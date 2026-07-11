import SwiftUI

/// Tai tab root: active conversation first; Goals / privacy reachable without becoming primary IA.
struct TaiConversationContainerView: View {
    let mealRepository: MealRepository
    let goalRepository: GoalRepository
    let aiService: AIService
    let ownerID: String
    let assistantName: String
    var analytics: any AnalyticsClient = NoOpAnalyticsClient()
    var mealIntentToken: Int = 0
    var onMealSaved: (() -> Void)? = nil

    @State private var viewModel: ConversationViewModel?
    @State private var isGoalsPresented = false
    @State private var isConsentPresented = false

    var body: some View {
        Group {
            if let viewModel {
                ConversationView(viewModel: viewModel)
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
            if viewModel == nil {
                let meal = MealCapabilityController(
                    mealRepository: mealRepository,
                    ownerID: ownerID,
                    interpreter: AIServiceCheckInInterpreter(aiService: aiService, ownerID: ownerID)
                )
                let vm = ConversationViewModel(
                    store: ConversationSessionStore(),
                    meal: meal,
                    assistantName: assistantName,
                    onMealSaved: onMealSaved
                )
                vm.startIfNeeded()
                viewModel = vm
            }
        }
        .onChange(of: mealIntentToken) { _, _ in
            viewModel?.applyMealIntent()
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
}

#Preview("Tai conversation") {
    NavigationStack {
        TaiConversationContainerView(
            mealRepository: MockMealRepository(),
            goalRepository: MockGoalRepository(),
            aiService: MockAIService(),
            ownerID: "preview.user",
            assistantName: "Tai"
        )
    }
}
