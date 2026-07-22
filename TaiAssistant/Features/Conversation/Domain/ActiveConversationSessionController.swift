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
    private let goalRepository: GoalRepository
    private let aiService: AIService
    private let ownerID: String
    private let assistantName: String
    private var onMealSaved: (() -> Void)?
    private var loadTask: Task<Void, Never>?
    private var didLoad = false
    private var persistCoordinator: ConversationPersistCoordinator?

    init(
        conversationRepository: ActiveConversationRepository,
        mealRepository: MealRepository,
        goalRepository: GoalRepository,
        aiService: AIService,
        ownerID: String,
        assistantName: String,
        onMealSaved: (() -> Void)? = nil
    ) {
        self.conversationRepository = conversationRepository
        self.mealRepository = mealRepository
        self.goalRepository = goalRepository
        self.aiService = aiService
        self.ownerID = ownerID
        self.assistantName = assistantName
        self.onMealSaved = onMealSaved
    }

    func updateOnMealSaved(_ handler: (() -> Void)?) {
        onMealSaved = handler
        viewModel?.onMealSaved = handler
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

            let liveTai = LiveTaiCapabilityController(
                mealRepository: mealRepository,
                goalRepository: goalRepository,
                aiService: aiService,
                ownerID: ownerID
            )

            let vm = ConversationViewModel(
                store: store,
                meal: meal,
                liveTai: liveTai,
                assistantName: assistantName,
                onMealSaved: onMealSaved
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
        // `intent.dayContext` is wired for later historical-logging slices; meal capture still defaults to today.
        switch intent.kind {
        case .openConversation:
            viewModel.startIfNeeded()
        case .startMealCapture:
            viewModel.applyMealIntent()
        case .focusComposer:
            viewModel.startIfNeeded()
        }
    }
}
