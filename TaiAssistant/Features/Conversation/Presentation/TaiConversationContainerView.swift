import SwiftUI

/// Tai tab root: binds to the process-wide Conversation session (load-once).
struct TaiConversationContainerView: View {
    let conversationSession: ActiveConversationSessionController
    let goalRepository: GoalRepository
    let aiService: AIService
    let ownerID: String
    let assistantName: String
    var analytics: any AnalyticsClient = NoOpAnalyticsClient()
    var launchIntent: TaiLaunchIntent?
    var onLaunchIntentConsumed: (() -> Void)? = nil

    @State private var isGoalsPresented = false
    @State private var isConsentPresented = false

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
        aiService: MockAIService(),
        ownerID: "preview.user",
        assistantName: "Tai"
    )
    return NavigationStack {
        TaiConversationContainerView(
            conversationSession: session,
            goalRepository: MockGoalRepository(),
            aiService: MockAIService(),
            ownerID: "preview.user",
            assistantName: "Tai"
        )
    }
}
