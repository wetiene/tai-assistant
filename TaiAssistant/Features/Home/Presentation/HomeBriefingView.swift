import SwiftUI

struct HomeBriefingView: View {
    let mealRepository: MealRepository
    let workoutRepository: WorkoutRepository
    let gymPlanRepository: GymPlanRepository
    let goalRepository: GoalRepository
    @Bindable var nutritionDaySelection: NutritionDaySelection
    let ownerID: String
    let assistantName: String
    var displayName: String? = nil
    var mealAddedFeedbackTrigger: Int = 0
    var workoutAddedFeedbackTrigger: Int = 0
    var analytics: any AnalyticsClient = NoOpAnalyticsClient()
    var onPrimaryAction: ((RecommendationActionDestination) -> Void)? = nil
    var onOpenTai: (() -> Void)? = nil
    var onManageGymPlans: (() -> Void)? = nil
    var onStartStrengthWorkout: ((GymResolvablePlan, [StrengthProgressionProposal], [WorkoutSessionLog]) -> Void)? = nil
    var onResumeStrengthWorkout: (() -> Void)? = nil

    @State private var briefing: DailyCoachBriefing?
    @State private var strengthCardState: StrengthTrainingCardState?
    @State private var resolvedPlannedWorkout: GymResolvablePlan?
    @State private var strengthHistorySessions: [WorkoutSessionLog] = []
    @State private var inProgressStrengthSession: StrengthWorkoutSession?
    @State private var didAutoStartStrengthForUITest = false
    @State private var historicalSummary: HomeHistoricalDaySummary?
    @State private var displayedMeals: [HomeMealSummary] = []
    @State private var displayedWorkouts: [HomeWorkoutSummary] = []
    @State private var cachedGoal: GoalProfile?
    @State private var cachedTargets: DailyTargets?
    @State private var isLoading = false
    @State private var loadError: String?
    @State private var showsMealAddedFeedback = false
    @State private var isWhyPresented = false
    @State private var isDatePickerPresented = false
    @State private var datePickerDraft = Date.now
    @State private var pendingUndoMeal: HomeMealRestorePayload?
    @State private var actionError: String?
    @State private var addFeedbackDismissTask: Task<Void, Never>?
    @State private var undoDismissTask: Task<Void, Never>?
    @State private var loadGeneration: UInt64 = 0

    private var isViewingToday: Bool {
        nutritionDaySelection.isSelectedDayToday
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DSSpacing.xl) {
                dayNavigationBar
                header

                if !isViewingToday {
                    viewingHistoryBadge
                }

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

                if isViewingToday, let briefing {
                    if briefing.recommendation.destination != .reviewGoal {
                        briefingHero(briefing)
                    }
                    if let strengthCardState {
                        StrengthTrainingCardView(
                            state: strengthCardState,
                            onResume: { resumeStrengthWorkout() },
                            onStart: { startStrengthWorkout() }
                        )
                    }
                    focusCard(briefing)
                    compactProgress(briefing.progress, isToday: true)
                    mealsSection
                    workoutsSection
                    if let note = briefing.dataSufficiencyNote {
                        Text(note)
                            .font(.caption)
                            .foregroundStyle(DSColor.textSecondary)
                    }
                } else if let historicalSummary {
                    historicalSummaryCard(historicalSummary)
                    compactProgress(historicalSummary.progress, isToday: false)
                    mealsSection
                    workoutsSection
                    historicalTaiCard
                } else if isLoading {
                    ProgressView(HomeNutritionDayFormatting.loadingMessage(isToday: isViewingToday))
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
        .onChange(of: workoutAddedFeedbackTrigger) { _, _ in
            Task { await loadHome() }
        }
        .onChange(of: nutritionDaySelection.selectedDay) { _, _ in
            briefing = nil
            historicalSummary = nil
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
        .sheet(isPresented: $isDatePickerPresented) {
            HomeNutritionDayPickerSheet(
                selectedDate: $datePickerDraft,
                maximumDate: .now,
                onCancel: { isDatePickerPresented = false },
                onConfirm: {
                    nutritionDaySelection.select(containing: datePickerDraft)
                    isDatePickerPresented = false
                }
            )
        }
    }

    private var dayNavigationBar: some View {
        HomeDayNavigationBar(
            title: HomeNutritionDayFormatting.pickerLabel(
                for: nutritionDaySelection.selectedDay
            ),
            canGoForward: nutritionDaySelection.canSelectNextDay,
            showsTodayShortcut: !isViewingToday,
            onPreviousDay: { nutritionDaySelection.selectPreviousDay() },
            onNextDay: { _ = nutritionDaySelection.selectNextDay() },
            onSelectDate: {
                datePickerDraft = nutritionDaySelection.selectedDay.start
                isDatePickerPresented = true
            },
            onSelectToday: { nutritionDaySelection.selectToday() }
        )
    }

    private var viewingHistoryBadge: some View {
        Label("Viewing history", systemImage: "clock.arrow.circlepath")
            .font(.caption.weight(.semibold))
            .foregroundStyle(DSColor.textSecondary)
            .padding(.horizontal, DSSpacing.md)
            .padding(.vertical, DSSpacing.xs)
            .background(DSColor.surface)
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .stroke(DSColor.cardStroke, lineWidth: 1)
            )
            .accessibilityLabel("Viewing a past nutrition day")
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: DSSpacing.xs) {
            Text(assistantName)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(DSColor.coralEnd)
            Text(headerGreeting)
                .font(.largeTitle.weight(.bold))
                .foregroundStyle(DSColor.textPrimary)
                .accessibilityAddTraits(.isHeader)
        }
    }

    private var headerGreeting: String {
        if let historicalSummary {
            return historicalSummary.navigationTitle
        }
        return briefing?.greeting ?? timeFallbackGreeting
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
    private func historicalSummaryCard(_ summary: HomeHistoricalDaySummary) -> some View {
        VStack(alignment: .leading, spacing: DSSpacing.md) {
            Text(summary.headline)
                .font(.title2.weight(.bold))
                .foregroundStyle(DSColor.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Text(summary.body)
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

    private var historicalTaiCard: some View {
        PrimaryCard(cornerRadius: 24, useWarmBackground: true) {
            Text("Tai")
                .font(.caption.weight(.semibold))
                .foregroundStyle(DSColor.coralEnd)
            Text("Log a meal for this day")
                .font(.title3.weight(.bold))
                .foregroundStyle(DSColor.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Text("Describe or photograph what you ate. Tai will save it to this nutrition day.")
                .font(.subheadline)
                .foregroundStyle(DSColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            Button {
                analytics.track(.checkInMealSelected)
                onPrimaryAction?(.checkInMeal)
            } label: {
                Text("Log a meal")
            }
            .buttonStyle(CoralGradientButtonStyle())
            .accessibilityHint("Opens Tai to log a meal for the selected day")

            Button {
                onOpenTai?()
            } label: {
                Text("Open Tai")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(DSColor.coralEnd)
            }
            .buttonStyle(.plain)
            .accessibilityHint("Opens Tai with this day’s context")
        }
    }

    @ViewBuilder
    private func compactProgress(_ progress: NutritionProgressSnapshot, isToday: Bool) -> some View {
        VStack(alignment: .leading, spacing: DSSpacing.md) {
            Text(HomeNutritionDayFormatting.progressSectionTitle(isToday: isToday))
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

    private var mealsSection: some View {
        VStack(alignment: .leading, spacing: DSSpacing.md) {
            HStack {
                Text(HomeNutritionDayFormatting.mealsSectionTitle(isToday: isViewingToday))
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

            if displayedMeals.isEmpty {
                Text(HomeNutritionDayFormatting.emptyMealsMessage(isToday: isViewingToday))
                    .font(.subheadline)
                    .foregroundStyle(DSColor.textSecondary)
            } else {
                ForEach(displayedMeals) { meal in
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
        loadGeneration &+= 1
        let generation = loadGeneration
        let requestedDay = nutritionDaySelection.selectedDay
        let viewingToday = requestedDay.isToday()

        isLoading = briefing == nil && historicalSummary == nil
        loadError = nil
        do {
            let result = try await HomeNutritionDayLoader.load(
                day: requestedDay,
                ownerID: ownerID,
                mealRepository: mealRepository,
                goalRepository: goalRepository,
                displayName: displayName,
                assistantName: assistantName
            )
            guard generation == loadGeneration,
                  requestedDay == nutritionDaySelection.selectedDay else { return }

            cachedGoal = result.goal
            cachedTargets = result.targets
            briefing = result.todayBriefing
            historicalSummary = result.historicalSummary
            displayedMeals = result.mealSummaries
            displayedWorkouts = try await loadWorkoutSummaries(for: requestedDay)
            if viewingToday {
                try await loadStrengthTrainingCard()
            } else {
                strengthCardState = nil
            }
        } catch {
            guard generation == loadGeneration,
                  requestedDay == nutritionDaySelection.selectedDay else { return }
            loadError = HomeNutritionDayFormatting.loadErrorMessage(isToday: viewingToday)
        }
        isLoading = false
    }

    private func loadStrengthTrainingCard() async throws {
        let allSessions = try await workoutRepository.fetchSessions(
            ownerID: ownerID,
            from: Calendar.current.date(byAdding: .year, value: -1, to: .now) ?? .distantPast,
            to: .now.addingTimeInterval(86400)
        )
        strengthHistorySessions = allSessions

        let inProgress = try await workoutRepository.fetchInProgressSession(ownerID: ownerID)
        let inProgressStrength = StrengthSessionPersistence.decodeStrength(from: inProgress?.activeSessionJSON)

        let library = try await gymPlanRepository.fetchLibrary(ownerID: ownerID)
        let planned = try await StrengthTrainingBriefingBuilder.resolvePlannedWorkout(
            library: library,
            gymPlanRepository: gymPlanRepository,
            ownerID: ownerID
        )
        resolvedPlannedWorkout = planned

        strengthCardState = StrengthTrainingBriefingBuilder.buildCardState(
            inProgressSession: inProgressStrength,
            plannedWorkout: planned,
            historySessions: allSessions
        )
        inProgressStrengthSession = inProgressStrength
        if ProcessInfo.processInfo.arguments.contains("-UITestStrengthAutoStartFromHome"),
           !didAutoStartStrengthForUITest,
           inProgressStrength == nil,
           planned != nil
        {
            didAutoStartStrengthForUITest = true
            startStrengthWorkout()
        }
    }

    private func startStrengthWorkout() {
        guard case .planned(let model) = strengthCardState else { return }
        if let plan = resolvedPlannedWorkout {
            let proposals = StrengthSessionBuilder.proposals(
                for: plan,
                historySessions: strengthHistorySessions
            )
            onStartStrengthWorkout?(plan, proposals, strengthHistorySessions)
            return
        }
        Task {
            do {
                let plan = try await gymPlanRepository.resolvePlan(
                    reference: model.planReference,
                    sectionIndex: model.sectionIndex,
                    ownerID: ownerID
                )
                let proposals = StrengthSessionBuilder.proposals(
                    for: plan,
                    historySessions: strengthHistorySessions
                )
                await MainActor.run {
                    onStartStrengthWorkout?(plan, proposals, strengthHistorySessions)
                }
            } catch {
                await MainActor.run {
                    actionError = "Could not start this workout."
                }
            }
        }
    }

    private func resumeStrengthWorkout() {
        guard inProgressStrengthSession != nil else { return }
        onResumeStrengthWorkout?()
    }

    private func loadWorkoutSummaries(for day: NutritionDay) async throws -> [HomeWorkoutSummary] {
        let bounds = day.queryBounds()
        let sessions = try await workoutRepository.fetchSessions(
            ownerID: ownerID,
            from: bounds.start,
            to: bounds.end
        )
        return sessions
            .filter { $0.status == .completed || !$0.sets.isEmpty }
            .map(HomeWorkoutSummary.init)
    }

    private var workoutsSection: some View {
        VStack(alignment: .leading, spacing: DSSpacing.md) {
            HStack {
                Text("Workouts")
                    .font(.headline)
                    .foregroundStyle(DSColor.textPrimary)
                Spacer()
                Button("Gym Plans") {
                    onManageGymPlans?()
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(DSColor.coralEnd)
                .buttonStyle(.plain)
            }

            if displayedWorkouts.isEmpty {
                Text(isViewingToday ? "No workouts logged today yet." : "No workouts logged for this day.")
                    .font(.subheadline)
                    .foregroundStyle(DSColor.textSecondary)
            } else {
                ForEach(displayedWorkouts) { workout in
                    VStack(alignment: .leading, spacing: DSSpacing.xs) {
                        HStack {
                            Text(workout.title)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(DSColor.textPrimary)
                            Spacer()
                            Text("\(workout.setCount) sets")
                                .font(.caption)
                                .foregroundStyle(DSColor.textSecondary)
                        }
                        if let debriefSummary = workout.debriefSummary {
                            Text(debriefSummary)
                                .font(.caption)
                                .foregroundStyle(DSColor.coralEnd)
                        }
                        ForEach(workout.exerciseLines) { exercise in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(exercise.exerciseName)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(DSColor.textPrimary)
                                ForEach(exercise.setLines, id: \.self) { line in
                                    Text(line)
                                        .font(.caption)
                                        .foregroundStyle(DSColor.textSecondary)
                                }
                            }
                        }
                    }
                    .padding(.vertical, DSSpacing.xs)
                }
            }
        }
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
        displayedMeals.removeAll { $0.id == meal.id }
        recomputeDisplayedContentFromLocalMeals()
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
        displayedMeals.insert(restored, at: 0)
        displayedMeals.sort { $0.eatenAt > $1.eatenAt }
        recomputeDisplayedContentFromLocalMeals()
        do {
            try await mealRepository.createMealLog(payload.makeMealLog())
        } catch {
            actionError = "Couldn’t undo that delete."
            await loadHome()
        }
    }

    /// Immediate local recompute so totals update without waiting on disk/reload.
    private func recomputeDisplayedContentFromLocalMeals() {
        let mealLogs = displayedMeals.map { $0.restorePayload.makeMealLog() }
        let day = nutritionDaySelection.selectedDay
        let referenceNow = day.isToday() ? Date.now : day.defaultOccurrenceTimestamp()
        let input = CoachBriefingInputFactory.make(
            now: referenceNow,
            displayName: displayName,
            goal: cachedGoal,
            targets: cachedTargets,
            meals: mealLogs,
            assistantName: assistantName
        )

        if day.isToday() {
            briefing = DailyCoachBriefingBuilder.build(input)
            historicalSummary = nil
        } else {
            historicalSummary = HomeHistoricalDayPresenter.make(day: day, input: input)
            briefing = nil
        }
    }
}

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

// MARK: - Workout summaries

struct HomeWorkoutSummary: Identifiable {
    let id: UUID
    let title: String
    let setCount: Int
    let exerciseLines: [HomeWorkoutExerciseSummary]
    let debriefSummary: String?

    init(session: WorkoutSessionLog) {
        id = session.id
        title = session.title
        setCount = session.sets.count
        debriefSummary = {
            guard let debrief = StrengthSessionPersistence.decodeDebrief(from: session.debriefJSON),
                  let win = debrief.wins.first else { return nil }
            return "\(win.exerciseName): \(win.detail)"
        }()

        let grouped = Dictionary(grouping: session.sets.sorted { $0.setNumber < $1.setNumber }) {
            $0.exerciseID
        }
        exerciseLines = grouped.keys.sorted().compactMap { exerciseID in
            guard let sets = grouped[exerciseID]?.sorted(by: { $0.setNumber < $1.setNumber }),
                  let name = sets.first?.exerciseName else { return nil }
            return HomeWorkoutExerciseSummary(
                exerciseID: exerciseID,
                exerciseName: name,
                setLines: sets.map { set in
                    let weight = set.weightValue.formattedWorkoutWeight
                    return "\(weight) \(set.weightUnit) × \(set.repetitions)"
                }
            )
        }
    }
}

struct HomeWorkoutExerciseSummary: Identifiable {
    let exerciseID: String
    let exerciseName: String
    let setLines: [String]

    var id: String { exerciseID }
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
        workoutRepository: MockWorkoutRepository(),
        gymPlanRepository: MockGymPlanRepository(),
        goalRepository: MockGoalRepository(),
        nutritionDaySelection: NutritionDaySelection(),
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

private extension Double {
    var formattedWorkoutWeight: String {
        truncatingRemainder(dividingBy: 1) == 0 ? String(format: "%.0f", self) : String(format: "%.1f", self)
    }
}
