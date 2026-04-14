import SwiftUI

struct DashboardView: View {
    let mealRepository: MealRepository
    let goalRepository: GoalRepository
    let recurringMealRepository: RecurringMealRepository
    let alcoholPlanRepository: AlcoholPlanRepository
    let assistantName: String

    @State private var state = DashboardState.placeholder
    @State private var isLoading = false

    private let ownerID = "preview.user"

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DSSpacing.xxl) {
                header

                BestNextMoveCard(state: state, assistantName: assistantName)

                DashboardCard(title: "Macro Rhythm", icon: "chart.bar.fill", tint: .blue) {
                    MacroProgressRow(
                        label: "Protein",
                        consumed: state.proteinConsumed,
                        target: state.proteinTarget,
                        tint: .mint
                    )
                    MacroProgressRow(
                        label: "Carbs",
                        consumed: state.carbsConsumed,
                        target: state.carbsTarget,
                        tint: .blue
                    )
                    MacroProgressRow(
                        label: "Fat",
                        consumed: state.fatConsumed,
                        target: state.fatTarget,
                        tint: .orange
                    )
                }

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: DSSpacing.md) {
                    DecisionTile(
                        title: "Meal Move",
                        value: state.nextBestMealTitle,
                        caption: state.nextBestMealTagline,
                        icon: "takeoutbag.and.cup.and.straw.fill",
                        tint: .green
                    )
                    DecisionTile(
                        title: "Momentum",
                        value: "\(state.caloriesRemaining) kcal left",
                        caption: "\(Int((state.calorieProgress * 100).rounded()))% of daily target",
                        icon: "flame.fill",
                        tint: .orange
                    )
                    TonightStrategyCard(
                        title: state.tonightStrategyTitle,
                        caption: state.tonightStrategyBody
                    )
                    .gridCellColumns(2)
                    DecisionTile(
                        title: "Smart Patterns",
                        value: state.recurringPreview.first ?? "Create first repeatable meal",
                        caption: state.recurringPreview.isEmpty ? "No saved patterns yet" : "\(state.recurringPreview.count) saved this week",
                        icon: "arrow.triangle.2.circlepath",
                        tint: .teal
                    )
                }

                DashboardCard(title: "Pattern Stack", icon: "leaf.fill", tint: .teal) {
                    if state.recurringPreview.isEmpty {
                        HStack(spacing: DSSpacing.sm) {
                            Image(systemName: "sparkles")
                                .foregroundStyle(.teal)
                            Text("Save one repeatable breakfast or lunch to unlock one-tap future decisions.")
                                .font(.subheadline)
                                .foregroundStyle(DSColor.textSecondary)
                        }
                    } else {
                        ForEach(state.recurringPreview, id: \.self) { mealName in
                            HStack(spacing: DSSpacing.sm) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.teal)
                                Text(mealName)
                                    .font(.subheadline.weight(.medium))
                                    .foregroundStyle(DSColor.textPrimary)
                                Spacer()
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }
            }
            .padding(DSSpacing.lg)
        }
        .background(DSColor.background.ignoresSafeArea())
        .navigationTitle("Dashboard")
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
            Text("Today with \(assistantName)")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(DSColor.textSecondary)
            Text("Pick the next best move")
                .font(.largeTitle.weight(.bold))
                .foregroundStyle(DSColor.textPrimary)
        }
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

private struct DashboardHeroCard: View {
    let state: DashboardState

    var body: some View {
        HStack(spacing: DSSpacing.lg) {
            ZStack {
                ProgressRing(progress: state.calorieProgress, lineWidth: 10)
                    .frame(width: 94, height: 94)
                VStack(spacing: 2) {
                    Text("\(state.caloriesRemaining)")
                        .font(.title3.weight(.bold))
                        .foregroundStyle(.white)
                    Text("kcal left")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.white.opacity(0.85))
                }
            }

            VStack(alignment: .leading, spacing: DSSpacing.xs) {
                Text(state.confidenceHeadline)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.white)
                Text(state.confidenceBody)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.88))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(DSSpacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DSColor.coralGradient)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.white.opacity(0.3), lineWidth: 1)
        )
        .shadow(color: DSColor.coralEnd.opacity(0.3), radius: 16, y: 8)
    }
}

private struct BestNextMoveCard: View {
    let state: DashboardState
    let assistantName: String

    var body: some View {
        VStack(alignment: .leading, spacing: DSSpacing.lg) {
            HStack(spacing: DSSpacing.md) {
                ZStack {
                    ProgressRing(progress: state.calorieProgress, lineWidth: 10)
                        .frame(width: 92, height: 92)
                    VStack(spacing: 2) {
                        Text("\(state.caloriesRemaining)")
                            .font(.title3.weight(.bold))
                        Text("kcal left")
                            .font(.caption.weight(.semibold))
                            .opacity(0.85)
                    }
                    .foregroundStyle(.white)
                }

                VStack(alignment: .leading, spacing: DSSpacing.xs) {
                    Text("Best next move")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.85))
                    Text(state.nextBestMealTitle)
                        .font(.title3.weight(.bold))
                        .foregroundStyle(.white)
                    Text(state.nextBestMealTagline)
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.9))
                }
            }

            HStack(spacing: DSSpacing.sm) {
                DominantChip(label: state.topMacroChip, icon: "fork.knife")
                DominantChip(label: state.momentumChip, icon: "flame.fill")
                DominantChip(label: "Ask \(assistantName)", icon: "sparkles")
            }
        }
        .padding(DSSpacing.xl)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DSColor.coralGradient)
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(Color.white.opacity(0.26), lineWidth: 1)
        )
        .shadow(color: DSColor.coralEnd.opacity(0.35), radius: 18, y: 10)
    }
}

private struct DominantChip: View {
    let label: String
    let icon: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.caption.weight(.bold))
            Text(label)
                .font(.caption.weight(.semibold))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, DSSpacing.sm + 2)
        .padding(.vertical, DSSpacing.xs + 2)
        .background(Color.white.opacity(0.16))
        .clipShape(Capsule())
    }
}

private struct DecisionTile: View {
    let title: String
    let value: String
    let caption: String
    let icon: String
    let tint: Color

    var body: some View {
        PrimaryCard(cornerRadius: 18) {
            HStack {
                Label(title, systemImage: icon)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(tint)
                Spacer()
            }
            Text(value)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(DSColor.textPrimary)
                .lineLimit(2)
            Text(caption)
                .font(.caption)
                .foregroundStyle(DSColor.textSecondary)
                .lineLimit(2)
        }
    }
}

private struct TonightStrategyCard: View {
    let title: String
    let caption: String

    var bodyView: some View {
        PrimaryCard(cornerRadius: 20, useWarmBackground: true) {
            Label("Tonight Strategy", systemImage: "moon.stars.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.purple)
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(DSColor.textPrimary)
            Text(caption)
                .font(.caption)
                .foregroundStyle(DSColor.textSecondary)
        }
    }

    var body: some View {
        bodyView
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

    var topMacroChip: String {
        let deficits = [
            ("Protein", proteinRemaining),
            ("Carbs", carbsRemaining),
            ("Fat", fatRemaining)
        ]
        let top = deficits.max { $0.1 < $1.1 } ?? ("Protein", 0)
        if top.1 <= 0 { return "Macros on target" }
        return "\(top.0) +\(top.1)g"
    }

    var momentumChip: String {
        "\(Int((calorieProgress * 100).rounded()))% pace"
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
                "Macros are on target",
                "Beautiful pacing. Ask \(assistantName) for a light maintenance meal so tonight stays easy."
            )
        }

        switch top.0 {
        case "protein":
            return (
                "Prioritize a high-protein meal",
                "About \(top.1)g protein still to go. Anchor your next plate with lean protein and let carbs follow."
            )
        case "carbs":
            return (
                "Refuel with quality carbs",
                "Around \(top.1)g carbs remain. Pair whole-food carbs with protein for steadier energy later."
            )
        default:
            return (
                "Add healthy fats intentionally",
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
