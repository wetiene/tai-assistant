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
    private let aiService: AIService
    private let ownerID: String
    private let assistantName: String
    private var onMealSaved: (() -> Void)?
    private var loadTask: Task<Void, Never>?
    private var didLoad = false

    init(
        conversationRepository: ActiveConversationRepository,
        mealRepository: MealRepository,
        aiService: AIService,
        ownerID: String,
        assistantName: String,
        onMealSaved: (() -> Void)? = nil
    ) {
        self.conversationRepository = conversationRepository
        self.mealRepository = mealRepository
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
            let restored = try conversationRepository.loadOrCreateActive(ownerID: ownerID)
            ConversationStartupProbe.recordLoadOrCreate(
                durationMilliseconds: (CFAbsoluteTimeGetCurrent() - loadStarted) * 1000
            )

            let store = ConversationSessionStore(seed: restored)
            store.suppressPersistence = true
            store.onPersist = { [conversationRepository, ownerID] conversation in
                ConversationStartupProbe.recordPersist()
                try? conversationRepository.saveActive(conversation, ownerID: ownerID)
            }
            store.onPersistComposer = { [conversationRepository, ownerID] draft in
                ConversationStartupProbe.recordComposerPersist()
                try? conversationRepository.saveComposerDraft(draft, ownerID: ownerID)
            }

            let meal = MealCapabilityController(
                mealRepository: mealRepository,
                ownerID: ownerID,
                interpreter: AIServiceCheckInInterpreter(aiService: aiService, ownerID: ownerID)
            )
            meal.restoreFromConversation(restored)

            let vm = ConversationViewModel(
                store: store,
                meal: meal,
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
        switch intent {
        case .openConversation:
            viewModel.startIfNeeded()
        case .startMealCapture:
            viewModel.applyMealIntent()
        case .focusComposer:
            viewModel.startIfNeeded()
        }
    }
}
