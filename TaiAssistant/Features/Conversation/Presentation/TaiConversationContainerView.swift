import SwiftUI

/// Tai tab root: binds to the process-wide Conversation session (load-once).
struct TaiConversationContainerView: View {
    let conversationSession: ActiveConversationSessionController
    let goalRepository: GoalRepository
    let gymPlanRepository: GymPlanRepository
    let aiService: AIService
    let ownerID: String
    let assistantName: String
    var analytics: any AnalyticsClient = NoOpAnalyticsClient()
    var launchIntent: TaiLaunchIntent?
    var onLaunchIntentConsumed: (() -> Void)? = nil
    var onManageGymPlans: (() -> Void)? = nil
    var onStartWorkout: ((GymPlanWorkoutTarget) -> Void)? = nil

    @State private var isGoalsPresented = false
    @State private var isGymPlansPresented = false
    @State private var isConsentPresented = false
    @State private var pendingGymPlanImportReview: (draft: GymPlanImportDraft, sourceText: String?)?

    var body: some View {
        Group {
            if let viewModel = conversationSession.viewModel {
                ConversationView(viewModel: viewModel)
            } else if let loadError = conversationSession.loadError {
                ContentUnavailableView(
                    "Couldn’t restore conversation",
                    systemImage: "exclamationmark.bubble",
                    description: Text(loadError)
                )
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(DSColor.background.ignoresSafeArea())
            }
        }
        .navigationTitle(assistantName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        analytics.track(.taiGoalSelected)
                        isGoalsPresented = true
                    } label: {
                        Label("Goals", systemImage: "target")
                    }
                    Button {
                        isGymPlansPresented = true
                    } label: {
                        Label("Gym Plans", systemImage: "list.bullet.rectangle")
                    }
                    Button {
                        isConsentPresented = true
                    } label: {
                        Label("AI consent", systemImage: "hand.raised.fill")
                    }
                    Link(destination: AppLegalLinks.privacyPolicyURL) {
                        Label("Privacy Policy", systemImage: "doc.text")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .accessibilityLabel("More")
            }
        }
        .task {
            analytics.track(.taiConversationViewed)
            conversationSession.updateOnManageGymPlans {
                if let onManageGymPlans {
                    onManageGymPlans()
                } else {
                    isGymPlansPresented = true
                }
            }
            conversationSession.updateOnPresentGymPlanImportReview { draft, sourceText in
                pendingGymPlanImportReview = (draft, sourceText)
                isGymPlansPresented = true
            }
            await conversationSession.ensureLoaded()
            consumeLaunchIntentIfNeeded()
        }
        .onChange(of: launchIntent) { _, _ in
            consumeLaunchIntentIfNeeded()
        }
        .sheet(isPresented: $isGoalsPresented) {
            NavigationStack {
                GoalsView(
                    goalRepository: goalRepository,
                    aiService: aiService,
                    ownerID: ownerID,
                    localeIdentifier: Locale.current.identifier,
                    timeZoneIdentifier: TimeZone.current.identifier
                )
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Done") { isGoalsPresented = false }
                    }
                }
            }
        }
        .sheet(isPresented: $isGymPlansPresented) {
            NavigationStack {
                GymPlansView(
                    gymPlanRepository: gymPlanRepository,
                    aiService: aiService,
                    ownerID: ownerID,
                    importRequestContext: RuntimeAppConfig.default.gymPlanImportRequestContext(
                        sourceType: .text,
                        sourceTextCharacterCount: 0,
                        knownExerciseCount: GymExerciseID.allCases.count
                    ),
                    pendingImportReview: pendingGymPlanImportReview,
                    onStartWorkout: { target in
                        isGymPlansPresented = false
                        pendingGymPlanImportReview = nil
                        onStartWorkout?(target)
                    },
                    onDismiss: {
                        isGymPlansPresented = false
                        pendingGymPlanImportReview = nil
                    }
                )
            }
        }
        .sheet(isPresented: $isConsentPresented) {
            AIDataProcessingConsentSheet(
                onAccept: { isConsentPresented = false },
                onDecline: { isConsentPresented = false }
            )
        }
    }

    private func consumeLaunchIntentIfNeeded() {
        guard let launchIntent else { return }
        guard conversationSession.viewModel != nil else { return }
        conversationSession.deliver(launchIntent)
        onLaunchIntentConsumed?()
    }
}

#Preview("Tai conversation") {
    let session = ActiveConversationSessionController(
        conversationRepository: InMemoryActiveConversationRepository(),
        mealRepository: MockMealRepository(),
        workoutRepository: MockWorkoutRepository(),
        gymPlanRepository: MockGymPlanRepository(),
        goalRepository: MockGoalRepository(),
        aiService: MockAIService(),
        ownerID: "preview.user",
        assistantName: "Tai"
    )
    NavigationStack {
        TaiConversationContainerView(
            conversationSession: session,
            goalRepository: MockGoalRepository(),
            gymPlanRepository: MockGymPlanRepository(),
            aiService: MockAIService(),
            ownerID: "preview.user",
            assistantName: "Tai"
        )
    }
}
