import Foundation
import Observation

/// Owns the single in-memory Conversation session for the app process.
/// Loads/restores at most once; shared by the Tai tab so SwiftUI recomputation cannot re-bootstrap.
@MainActor
@Observable
final class ActiveConversationSessionController {
    private(set) var viewModel: ConversationViewModel?
    private(set) var isLoading = false
    private(set) var loadError: String?

    private let conversationRepository: ActiveConversationRepository
    private let mealRepository: MealRepository
    private let workoutRepository: WorkoutRepository
    private let gymPlanRepository: GymPlanRepository
    private let goalRepository: GoalRepository
    private let aiService: AIService
    private let ownerID: String
    private let assistantName: String
    private var onMealSaved: (() -> Void)?
    private var onWorkoutSaved: (() -> Void)?
    private var onManageGymPlans: (() -> Void)?
    private var onPresentGymPlanImportReview: ((GymPlanImportDraft, String?) -> Void)?
    private var onPresentStrengthWorkout: ((StrengthWorkoutPresentation) -> Void)?
    private var strengthWorkoutCoordinator: StrengthWorkoutCoordinator?
    private weak var strengthWorkoutEntryRouter: StrengthWorkoutEntryRouter?
    private var loadTask: Task<Void, Never>?
    private var didLoad = false
    private var persistCoordinator: ConversationPersistCoordinator?

    init(
        conversationRepository: ActiveConversationRepository,
        mealRepository: MealRepository,
        workoutRepository: WorkoutRepository,
        gymPlanRepository: GymPlanRepository,
        goalRepository: GoalRepository,
        aiService: AIService,
        ownerID: String,
        assistantName: String,
        onMealSaved: (() -> Void)? = nil,
        onWorkoutSaved: (() -> Void)? = nil
    ) {
        self.conversationRepository = conversationRepository
        self.mealRepository = mealRepository
        self.workoutRepository = workoutRepository
        self.gymPlanRepository = gymPlanRepository
        self.goalRepository = goalRepository
        self.aiService = aiService
        self.ownerID = ownerID
        self.assistantName = assistantName
        self.onMealSaved = onMealSaved
        self.onWorkoutSaved = onWorkoutSaved
    }

    func updateOnMealSaved(_ handler: (() -> Void)?) {
        onMealSaved = handler
        viewModel?.onMealSaved = handler
    }

    func updateOnWorkoutSaved(_ handler: (() -> Void)?) {
        onWorkoutSaved = handler
        viewModel?.onWorkoutSaved = handler
    }

    func updateOnManageGymPlans(_ handler: (() -> Void)?) {
        onManageGymPlans = handler
        viewModel?.onManageGymPlans = handler
    }

    func updateOnPresentGymPlanImportReview(_ handler: ((GymPlanImportDraft, String?) -> Void)?) {
        onPresentGymPlanImportReview = handler
        viewModel?.onPresentGymPlanImportReview = handler
    }

    func updateStrengthWorkoutEntryRouting(
        coordinator: StrengthWorkoutCoordinator,
        router: StrengthWorkoutEntryRouter,
        onPresent: @escaping (StrengthWorkoutPresentation) -> Void
    ) {
        strengthWorkoutCoordinator = coordinator
        strengthWorkoutEntryRouter = router
        onPresentStrengthWorkout = onPresent
        viewModel?.strengthWorkoutCoordinator = coordinator
        viewModel?.onPresentStrengthWorkout = onPresent
        viewModel?.onRequestStrengthWorkoutStart = { [weak router] target, source in
            Task { await router?.requestStart(target: target, source: source) }
        }
        viewModel?.onRequestStrengthWorkoutResume = { [weak router] source in
            Task { await router?.requestResume(source: source) }
        }
    }

    /// Retained for tests and legacy wiring.
    func updateStrengthWorkoutRouting(
        coordinator: StrengthWorkoutCoordinator,
        onPresent: @escaping (StrengthWorkoutPresentation) -> Void
    ) {
        strengthWorkoutCoordinator = coordinator
        onPresentStrengthWorkout = onPresent
        viewModel?.strengthWorkoutCoordinator = coordinator
        viewModel?.onPresentStrengthWorkout = onPresent
    }

    /// Idempotent: first call starts restore; later calls await the same load.
    func ensureLoaded() async {
        if didLoad { return }
        if let loadTask {
            await loadTask.value
            return
        }
        let task = Task { @MainActor in
            await self.performLoad()
        }
        loadTask = task
        await task.value
    }

    func deliver(_ intent: TaiLaunchIntent) {
        guard let viewModel else { return }
        apply(intent, to: viewModel)
    }

    /// Waits for the single conversation bootstrap, then applies a launch intent once.
    func deliverWhenReady(_ intent: TaiLaunchIntent) async {
        await ensureLoaded()
        deliver(intent)
    }

    func refreshStrengthAfterDedicatedDismiss() async {
        await viewModel?.refreshStrengthSessionFromRepository()
    }

    // MARK: - Private

    private func performLoad() async {
        guard !didLoad else { return }
        isLoading = true
        loadError = nil
        ConversationStartupProbe.resetSession()
        ConversationStartupProbe.isBootstrapping = true
        defer {
            ConversationStartupProbe.isBootstrapping = false
            isLoading = false
        }

        // Let the shell / Home paint before Conversation disk work.
        await Task.yield()

        do {
            let loadStarted = CFAbsoluteTimeGetCurrent()
            let repository = conversationRepository
            let owner = ownerID
            // Decode + attachment migration off the MainActor; hop back for UI wiring.
            let restored: ActiveConversation = try await withCheckedThrowingContinuation { continuation in
                DispatchQueue.global(qos: .userInitiated).async {
                    do {
                        let value = try repository.loadOrCreateActive(ownerID: owner)
                        continuation.resume(returning: value)
                    } catch {
                        continuation.resume(throwing: error)
                    }
                }
            }
            ConversationStartupProbe.recordLoadOrCreate(
                durationMilliseconds: (CFAbsoluteTimeGetCurrent() - loadStarted) * 1000
            )

            let coordinator = ConversationPersistCoordinator(
                repository: conversationRepository,
                ownerID: ownerID
            )
            persistCoordinator = coordinator

            let store = ConversationSessionStore(seed: restored)
            store.suppressPersistence = true
            store.onPersist = { conversation in
                coordinator.enqueueActive(conversation)
            }
            store.onPersistComposer = { draft in
                coordinator.enqueueComposer(draft)
            }

            let meal = MealCapabilityController(
                mealRepository: mealRepository,
                ownerID: ownerID,
                interpreter: AIServiceCheckInInterpreter(aiService: aiService, ownerID: ownerID)
            )
            meal.restoreFromConversation(restored)

            let gym = GymCapabilityController(
                workoutRepository: workoutRepository,
                aiService: aiService,
                ownerID: ownerID
            )
            await gym.restoreFromConversation(restored)

            let strengthConversation = StrengthConversationController(
                workoutRepository: workoutRepository,
                gymPlanRepository: gymPlanRepository,
                aiService: aiService,
                ownerID: ownerID
            )
            await strengthConversation.restoreFromConversation(restored)

            let liveTai = LiveTaiCapabilityController(
                mealRepository: mealRepository,
                goalRepository: goalRepository,
                aiService: aiService,
                ownerID: ownerID
            )

            let vm = ConversationViewModel(
                store: store,
                meal: meal,
                gym: gym,
                strengthConversation: strengthConversation,
                liveTai: liveTai,
                gymPlanRepository: gymPlanRepository,
                aiService: aiService,
                ownerID: ownerID,
                assistantName: assistantName,
                onMealSaved: onMealSaved,
                onWorkoutSaved: onWorkoutSaved,
                onManageGymPlans: onManageGymPlans,
                onPresentGymPlanImportReview: onPresentGymPlanImportReview,
                onPresentStrengthWorkout: onPresentStrengthWorkout,
                strengthWorkoutCoordinator: strengthWorkoutCoordinator
            )
            let beforeSeed = store.active
            vm.startIfNeeded()
            let seededGreeting = store.active != beforeSeed

            // End bootstrap before the optional one-shot greeting save so probes
            // only flag uncontrolled onPersist cascades during restore.
            ConversationStartupProbe.isBootstrapping = false
            store.suppressPersistence = false
            if seededGreeting {
                try conversationRepository.saveActive(store.snapshotIncludingComposer, ownerID: ownerID)
            }

            viewModel = vm
            didLoad = true
        } catch {
            loadError = "Tai couldn’t restore your conversation. Please relaunch the app."
            loadTask = nil
        }
    }

    private func apply(_ intent: TaiLaunchIntent, to viewModel: ConversationViewModel) {
        if let dayContext = intent.dayContext {
            viewModel.setNutritionDayContext(dayContext)
        }
        switch intent.kind {
        case .openConversation:
            viewModel.startIfNeeded()
        case .startMealCapture:
            viewModel.applyMealIntent(dayContext: intent.dayContext)
        case .focusComposer:
            viewModel.startIfNeeded()
        case .startConversationalStrength:
            viewModel.startIfNeeded()
            Task { await viewModel.beginConversationalStrengthFromHome() }
        case .resumeConversationalStrength:
            viewModel.startIfNeeded()
            Task { await viewModel.resumeConversationalStrengthFromHome() }
        case .startGymWorkout(let target):
            viewModel.startIfNeeded()
            Task { await viewModel.beginConversationalStrengthWorkout(target: target, entrySource: .home) }
        case .resumeGymWorkout:
            viewModel.startIfNeeded()
            Task { await viewModel.resumeConversationalStrengthFromHome() }
        case .manageGymPlans:
            viewModel.onManageGymPlans?()
        }
    }
}
