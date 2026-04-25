import SwiftUI
import UIKit

struct DashboardView: View {
    let mealRepository: MealRepository
    let goalRepository: GoalRepository
    let recurringMealRepository: RecurringMealRepository
    let alcoholPlanRepository: AlcoholPlanRepository
    let ownerID: String
    let assistantName: String
    var mealAddedFeedbackTrigger: Int = 0
    var onCheckInRequested: (() -> Void)? = nil
    var onAskTaiRequested: ((String) -> Void)? = nil
    var onScrollDirectionChanged: ((Bool) -> Void)? = nil

    @State private var state = DashboardState.placeholder
    @State private var isLoading = false
    @State private var pendingUndoMeal: DashboardState.TodayMealRestorePayload?
    @State private var pendingUndoOriginalIndex: Int?
    @State private var undoDismissTask: Task<Void, Never>?
    @State private var showsMealAddedFeedback = false
    @State private var addFeedbackDismissTask: Task<Void, Never>?
    @State private var lastScrollMinY: CGFloat = 0
    @State private var isScrollingDown = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DSSpacing.xl) {
                header

                if showsMealAddedFeedback {
                    DashboardInlineFeedback(
                        message: "Meal added",
                        icon: "checkmark.circle.fill",
                        tint: DSColor.coralEnd
                    )
                    .transition(.move(edge: .top).combined(with: .opacity))
                }

                TodayStatusHero(state: state)

                NextBestMealCard(state: state)

                DashboardCard(title: "Macros Remaining", icon: "flame.fill", tint: .orange) {
                    MacroProgressRow(
                        label: "Protein",
                        consumed: state.proteinConsumed,
                        target: state.proteinTarget,
                        tint: .mint,
                        isPriority: state.priorityMacro == "Protein"
                    )
                    MacroProgressRow(
                        label: "Carbs",
                        consumed: state.carbsConsumed,
                        target: state.carbsTarget,
                        tint: .blue,
                        isPriority: state.priorityMacro == "Carbs"
                    )
                    MacroProgressRow(
                        label: "Fat",
                        consumed: state.fatConsumed,
                        target: state.fatTarget,
                        tint: .orange,
                        isPriority: state.priorityMacro == "Fat"
                    )
                }

                TodaysMealsCard(
                    state: state,
                    pendingUndoMeal: pendingUndoMeal,
                    pendingUndoOriginalIndex: pendingUndoOriginalIndex,
                    onDeleteMeal: deleteMeal,
                    onUndoDelete: { Task { await undoDeleteMeal() } }
                )

                SmartPatternsCard(state: state)

                AlcoholBudgetCard(state: state)

                Color.clear
                    .frame(height: DSSpacing.customBottomNavHeight + 48 + 30)
            }
            .padding(DSSpacing.lg)
            .background(
                GeometryReader { proxy in
                    Color.clear.preference(
                        key: DashboardScrollMinYPreferenceKey.self,
                        value: proxy.frame(in: .named("dashboardScrollView")).minY
                    )
                }
            )
        }
        .coordinateSpace(name: "dashboardScrollView")
        .background(DSColor.background.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .navigationBar)
        .refreshable {
            await loadDashboard()
        }
        .task {
            await loadDashboard()
        }
        .overlay {
            if isLoading {
                ProgressView()
                    .padding(DSSpacing.lg)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
        .onChange(of: mealAddedFeedbackTrigger) { _, newValue in
            guard newValue > 0 else { return }
            showMealAddedFeedback()
        }
        .onPreferenceChange(DashboardScrollMinYPreferenceKey.self) { newMinY in
            let delta = newMinY - lastScrollMinY
            let threshold: CGFloat = 0.8

            if delta < -threshold, !isScrollingDown {
                isScrollingDown = true
                onScrollDirectionChanged?(true)
            } else if delta > threshold, isScrollingDown {
                isScrollingDown = false
                onScrollDirectionChanged?(false)
            }
            lastScrollMinY = newMinY
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: DSSpacing.sm) {
            Text("Today with Tai")
                .font(.largeTitle.weight(.bold))
                .foregroundStyle(DSColor.textPrimary)
            Text(todayDateLabel)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(DSColor.textSecondary)
        }
    }

    private var todayDateLabel: String {
        Date.now.formatted(.dateTime.weekday(.wide).month(.wide).day())
    }

    private func loadDashboard() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }

        do {
            async let goalProfilesTask = goalRepository.fetchGoalProfiles(ownerID: ownerID)
            async let recurringMealsTask = recurringMealRepository.fetchRecurringMeals(ownerID: ownerID, activeOnly: true)
            async let alcoholPlanTask = alcoholPlanRepository.fetchAlcoholPlan(ownerID: ownerID)

            let calendar = Calendar.current
            let dayStart = calendar.startOfDay(for: .now)
            let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) ?? .now
            let todaysMeals = try await mealRepository.fetchMealLogs(ownerID: ownerID, from: dayStart, to: dayEnd)

            let goalProfiles = try await goalProfilesTask
            let recurringMeals = try await recurringMealsTask
            let alcoholPlan = try await alcoholPlanTask

            let selectedGoal = goalProfiles.first
            let targets: DailyTargets? = if let selectedGoal {
                try await goalRepository.fetchDailyTargets(goalProfileID: selectedGoal.id)
            } else {
                nil
            }

            state = DashboardState.build(
                assistantName: assistantName,
                meals: todaysMeals,
                targets: targets,
                recurringMeals: recurringMeals,
                alcoholPlan: alcoholPlan
            )
        } catch {
            state = DashboardState.placeholder
        }
    }

    private func deleteMeal(_ meal: DashboardState.TodayMealSummary) {
        Task {
            do {
                let deletedIndex = state.todaysMeals.firstIndex(where: { $0.id == meal.id })
                try await mealRepository.deleteMealLog(id: meal.id)
                withAnimation(.easeInOut(duration: 0.18)) {
                    pendingUndoMeal = meal.restorePayload
                    pendingUndoOriginalIndex = deletedIndex
                }
                scheduleUndoDismiss()
                await loadDashboard()
            } catch {
                // Keep current UI state if delete fails.
            }
        }
    }

    private func undoDeleteMeal() async {
        guard let payload = pendingUndoMeal else { return }
        do {
            try await mealRepository.createMealLog(payload.makeMealLog())
            undoDismissTask?.cancel()
            undoDismissTask = nil
            withAnimation(.easeInOut(duration: 0.16)) {
                pendingUndoMeal = nil
                pendingUndoOriginalIndex = nil
            }
            await loadDashboard()
        } catch {
            // Keep toast visible if restore fails so user can retry.
        }
    }

    private func scheduleUndoDismiss() {
        undoDismissTask?.cancel()
        undoDismissTask = Task {
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            await MainActor.run {
                withAnimation(.easeOut(duration: 0.2)) {
                    pendingUndoMeal = nil
                    pendingUndoOriginalIndex = nil
                }
            }
        }
    }

    private func showMealAddedFeedback() {
        addFeedbackDismissTask?.cancel()
        withAnimation(.spring(response: 0.28, dampingFraction: 0.9)) {
            showsMealAddedFeedback = true
        }
        addFeedbackDismissTask = Task {
            try? await Task.sleep(nanoseconds: 1_700_000_000)
            await MainActor.run {
                withAnimation(.easeOut(duration: 0.2)) {
                    showsMealAddedFeedback = false
                }
            }
        }
    }
}

private struct DashboardScrollMinYPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

private struct TodayStatusHero: View {
    let state: DashboardState

    var body: some View {
        PrimaryCard(cornerRadius: 26) {
            VStack(spacing: 0) {
                ZStack {
                    StatusRing(progress: state.calorieProgress)
                        .frame(width: 212, height: 212)
                    VStack(spacing: 4) {
                        Text("\(state.consumedCalories)")
                            .font(.system(size: 56, weight: .semibold, design: .rounded))
                            .foregroundStyle(DSColor.textPrimary)
                        Text("kcal")
                            .font(.title3.weight(.medium))
                            .foregroundStyle(DSColor.textSecondary)
                    }
                }
                .frame(maxWidth: .infinity)

                Text(state.supportiveStatusLine)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(state.supportiveStatusTint)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.top, 22)

                Text("Need specifics? Ask Tai for your best next move.")
                    .font(.footnote)
                    .foregroundStyle(DSColor.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.top, 6)

                Text(state.heroDetailLine)
                    .font(.caption2)
                    .foregroundStyle(DSColor.textSecondary.opacity(0.78))
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.top, 9)
            }
            .padding(.top, 6)
            .padding(.bottom, 6)
        }
    }
}

private struct StatusRing: View {
    let progress: Double

    private var normalizedProgress: Double {
        min(max(progress, 0), 1)
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(DSColor.textSecondary.opacity(0.14), lineWidth: 18)
            Circle()
                .trim(from: 0, to: normalizedProgress)
                .stroke(
                    LinearGradient(
                        colors: [DSColor.coralStart.opacity(0.5), DSColor.coralEnd.opacity(0.9)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    style: StrokeStyle(lineWidth: 18, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
        }
    }
}

private struct NextBestMealCard: View {
    let state: DashboardState

    var body: some View {
        DashboardCard(title: "Next Best Meal", icon: "fork.knife", tint: .pink) {
            Text(state.nextBestMealTitle)
                .dashboardPrimaryText(.title)
                .foregroundStyle(DSColor.coralEnd)
                .lineLimit(2)
            Text(state.nextBestMealTagline)
                .dashboardSecondaryText()
                .lineLimit(2)
        }
    }
}

private struct TodaysMealsCard: View {
    let state: DashboardState
    let pendingUndoMeal: DashboardState.TodayMealRestorePayload?
    let pendingUndoOriginalIndex: Int?
    let onDeleteMeal: (DashboardState.TodayMealSummary) -> Void
    let onUndoDelete: () -> Void

    var body: some View {
        DashboardCard(title: "Today's meals", icon: "list.bullet.rectangle.portrait", tint: .pink) {
            let rows = displayRows

            if rows.isEmpty {
                VStack(alignment: .leading, spacing: DSSpacing.xs) {
                    Text("No meals yet today")
                        .dashboardPrimaryText(.body)
                    Text("Start by checking in your first meal")
                        .dashboardSecondaryText()
                }
            } else {
                ForEach(rows) { row in
                    switch row {
                    case .meal(let meal):
                        TodayMealSwipeRow(meal: meal, onDelete: onDeleteMeal)
                    case .undoPlaceholder:
                        undoPlaceholder
                    }
                }
            }
        }
    }

    private var undoPlaceholder: some View {
        HStack(alignment: .firstTextBaseline, spacing: DSSpacing.sm) {
            Text("Meal removed")
                .font(.footnote.weight(.regular))
                .foregroundStyle(DSColor.textSecondary.opacity(0.95))
                .lineLimit(1)
            Spacer(minLength: DSSpacing.xs)
            Button("Undo", action: onUndoDelete)
                .font(.subheadline.weight(.regular))
                .foregroundStyle(DSColor.coralEnd.opacity(0.86))
                .buttonStyle(.plain)
        }
        .frame(minHeight: 40)
        .padding(.vertical, DSSpacing.xs)
        .background(DSColor.warmSurface.opacity(0.035))
        .transition(.opacity)
    }

    private var displayRows: [MealRow] {
        var rows = state.todaysMeals.map { MealRow.meal($0) }
        guard let pendingUndoMeal else { return rows }

        let insertionIndex = undoInsertionIndex(for: pendingUndoMeal, meals: state.todaysMeals)
        rows.insert(.undoPlaceholder, at: insertionIndex)
        return rows
    }

    private func undoInsertionIndex(
        for pendingMeal: DashboardState.TodayMealRestorePayload,
        meals: [DashboardState.TodayMealSummary]
    ) -> Int {
        if let pendingUndoOriginalIndex {
            return min(max(pendingUndoOriginalIndex, 0), meals.count)
        }

        // Fallback when index context is missing: place near original chronological slot.
        let idx = meals.firstIndex { $0.eatenAt <= pendingMeal.eatenAt } ?? meals.count
        return min(max(idx, 0), meals.count)
    }

    private enum MealRow: Identifiable {
        case meal(DashboardState.TodayMealSummary)
        case undoPlaceholder

        var id: String {
            switch self {
            case .meal(let meal):
                return meal.id.uuidString
            case .undoPlaceholder:
                return "undo-placeholder-row"
            }
        }
    }
}

private struct TodayMealSwipeRow: View {
    let meal: DashboardState.TodayMealSummary
    let onDelete: (DashboardState.TodayMealSummary) -> Void

    @State private var settledOffset: CGFloat = 0
    @GestureState private var dragTranslation: CGFloat = 0
    @State private var isDeleteArmed = false
    @State private var didCommitDelete = false

    private let openOffset: CGFloat = 96
    private let armThreshold: CGFloat = 92
    private let commitThreshold: CGFloat = 142
    private let easySwipeDistance: CGFloat = 60
    private let resistanceFactor: CGFloat = 0.55
    private let maxPullDistance: CGFloat = 220
    private let commitSlideDistance: CGFloat = 420

    var body: some View {
        ZStack(alignment: .trailing) {
            deleteBackground
            rowContent
                .offset(x: effectiveOffset)
                .contentShape(Rectangle())
                .gesture(dragGesture)
                .onTapGesture {
                    if settledOffset != 0 {
                        withAnimation(.spring(response: 0.26, dampingFraction: 0.88)) {
                            settledOffset = 0
                        }
                        isDeleteArmed = false
                    }
                }
        }
        .clipped()
        .onChange(of: abs(effectiveOffset) >= armThreshold) { _, isArmed in
            guard isArmed != isDeleteArmed else { return }
            isDeleteArmed = isArmed
            if isArmed {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            }
        }
    }

    private var rowContent: some View {
        HStack(alignment: .firstTextBaseline, spacing: DSSpacing.sm) {
            VStack(alignment: .leading, spacing: 2) {
                Text(meal.label)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(DSColor.textPrimary)
                    .lineLimit(1)
                Text(meal.eatenAt.formatted(.dateTime.hour().minute()))
                    .dashboardSecondaryText()
            }
            Spacer()
            Text("\(meal.calories) kcal")
                .font(.body.weight(.medium))
                .foregroundStyle(DSColor.textPrimary)
        }
        .frame(minHeight: 40)
        .padding(.vertical, DSSpacing.xs)
        .background(DSColor.surface)
    }

    private var effectiveOffset: CGFloat {
        if didCommitDelete {
            return -maxPullDistance
        }
        let drag = transformedDrag(dragTranslation)
        let combined = settledOffset + drag
        return min(0, max(-maxPullDistance, combined))
    }

    private var revealProgress: CGFloat {
        min(abs(effectiveOffset) / armThreshold, 1)
    }

    @ViewBuilder
    private var deleteBackground: some View {
        let absoluteOffset = abs(effectiveOffset)
        let shouldFillRow = absoluteOffset >= armThreshold
        let backgroundWidth = max(40, absoluteOffset + 26)
        let iconScale = shouldFillRow ? 1.12 : 0.92 + (0.12 * revealProgress)
        let labelOpacity = min(max((absoluteOffset - armThreshold) / 26, 0), 1)

        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(DSColor.destructiveCoral.opacity(0.9))
            .frame(width: backgroundWidth)
            .frame(maxWidth: shouldFillRow ? .infinity : nil, alignment: .trailing)
            .overlay(alignment: .trailing) {
                HStack(spacing: 6) {
                    Image(systemName: "trash.fill")
                        .font(.callout.weight(.semibold))
                        .scaleEffect(iconScale)
                        .opacity(0.35 + (0.65 * revealProgress))
                    Text("Delete")
                        .font(.caption.weight(.semibold))
                        .opacity(labelOpacity)
                }
                .foregroundStyle(.white)
                .padding(.trailing, DSSpacing.md)
                .animation(.easeOut(duration: 0.16), value: shouldFillRow)
                .animation(.easeOut(duration: 0.12), value: labelOpacity)
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 12, coordinateSpace: .local)
            .updating($dragTranslation) { value, state, _ in
                guard abs(value.translation.width) > abs(value.translation.height) else { return }
                state = value.translation.width
            }
            .onEnded { value in
                guard abs(value.translation.width) > abs(value.translation.height) else { return }

                let predicted = settledOffset + transformedDrag(value.predictedEndTranslation.width)
                let finalPredicted = min(0, max(-maxPullDistance, predicted))
                let predictedDistance = abs(finalPredicted)

                if predictedDistance >= commitThreshold {
                    commitDelete()
                    return
                }

                let shouldOpen = predictedDistance >= armThreshold
                withAnimation(.spring(response: 0.3, dampingFraction: 0.84)) {
                    settledOffset = shouldOpen ? -openOffset : 0
                }
                if !shouldOpen {
                    isDeleteArmed = false
                }
            }
    }

    private func transformedDrag(_ translation: CGFloat) -> CGFloat {
        if translation > 0 {
            return translation * 0.72
        }
        let distance = abs(translation)
        guard distance > easySwipeDistance else { return translation }
        let resisted = easySwipeDistance + ((distance - easySwipeDistance) * resistanceFactor)
        return -resisted
    }

    private func commitDelete() {
        guard !didCommitDelete else { return }
        didCommitDelete = true
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()

        withAnimation(.spring(response: 0.26, dampingFraction: 0.9)) {
            settledOffset = -commitSlideDistance
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
            onDelete(meal)
        }
    }
}

private struct DashboardInlineFeedback: View {
    let message: String
    let icon: String
    let tint: Color

    var body: some View {
        HStack(spacing: DSSpacing.sm) {
            Image(systemName: icon)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(tint)
            Text(message)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(DSColor.textPrimary)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, DSSpacing.md)
        .padding(.vertical, DSSpacing.sm)
        .background(DSColor.warmSurface)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

private struct SmartPatternsCard: View {
    let state: DashboardState

    var body: some View {
        DashboardCard(title: "Your Smart Patterns", icon: "arrow.triangle.2.circlepath", tint: .teal) {
            if state.recurringPreview.isEmpty {
                PatternPill(text: "Save your first repeatable meal")
            } else {
                ForEach(state.recurringPreview, id: \.self) { pattern in
                    PatternPill(text: pattern)
                }
            }
        }
    }
}

private struct AlcoholBudgetCard: View {
    let state: DashboardState

    var body: some View {
        DashboardCard(title: "Alcohol Budget", icon: "wineglass.fill", tint: .purple) {
            Text(state.alcoholStatusValue)
                .dashboardPrimaryText(.body)
            Text(state.alcoholStatusDetail)
                .dashboardSecondaryText()
        }
    }
}

private struct PatternPill: View {
    let text: String

    var body: some View {
        HStack(spacing: DSSpacing.sm) {
            Text("•")
                .foregroundStyle(DSColor.textSecondary)
            Text(text)
                .dashboardPrimaryText(.body)
            Spacer()
        }
        .padding(.horizontal, DSSpacing.md)
        .padding(.vertical, DSSpacing.md)
        .background(DSColor.surface.opacity(0.7))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

private struct DashboardState {
    struct TodayMealItemRestorePayload {
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

    struct TodayMealRestorePayload {
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
        let items: [TodayMealItemRestorePayload]

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

    struct TodayMealSummary: Identifiable {
        let id: UUID
        let label: String
        let eatenAt: Date
        let calories: Int
        let restorePayload: TodayMealRestorePayload
    }

    let caloriesConsumed: Int
    let calorieTarget: Int
    let caloriesRemaining: Int
    let proteinConsumed: Int
    let proteinTarget: Int
    let proteinRemaining: Int
    let carbsConsumed: Int
    let carbsTarget: Int
    let carbsRemaining: Int
    let fatConsumed: Int
    let fatTarget: Int
    let fatRemaining: Int
    let nextBestMealTitle: String
    let nextBestMealBody: String
    let alcoholHeadline: String
    let alcoholGuidance: String
    let recurringPreview: [String]
    let alcoholRemainingDrinks: Int?
    let alcoholDailyCap: Int?
    let todaysMeals: [TodayMealSummary]

    var consumedCalories: Int {
        caloriesConsumed
    }

    var targetCalories: Int {
        calorieTarget
    }

    var caloriesOverTarget: Int {
        max(consumedCalories - targetCalories, 0)
    }

    var calorieProgress: Double {
        guard calorieTarget > 0 else { return 0 }
        return min(max(Double(caloriesConsumed) / Double(calorieTarget), 0), 1)
    }

    var confidenceHeadline: String {
        if caloriesRemaining < 0 {
            return "Small reset wins tonight"
        }
        if caloriesRemaining < 250 {
            return "Dialed in and nearly complete"
        }
        return "Confident runway for the rest of today"
    }

    var confidenceBody: String {
        if caloriesRemaining < 0 {
            return "You are \(abs(caloriesRemaining)) kcal over target. A lighter dinner keeps the week balanced."
        }
        return "\(caloriesRemaining) kcal remain from your \(calorieTarget) kcal target. Keep this pace and finish strong."
    }

    static let placeholder = DashboardState(
        caloriesConsumed: 0,
        calorieTarget: 2100,
        caloriesRemaining: 2100,
        proteinConsumed: 0,
        proteinTarget: 150,
        proteinRemaining: 150,
        carbsConsumed: 0,
        carbsTarget: 210,
        carbsRemaining: 210,
        fatConsumed: 0,
        fatTarget: 70,
        fatRemaining: 70,
        nextBestMealTitle: "Load your first meal",
        nextBestMealBody: "After your first meal log, Tai can suggest the best macro-balancing next meal.",
        alcoholHeadline: "No plan set",
        alcoholGuidance: "Set an alcohol plan to keep meals and social events aligned with your weekly goal.",
        recurringPreview: [],
        alcoholRemainingDrinks: nil,
        alcoholDailyCap: nil,
        todaysMeals: []
    )

    var nextBestMealTagline: String {
        nextBestMealBody
            .components(separatedBy: ".")
            .first?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? nextBestMealBody
    }

    private var calorieDelta: Int {
        caloriesConsumed - calorieTarget
    }

    var supportiveStatusLine: String {
        switch trackState {
        case .onTrack:
            return "You're on track"
        case .slightlyOff:
            return "Stay steady — keep meals balanced"
        case .offTrack:
            if calorieDelta > 0 { return "Keep your next meal lighter" }
            return "Focus on protein next"
        }
    }

    var supportiveStatusTint: Color {
        switch trackState {
        case .onTrack:
            return Color.green
        case .slightlyOff:
            return DSColor.textSecondary
        case .offTrack:
            return DSColor.textPrimary
        }
    }

    var heroDetailLine: String {
        if caloriesOverTarget > 0 {
            return "of \(targetCalories) target • +\(caloriesOverTarget) over"
        }
        return "of \(targetCalories) target"
    }

    private var trackState: TrackState {
        let delta = abs(calorieDelta)
        if delta <= 150 { return .onTrack }
        if delta <= 400 { return .slightlyOff }
        return .offTrack
    }

    private enum TrackState {
        case onTrack
        case slightlyOff
        case offTrack
    }

    var priorityMacro: String? {
        let deficits = [
            ("Protein", proteinRemaining),
            ("Carbs", carbsRemaining),
            ("Fat", fatRemaining)
        ]
        let top = deficits.max { $0.1 < $1.1 } ?? ("Protein", 0)
        return top.1 > 0 ? top.0 : nil
    }

    var alcoholStatusValue: String {
        guard let remaining = alcoholRemainingDrinks else { return "Set plan" }
        guard remaining >= 0 else { return "Past daily range today" }
        let unit = remaining == 1 ? "drink" : "drinks"
        return "\(remaining) \(unit) remaining today"
    }

    var alcoholStatusDetail: String {
        guard let cap = alcoholDailyCap else { return "Daily and weekly guidance" }
        return "Daily cap: \(cap)"
    }

    var alcoholTileCaption: String {
        guard let cap = alcoholDailyCap else { return "Add a daily/weekly drink plan" }
        if let remaining = alcoholRemainingDrinks {
            return remaining >= 0 ? "Daily cap \(cap)" : "Cap exceeded by \(abs(remaining))"
        }
        return "Daily cap \(cap)"
    }

    var tonightStrategyTitle: String {
        guard alcoholDailyCap != nil else {
            return "Going out tonight? Keep protein first and meals steady."
        }
        if let remaining = alcoholRemainingDrinks, remaining > 0 {
            return "Drinks tonight? Anchor protein early and keep lunch lighter."
        }
        return "No drinks planned? Keep dinner protein-forward and finish calm."
    }

    var tonightStrategyBody: String {
        guard let cap = alcoholDailyCap else {
            return "If plans shift, add hydration and keep evening choices simple."
        }
        if let remaining = alcoholRemainingDrinks, remaining > 0 {
            return "\(remaining) drink(s) available within your \(cap)-drink plan. Keep water between rounds and choose a balanced dinner."
        }
        return "You are already near your \(cap)-drink plan today. A lighter, protein-first dinner can help you feel good tomorrow."
    }

    static func build(
        assistantName: String,
        meals: [MealLog],
        targets: DailyTargets?,
        recurringMeals: [RecurringMeal],
        alcoholPlan: AlcoholPlan?
    ) -> DashboardState {
        let consumedCalories = meals.flatMap(\.items).reduce(0) { $0 + $1.calories }
        let consumedProtein = meals.flatMap(\.items).reduce(0.0) { $0 + $1.proteinGrams }
        let consumedCarbs = meals.flatMap(\.items).reduce(0.0) { $0 + $1.carbsGrams }
        let consumedFat = meals.flatMap(\.items).reduce(0.0) { $0 + $1.fatGrams }
        let consumedDrinks = meals.reduce(0.0) { $0 + $1.alcoholStandardDrinks }

        let calorieTarget = targets?.calories ?? 2100
        let proteinTarget = targets?.proteinGrams ?? 150
        let carbsTarget = targets?.carbsGrams ?? 210
        let fatTarget = targets?.fatGrams ?? 70

        let proteinDeficit = Int((proteinTarget - consumedProtein).rounded())
        let carbDeficit = Int((carbsTarget - consumedCarbs).rounded())
        let fatDeficit = Int((fatTarget - consumedFat).rounded())

        let guidance = buildMealGuidance(
            assistantName: assistantName,
            proteinDeficit: proteinDeficit,
            carbDeficit: carbDeficit,
            fatDeficit: fatDeficit
        )
        let alcoholCopy = buildAlcoholGuidance(
            plan: alcoholPlan,
            consumedDrinks: consumedDrinks
        )
        let dailyCap = alcoholPlan.map { Int($0.maxStandardDrinksPerDay.rounded()) }
        let remainingDrinks = alcoholPlan.map { Int(($0.maxStandardDrinksPerDay - consumedDrinks).rounded(.down)) }
        let todayMealSummaries = meals
            .sorted { $0.eatenAt > $1.eatenAt }
            .map { meal in
                let label = meal.notes.trimmingCharacters(in: .whitespacesAndNewlines)
                return TodayMealSummary(
                    id: meal.id,
                    label: label.isEmpty ? meal.timing.rawValue.capitalized : label,
                    eatenAt: meal.eatenAt,
                    calories: meal.items.reduce(0) { $0 + $1.calories },
                    restorePayload: TodayMealRestorePayload(
                        id: meal.id,
                        ownerID: meal.ownerID,
                        visibility: meal.visibility,
                        sharingGroupID: meal.sharingGroupID,
                        eatenAt: meal.eatenAt,
                        timing: meal.timing,
                        notes: meal.notes,
                        alcoholStandardDrinks: meal.alcoholStandardDrinks,
                        createdAt: meal.createdAt,
                        updatedAt: meal.updatedAt,
                        items: meal.items.map {
                            TodayMealItemRestorePayload(
                                id: $0.id,
                                name: $0.name,
                                amount: $0.amount,
                                unit: $0.unit,
                                calories: $0.calories,
                                proteinGrams: $0.proteinGrams,
                                carbsGrams: $0.carbsGrams,
                                fatGrams: $0.fatGrams,
                                fiberGrams: $0.fiberGrams,
                                alcoholGrams: $0.alcoholGrams
                            )
                        }
                    )
                )
            }

        return DashboardState(
            caloriesConsumed: consumedCalories,
            calorieTarget: calorieTarget,
            caloriesRemaining: calorieTarget - consumedCalories,
            proteinConsumed: Int(consumedProtein.rounded()),
            proteinTarget: Int(proteinTarget.rounded()),
            proteinRemaining: proteinDeficit,
            carbsConsumed: Int(consumedCarbs.rounded()),
            carbsTarget: Int(carbsTarget.rounded()),
            carbsRemaining: carbDeficit,
            fatConsumed: Int(consumedFat.rounded()),
            fatTarget: Int(fatTarget.rounded()),
            fatRemaining: fatDeficit,
            nextBestMealTitle: guidance.title,
            nextBestMealBody: guidance.body,
            alcoholHeadline: alcoholCopy.headline,
            alcoholGuidance: alcoholCopy.body,
            recurringPreview: Array(recurringMeals.prefix(3).map(\.name)),
            alcoholRemainingDrinks: remainingDrinks,
            alcoholDailyCap: dailyCap,
            todaysMeals: todayMealSummaries
        )
    }

    private static func buildMealGuidance(
        assistantName: String,
        proteinDeficit: Int,
        carbDeficit: Int,
        fatDeficit: Int
    ) -> (title: String, body: String) {
        let deficits = [
            ("protein", proteinDeficit),
            ("carbs", carbDeficit),
            ("fat", fatDeficit)
        ]
            .sorted { $0.1 > $1.1 }
        let top = deficits.first ?? ("protein", 0)

        if top.1 <= 0 {
            return (
                "On track",
                "Beautiful pacing. Ask \(assistantName) for a light maintenance meal so tonight stays easy."
            )
        }

        switch top.0 {
        case "protein":
            return (
                "Protein-first next meal",
                "About \(top.1)g protein still to go. Anchor your next plate with lean protein and let carbs follow."
            )
        case "carbs":
            return (
                "Add quality carbs",
                "Around \(top.1)g carbs remain. Pair whole-food carbs with protein for steadier energy later."
            )
        default:
            return (
                "Add healthy fats",
                "Roughly \(top.1)g fat remain. Add fats intentionally around protein so your calories stay strategic."
            )
        }
    }

    private static func buildAlcoholGuidance(
        plan: AlcoholPlan?,
        consumedDrinks: Double
    ) -> (headline: String, body: String) {
        guard let plan else {
            return (
                "No drink plan yet",
                "Add a gentle daily and weekly guide if you want tailored tonight strategy prompts."
            )
        }

        let remaining = Int((plan.maxStandardDrinksPerDay - consumedDrinks).rounded(.down))
        if remaining < 0 {
            return (
                "You are past today’s planned range",
                "Consider a lighter, protein-forward meal and hydration to keep tomorrow steady."
            )
        }

        return (
            "\(remaining) drink(s) remaining today",
            "Daily cap: \(Int(plan.maxStandardDrinksPerDay)) • Weekly cap: \(Int(plan.maxStandardDrinksPerWeek)) • \(plan.alcoholFreeDaysTarget) alcohol-free days/week."
        )
    }
}
