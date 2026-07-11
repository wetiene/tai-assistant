import SwiftUI

struct HomeBriefingView: View {
    let mealRepository: MealRepository
    let goalRepository: GoalRepository
    let ownerID: String
    let assistantName: String
    var displayName: String? = nil
    var mealAddedFeedbackTrigger: Int = 0
    var analytics: any AnalyticsClient = NoOpAnalyticsClient()
    var onPrimaryAction: ((RecommendationActionDestination) -> Void)? = nil

    @State private var briefing: DailyCoachBriefing?
    @State private var todaysMeals: [HomeMealSummary] = []
    @State private var cachedGoal: GoalProfile?
    @State private var cachedTargets: DailyTargets?
    @State private var isLoading = false
    @State private var loadError: String?
    @State private var showsMealAddedFeedback = false
    @State private var isWhyPresented = false
    @State private var pendingUndoMeal: HomeMealRestorePayload?
    @State private var actionError: String?
    @State private var addFeedbackDismissTask: Task<Void, Never>?
    @State private var undoDismissTask: Task<Void, Never>?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DSSpacing.xl) {
                header

                if let loadError {
                    inlineFeedback(message: loadError, icon: "exclamationmark.triangle.fill", tint: DSColor.destructiveCoral)
                    Button("Try again") {
                        Task { await loadHome() }
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(DSColor.coralEnd)
                    .buttonStyle(.plain)
                }

                if showsMealAddedFeedback {
                    inlineFeedback(message: "Meal added", icon: "checkmark.circle.fill", tint: DSColor.coralEnd)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }

                if let actionError {
                    inlineFeedback(message: actionError, icon: "exclamationmark.triangle.fill", tint: DSColor.destructiveCoral)
                }

                if let briefing {
                    briefingHero(briefing)
                    focusCard(briefing)
                    compactProgress(briefing.progress)
                    recentCheckIns
                    if let note = briefing.dataSufficiencyNote {
                        Text(note)
                            .font(.caption)
                            .foregroundStyle(DSColor.textSecondary)
                    }
                } else if isLoading {
                    ProgressView("Preparing today’s briefing…")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                NutritionEstimateDisclaimer()
                    .padding(.top, DSSpacing.xs)
            }
            .padding(DSSpacing.lg)
            .padding(.bottom, DSSpacing.xl)
        }
        .background(DSColor.background.ignoresSafeArea())
        .task {
            analytics.track(.homeViewed)
            await loadHome()
        }
        .refreshable {
            await loadHome()
        }
        .onChange(of: mealAddedFeedbackTrigger) { _, _ in
            showMealAddedFeedback()
            Task { await loadHome() }
        }
        .sheet(isPresented: $isWhyPresented) {
            if let recommendation = briefing?.recommendation {
                RecommendationWhySheet(
                    recommendation: recommendation,
                    assistantName: assistantName,
                    onDismiss: { isWhyPresented = false }
                )
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: DSSpacing.xs) {
            Text(assistantName)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(DSColor.coralEnd)
            Text(briefing?.greeting ?? timeFallbackGreeting)
                .font(.largeTitle.weight(.bold))
                .foregroundStyle(DSColor.textPrimary)
                .accessibilityAddTraits(.isHeader)
        }
    }

    private var timeFallbackGreeting: String {
        DailyCoachBriefingBuilder.makeGreeting(now: .now, calendar: .current, displayName: displayName)
    }

    @ViewBuilder
    private func briefingHero(_ briefing: DailyCoachBriefing) -> some View {
        VStack(alignment: .leading, spacing: DSSpacing.md) {
            Text(briefing.headline)
                .font(.title2.weight(.bold))
                .foregroundStyle(DSColor.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Text(briefing.body)
                .font(.body)
                .foregroundStyle(DSColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func focusCard(_ briefing: DailyCoachBriefing) -> some View {
        PrimaryCard(cornerRadius: 24, useWarmBackground: true) {
            Text("Today’s focus")
                .font(.caption.weight(.semibold))
                .foregroundStyle(DSColor.coralEnd)
            Text(briefing.recommendation.focusTitle)
                .font(.title3.weight(.bold))
                .foregroundStyle(DSColor.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            Button {
                analytics.track(.homePrimaryActionTapped)
                onPrimaryAction?(briefing.recommendation.destination)
            } label: {
                Text(briefing.recommendation.actionTitle)
            }
            .buttonStyle(CoralGradientButtonStyle())
            .accessibilityHint("Opens \(briefing.recommendation.actionTitle)")

            Button {
                analytics.track(.homeWhyTapped)
                isWhyPresented = true
            } label: {
                Label("Why this?", systemImage: "info.circle")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(DSColor.coralEnd)
            }
            .buttonStyle(.plain)
            .accessibilityHint("Explains how Tai chose this recommendation")
        }
    }

    @ViewBuilder
    private func compactProgress(_ progress: NutritionProgressSnapshot) -> some View {
        VStack(alignment: .leading, spacing: DSSpacing.md) {
            Text("Today’s progress")
                .font(.headline)
                .foregroundStyle(DSColor.textPrimary)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: DSSpacing.md) {
                progressChip(label: "Calories", value: "\(progress.caloriesConsumed)/\(max(progress.calorieTarget, 0))")
                progressChip(label: "Protein", value: "\(progress.proteinConsumed)/\(max(progress.proteinTarget, 0))g")
                progressChip(label: "Carbs", value: "\(progress.carbsConsumed)/\(max(progress.carbsTarget, 0))g")
                progressChip(label: "Fat", value: "\(progress.fatConsumed)/\(max(progress.fatTarget, 0))g")
            }
        }
        .accessibilityElement(children: .contain)
    }

    private func progressChip(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption)
                .foregroundStyle(DSColor.textSecondary)
            Text(value)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(DSColor.textPrimary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(DSSpacing.md)
        .background(DSColor.surface)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(DSColor.cardStroke, lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label) \(value)")
    }

    private var recentCheckIns: some View {
        VStack(alignment: .leading, spacing: DSSpacing.md) {
            HStack {
                Text("Recent check-ins")
                    .font(.headline)
                    .foregroundStyle(DSColor.textPrimary)
                Spacer()
                if pendingUndoMeal != nil {
                    Button("Undo") {
                        Task { await undoDeleteMeal() }
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(DSColor.coralEnd)
                }
            }

            if todaysMeals.isEmpty {
                Text("No meals logged today yet.")
                    .font(.subheadline)
                    .foregroundStyle(DSColor.textSecondary)
            } else {
                ForEach(todaysMeals) { meal in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(meal.label)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(DSColor.textPrimary)
                            Text(meal.eatenAt, style: .time)
                                .font(.caption)
                                .foregroundStyle(DSColor.textSecondary)
                        }
                        Spacer()
                        Text("\(meal.calories) kcal")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(DSColor.textSecondary)
                        Button {
                            deleteMeal(meal)
                        } label: {
                            Image(systemName: "trash")
                                .foregroundStyle(DSColor.destructiveCoral)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Delete \(meal.label)")
                    }
                    .padding(.vertical, DSSpacing.xs)
                }
            }
        }
    }

    private func inlineFeedback(message: String, icon: String, tint: Color) -> some View {
        Label(message, systemImage: icon)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(tint)
            .padding(DSSpacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(tint.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    @MainActor
    private func loadHome() async {
        isLoading = briefing == nil
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

            let input = CoachBriefingInputFactory.make(
                displayName: displayName,
                goal: goal,
                targets: targets,
                todaysMeals: meals,
                assistantName: assistantName
            )
            cachedGoal = goal
            cachedTargets = targets
            briefing = DailyCoachBriefingBuilder.build(input)
            todaysMeals = meals
                .sorted { $0.eatenAt > $1.eatenAt }
                .map { HomeMealSummary(meal: $0) }
        } catch {
            loadError = "Couldn’t load today’s briefing. Pull to refresh."
        }
        isLoading = false
    }

    private func showMealAddedFeedback() {
        addFeedbackDismissTask?.cancel()
        withAnimation(.easeInOut(duration: 0.2)) {
            showsMealAddedFeedback = true
        }
        addFeedbackDismissTask = Task {
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                withAnimation(.easeInOut(duration: 0.2)) {
                    showsMealAddedFeedback = false
                }
            }
        }
    }

    private func deleteMeal(_ meal: HomeMealSummary) {
        pendingUndoMeal = meal.restorePayload
        todaysMeals.removeAll { $0.id == meal.id }
        recomputeBriefingFromLocalMeals()
        undoDismissTask?.cancel()
        undoDismissTask = Task {
            do {
                try await mealRepository.deleteMealLog(id: meal.id)
                try? await Task.sleep(nanoseconds: 4_000_000_000)
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    pendingUndoMeal = nil
                }
            } catch {
                await MainActor.run {
                    actionError = "Couldn’t delete that meal."
                    Task { await loadHome() }
                }
            }
        }
    }

    @MainActor
    private func undoDeleteMeal() async {
        guard let payload = pendingUndoMeal else { return }
        undoDismissTask?.cancel()
        pendingUndoMeal = nil
        let restored = HomeMealSummary(meal: payload.makeMealLog())
        todaysMeals.insert(restored, at: 0)
        todaysMeals.sort { $0.eatenAt > $1.eatenAt }
        recomputeBriefingFromLocalMeals()
        do {
            try await mealRepository.createMealLog(payload.makeMealLog())
        } catch {
            actionError = "Couldn’t undo that delete."
            await loadHome()
        }
    }

    /// Immediate local recompute so progress chips update without waiting on disk/reload.
    private func recomputeBriefingFromLocalMeals() {
        let mealLogs = todaysMeals.map { $0.restorePayload.makeMealLog() }
        let input = CoachBriefingInputFactory.make(
            displayName: displayName,
            goal: cachedGoal,
            targets: cachedTargets,
            todaysMeals: mealLogs,
            assistantName: assistantName
        )
        briefing = DailyCoachBriefingBuilder.build(input)
    }
}

// MARK: - Meal summaries

struct HomeMealSummary: Identifiable {
    let id: UUID
    let label: String
    let eatenAt: Date
    let calories: Int
    let restorePayload: HomeMealRestorePayload

    init(meal: MealLog) {
        id = meal.id
        let notes = meal.notes.trimmingCharacters(in: .whitespacesAndNewlines)
        label = notes.isEmpty ? meal.timing.rawValue.capitalized : notes
        eatenAt = meal.eatenAt
        calories = meal.items.reduce(0) { $0 + $1.calories }
        restorePayload = HomeMealRestorePayload(meal: meal)
    }
}

struct HomeMealRestorePayload {
    let id: UUID
    let ownerID: String
    let visibility: VisibilityScope
    let sharingGroupID: String?
    let eatenAt: Date
    let timing: MealTiming
    let notes: String
    let alcoholStandardDrinks: Double
    let createdAt: Date
    let updatedAt: Date
    let items: [HomeMealItemRestorePayload]

    init(meal: MealLog) {
        id = meal.id
        ownerID = meal.ownerID
        visibility = meal.visibility
        sharingGroupID = meal.sharingGroupID
        eatenAt = meal.eatenAt
        timing = meal.timing
        notes = meal.notes
        alcoholStandardDrinks = meal.alcoholStandardDrinks
        createdAt = meal.createdAt
        updatedAt = meal.updatedAt
        items = meal.items.map { HomeMealItemRestorePayload(item: $0) }
    }

    func makeMealLog() -> MealLog {
        let mealLog = MealLog(
            id: id,
            ownerID: ownerID,
            visibility: visibility,
            sharingGroupID: sharingGroupID,
            eatenAt: eatenAt,
            timing: timing,
            notes: notes,
            alcoholStandardDrinks: alcoholStandardDrinks,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
        mealLog.items = items.map { $0.makeMealItem() }
        return mealLog
    }
}

struct HomeMealItemRestorePayload {
    let id: UUID
    let name: String
    let amount: Double
    let unit: String
    let calories: Int
    let proteinGrams: Double
    let carbsGrams: Double
    let fatGrams: Double
    let fiberGrams: Double
    let alcoholGrams: Double

    init(item: MealItem) {
        id = item.id
        name = item.name
        amount = item.amount
        unit = item.unit
        calories = item.calories
        proteinGrams = item.proteinGrams
        carbsGrams = item.carbsGrams
        fatGrams = item.fatGrams
        fiberGrams = item.fiberGrams
        alcoholGrams = item.alcoholGrams
    }

    func makeMealItem() -> MealItem {
        MealItem(
            id: id,
            name: name,
            amount: amount,
            unit: unit,
            calories: calories,
            proteinGrams: proteinGrams,
            carbsGrams: carbsGrams,
            fatGrams: fatGrams,
            fiberGrams: fiberGrams,
            alcoholGrams: alcoholGrams
        )
    }
}

#Preview("Empty Home") {
    HomeBriefingView(
        mealRepository: MockMealRepository(),
        goalRepository: MockGoalRepository(),
        ownerID: "preview.user",
        assistantName: "Tai"
    )
}

#Preview("Home after one meal / protein gap") {
    let briefing = DailyCoachBriefingBuilder.build(
        CoachBriefingInput(
            now: .now,
            calendar: .current,
            displayName: "Alex",
            hasActiveGoal: true,
            targets: CoachMacroTargets(calories: 2100, proteinGrams: 170, carbsGrams: 210, fatGrams: 70),
            todayMealCount: 1,
            caloriesConsumed: 520,
            proteinGramsConsumed: 28,
            carbsGramsConsumed: 55,
            fatGramsConsumed: 18,
            assistantName: "Tai"
        )
    )
    previewBriefingCanvas(briefing)
}

#Preview("Home broadly on track") {
    let briefing = DailyCoachBriefingBuilder.build(
        CoachBriefingInput(
            now: .now,
            calendar: .current,
            displayName: nil,
            hasActiveGoal: true,
            targets: CoachMacroTargets(calories: 2100, proteinGrams: 170, carbsGrams: 210, fatGrams: 70),
            todayMealCount: 2,
            caloriesConsumed: 1100,
            proteinGramsConsumed: 140,
            carbsGramsConsumed: 120,
            fatGramsConsumed: 40,
            assistantName: "Tai"
        )
    )
    previewBriefingCanvas(briefing)
}

#Preview("Home dark mode") {
    let briefing = DailyCoachBriefingBuilder.build(
        CoachBriefingInput(
            now: .now,
            calendar: .current,
            displayName: "Alex",
            hasActiveGoal: true,
            targets: CoachMacroTargets(calories: 2100, proteinGrams: 170, carbsGrams: 210, fatGrams: 70),
            todayMealCount: 2,
            caloriesConsumed: 900,
            proteinGramsConsumed: 62,
            carbsGramsConsumed: 80,
            fatGramsConsumed: 30,
            assistantName: "Tai"
        )
    )
    previewBriefingCanvas(briefing)
        .preferredColorScheme(.dark)
}

#Preview("Home large Dynamic Type") {
    let briefing = DailyCoachBriefingBuilder.build(
        CoachBriefingInput(
            now: .now,
            calendar: .current,
            displayName: "Alex",
            hasActiveGoal: false,
            targets: nil,
            todayMealCount: 0,
            caloriesConsumed: 0,
            proteinGramsConsumed: 0,
            carbsGramsConsumed: 0,
            fatGramsConsumed: 0,
            assistantName: "Tai"
        )
    )
    previewBriefingCanvas(briefing)
        .environment(\.sizeCategory, .accessibilityExtraExtraLarge)
}

@MainActor
private func previewBriefingCanvas(_ briefing: DailyCoachBriefing) -> some View {
    ScrollView {
        VStack(alignment: .leading, spacing: DSSpacing.xl) {
            Text(briefing.greeting)
                .font(.largeTitle.weight(.bold))
            Text(briefing.headline)
                .font(.title2.weight(.bold))
            Text(briefing.body)
                .foregroundStyle(DSColor.textSecondary)
            PrimaryCard(cornerRadius: 24, useWarmBackground: true) {
                Text("Today’s focus")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(DSColor.coralEnd)
                Text(briefing.recommendation.focusTitle)
                    .font(.title3.weight(.bold))
                Button(briefing.recommendation.actionTitle) {}
                    .buttonStyle(CoralGradientButtonStyle())
            }
        }
        .padding(DSSpacing.lg)
    }
    .background(DSColor.background.ignoresSafeArea())
}
