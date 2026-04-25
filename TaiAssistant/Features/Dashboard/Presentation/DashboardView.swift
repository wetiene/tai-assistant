import SwiftUI

struct DashboardView: View {
    let mealRepository: MealRepository
    let goalRepository: GoalRepository
    let recurringMealRepository: RecurringMealRepository
    let alcoholPlanRepository: AlcoholPlanRepository
    let ownerID: String
    let assistantName: String
    var onCheckInRequested: (() -> Void)? = nil
    var onAskTaiRequested: ((String) -> Void)? = nil

    @State private var state = DashboardState.placeholder
    @State private var isLoading = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DSSpacing.xl) {
                header

                TodayStatusHero(state: state)

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

                NextBestMealCard(state: state)

                SmartPatternsCard(state: state)

                AlcoholBudgetCard(state: state)

                Color.clear
                    .frame(height: 92)
            }
            .padding(DSSpacing.lg)
        }
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
        PrimaryCard(cornerRadius: 24, useWarmBackground: true) {
            HStack(spacing: DSSpacing.md) {
                Circle()
                    .fill(Color.pink.opacity(0.15))
                    .frame(width: 42, height: 42)
                    .overlay(
                        Text("🍽️")
                            .font(.title3)
                    )
                Text("Next Best Meal")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(DSColor.textPrimary)
            }

            Text(state.nextBestMealTitle)
                .font(.title3.weight(.bold))
                .foregroundStyle(DSColor.coralEnd)
            Text(state.nextBestMealTagline)
                .font(.body.weight(.medium))
                .foregroundStyle(DSColor.textPrimary)
                .lineLimit(3)
        }
    }
}

private struct SmartPatternsCard: View {
    let state: DashboardState

    var body: some View {
        PrimaryCard(cornerRadius: 24) {
            HStack(spacing: DSSpacing.md) {
                Circle()
                    .fill(Color.cyan.opacity(0.16))
                    .frame(width: 42, height: 42)
                    .overlay(
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .font(.headline.weight(.semibold))
                            .foregroundStyle(.teal)
                    )
                Text("Your Smart Patterns")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(DSColor.textPrimary)
            }

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
        PrimaryCard(cornerRadius: 24) {
            HStack(spacing: DSSpacing.md) {
                Circle()
                    .fill(Color.purple.opacity(0.14))
                    .frame(width: 42, height: 42)
                    .overlay(
                        Image(systemName: "wineglass.fill")
                            .font(.headline.weight(.semibold))
                            .foregroundStyle(.purple)
                    )
                Text("Alcohol Budget")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(DSColor.textPrimary)
            }

            Text(state.alcoholStatusValue)
                .font(.title2.weight(.bold))
                .foregroundStyle(DSColor.textPrimary)
            Text(state.alcoholStatusDetail)
                .font(.title3.weight(.medium))
                .foregroundStyle(DSColor.textSecondary)
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
                .font(.headline.weight(.medium))
                .foregroundStyle(DSColor.textPrimary)
            Spacer()
        }
        .padding(.horizontal, DSSpacing.md)
        .padding(.vertical, DSSpacing.md)
        .background(Color.white.opacity(0.55))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

private struct DashboardState {
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
        alcoholDailyCap: nil
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
            alcoholDailyCap: dailyCap
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
