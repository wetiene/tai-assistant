import SwiftUI

struct CoachView: View {
    let mealRepository: MealRepository
    let goalRepository: GoalRepository
    let aiService: AIService
    let askTaiGuidance: any AskTaiGuidanceService
    let ownerID: String
    let assistantName: String
    var isAskTaiPreview: Bool = true
    var displayName: String? = nil
    var analytics: any AnalyticsClient = NoOpAnalyticsClient()
    var onAskTaiRequested: (() -> Void)? = nil

    @State private var briefing: DailyCoachBriefing?
    @State private var activeGoalTitle: String?
    @State private var activeTargetsSummary: String?
    @State private var loadError: String?
    @State private var isAIConsentPresented = false

    var body: some View {
        List {
            Section {
                coachingSummarySection
            }

            Section {
                NavigationLink {
                    GoalsView(
                        goalRepository: goalRepository,
                        aiService: aiService,
                        ownerID: ownerID,
                        localeIdentifier: Locale.current.identifier,
                        timeZoneIdentifier: TimeZone.current.identifier
                    )
                } label: {
                    goalRow
                }
                .simultaneousGesture(TapGesture().onEnded {
                    analytics.track(.coachGoalSelected)
                })
            } header: {
                Text("Goal")
            }

            Section {
                Button {
                    analytics.track(.coachAskTaiSelected)
                    onAskTaiRequested?()
                } label: {
                    HStack(spacing: DSSpacing.md) {
                        Label {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(isAskTaiPreview ? "Ask \(assistantName) Preview" : "Ask \(assistantName)")
                                    .foregroundStyle(DSColor.textPrimary)
                                Text(isAskTaiPreview ? "Sample coaching responses — not live AI" : "Ask a coaching question")
                                    .font(.caption)
                                    .foregroundStyle(DSColor.textSecondary)
                            }
                        } icon: {
                            Image(systemName: "bubble.left.and.bubble.right.fill")
                                .foregroundStyle(DSColor.coralEnd)
                        }
                        Spacer()
                        if isAskTaiPreview {
                            PreviewFeatureBadge()
                        }
                    }
                }
            } header: {
                Text("Conversation")
            }

            if let briefing {
                Section {
                    progressSummary(briefing.progress)
                } header: {
                    Text("Today")
                }
            }

            Section {
                Button {
                    isAIConsentPresented = true
                } label: {
                    Label("AI processing consent", systemImage: "hand.raised.fill")
                }

                Link(destination: AppLegalLinks.privacyPolicyURL) {
                    Label("Privacy Policy", systemImage: "doc.text")
                }
            } header: {
                Text("Settings & privacy")
            } footer: {
                Text("Required legal controls stay available here. Sleep and weight stay unavailable until a trusted health source is connected — they are not logged manually.")
            }
        }
        .listStyle(.insetGrouped)
        .background(DSColor.background.ignoresSafeArea())
        .navigationTitle("Coach")
        .task {
            analytics.track(.coachViewed)
            await loadCoach()
        }
        .refreshable {
            await loadCoach()
        }
        .sheet(isPresented: $isAIConsentPresented) {
            AIDataProcessingConsentSheet(
                onAccept: { isAIConsentPresented = false },
                onDecline: { isAIConsentPresented = false }
            )
        }
    }

    @ViewBuilder
    private var coachingSummarySection: some View {
        VStack(alignment: .leading, spacing: DSSpacing.sm) {
            Text(assistantName)
                .font(.caption.weight(.semibold))
                .foregroundStyle(DSColor.coralEnd)
            if let briefing {
                Text(briefing.headline)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(DSColor.textPrimary)
                Text(briefing.body)
                    .font(.subheadline)
                    .foregroundStyle(DSColor.textSecondary)
                Text("Focus: \(briefing.recommendation.focusTitle)")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(DSColor.coralEnd)
            } else if let loadError {
                Text(loadError)
                    .font(.subheadline)
                    .foregroundStyle(DSColor.destructiveCoral)
            } else {
                ProgressView()
            }
        }
        .padding(.vertical, DSSpacing.xs)
        .accessibilityElement(children: .combine)
    }

    private var goalRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let activeGoalTitle {
                Text(activeGoalTitle)
                    .font(.headline)
                    .foregroundStyle(DSColor.textPrimary)
                if let activeTargetsSummary {
                    Text(activeTargetsSummary)
                        .font(.caption)
                        .foregroundStyle(DSColor.textSecondary)
                }
                Text("Manage goal")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(DSColor.coralEnd)
            } else {
                Text("Set your goal")
                    .font(.headline)
                    .foregroundStyle(DSColor.textPrimary)
                Text("Tai uses your goal to tailor today’s guidance.")
                    .font(.caption)
                    .foregroundStyle(DSColor.textSecondary)
            }
        }
        .padding(.vertical, 2)
    }

    private func progressSummary(_ progress: NutritionProgressSnapshot) -> some View {
        VStack(alignment: .leading, spacing: DSSpacing.xs) {
            Text("\(progress.caloriesConsumed) / \(progress.calorieTarget) kcal")
            Text("Protein \(progress.proteinConsumed) / \(progress.proteinTarget)g")
            Text("\(progress.mealCountToday) meal\(progress.mealCountToday == 1 ? "" : "s") today")
        }
        .font(.subheadline)
        .foregroundStyle(DSColor.textSecondary)
        .accessibilityElement(children: .combine)
    }

    @MainActor
    private func loadCoach() async {
        loadError = nil
        do {
            let bounds = CoachBriefingInputFactory.dayBounds(for: .now)
            let meals = try await mealRepository.fetchMealLogs(ownerID: ownerID, from: bounds.start, to: bounds.end)
            let goals = try await goalRepository.fetchGoalProfiles(ownerID: ownerID)
            let goal = goals.sorted { $0.updatedAt > $1.updatedAt }.first
            var targets: DailyTargets?
            if let goal {
                targets = try await goalRepository.fetchDailyTargets(goalProfileID: goal.id)
            }

            activeGoalTitle = goal?.title
            if let targets {
                activeTargetsSummary = "\(targets.calories) kcal · \(Int(targets.proteinGrams.rounded()))g protein"
            } else {
                activeTargetsSummary = nil
            }

            let input = CoachBriefingInputFactory.make(
                displayName: displayName,
                goal: goal,
                targets: targets,
                todaysMeals: meals,
                assistantName: assistantName
            )
            briefing = DailyCoachBriefingBuilder.build(input)
        } catch {
            loadError = "Couldn’t load coaching summary."
        }
    }
}

#Preview("Coach with goal summary") {
    NavigationStack {
        CoachView(
            mealRepository: MockMealRepository(),
            goalRepository: MockGoalRepository(),
            aiService: MockAIService(),
            askTaiGuidance: MockAskTaiGuidanceService(),
            ownerID: "preview.user",
            assistantName: "Tai",
            isAskTaiPreview: true
        )
    }
}

#Preview("Coach without goal") {
    NavigationStack {
        CoachView(
            mealRepository: MockMealRepository(),
            goalRepository: MockGoalRepository(),
            aiService: MockAIService(),
            askTaiGuidance: MockAskTaiGuidanceService(),
            ownerID: "preview.user",
            assistantName: "Tai",
            isAskTaiPreview: true
        )
    }
}

#Preview("Coach dark") {
    NavigationStack {
        CoachView(
            mealRepository: MockMealRepository(),
            goalRepository: MockGoalRepository(),
            aiService: MockAIService(),
            askTaiGuidance: MockAskTaiGuidanceService(),
            ownerID: "preview.user",
            assistantName: "Tai",
            isAskTaiPreview: true
        )
    }
    .preferredColorScheme(.dark)
}
