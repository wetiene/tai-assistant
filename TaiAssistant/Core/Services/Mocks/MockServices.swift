import Foundation

struct MockAIService: AIService {
    func send(message: String, context: [String: String]) async throws -> String {
        "Mock response from Tai: \(message)"
    }
}

struct MockHealthService: HealthService {
    func requestAuthorization() async throws {
        // Intentionally no-op in scaffold phase.
    }

    func latestDailySummary() async throws -> DailyHealthSummary? {
        DailyHealthSummary(date: .now, caloriesBurned: 0, steps: 0)
    }
}

final class MockMealRepository: MealRepository {
    private var meals: [MealLog]

    init() {
        self.meals = MockSeedData.makeMealLogs()
    }

    func fetchMealLogs(ownerID: String, from startDate: Date, to endDate: Date) async throws -> [MealLog] {
        return meals.filter {
            $0.ownerID == ownerID && $0.eatenAt >= startDate && $0.eatenAt < endDate
        }
    }

    func createMealLog(_ meal: MealLog) async throws {
        if meals.contains(where: { $0.id == meal.id }) {
            throw MealRepositoryError.mealLogAlreadyExists(id: meal.id)
        }
        meals.append(meal)
    }

    func updateMealLog(_ meal: MealLog) async throws {
        guard let index = meals.firstIndex(where: { $0.id == meal.id }) else {
            throw MealRepositoryError.mealLogNotFound(id: meal.id)
        }
        meals[index] = meal
    }

    func duplicateMealLog(from source: MealLog, eatenAt: Date) -> MealLog {
        let copy = MealLog(
            ownerID: source.ownerID,
            visibility: source.visibility,
            sharingGroupID: source.sharingGroupID,
            eatenAt: eatenAt,
            timing: source.timing,
            notes: source.notes,
            alcoholStandardDrinks: source.alcoholStandardDrinks
        )
        copy.items = source.items.map { Self.cloneMealItem(from: $0) }
        return copy
    }

    func duplicateMealLog(fromRecurringTemplate template: RecurringMeal, eatenAt: Date) -> MealLog {
        let copy = MealLog(
            ownerID: template.ownerID,
            visibility: template.visibility,
            sharingGroupID: template.sharingGroupID,
            eatenAt: eatenAt,
            timing: template.preferredTiming,
            notes: template.name,
            alcoholStandardDrinks: 0
        )
        copy.items = template.items.map { Self.cloneMealItem(from: $0) }
        return copy
    }

    func deleteMealLog(id: UUID) async throws {
        meals.removeAll { $0.id == id }
    }

    private static func cloneMealItem(from source: MealItem) -> MealItem {
        MealItem(
            name: source.name,
            amount: source.amount,
            unit: source.unit,
            calories: source.calories,
            proteinGrams: source.proteinGrams,
            carbsGrams: source.carbsGrams,
            fatGrams: source.fatGrams,
            fiberGrams: source.fiberGrams,
            alcoholGrams: source.alcoholGrams
        )
    }
}

final class MockGoalRepository: GoalRepository {
    private var goals: [GoalProfile]
    private var targetsByGoalID: [UUID: DailyTargets]

    init() {
        let seeded = MockSeedData.makeGoalProfileAndTargets()
        self.goals = [seeded.profile]
        self.targetsByGoalID = [seeded.profile.id: seeded.targets]
    }

    func fetchGoalProfiles(ownerID: String) async throws -> [GoalProfile] {
        return goals.filter { $0.ownerID == ownerID }
    }

    func upsertGoalProfile(_ profile: GoalProfile) async throws {
        if let index = goals.firstIndex(where: { $0.id == profile.id }) {
            goals[index] = profile
        } else {
            goals.append(profile)
        }
    }

    func fetchDailyTargets(goalProfileID: UUID) async throws -> DailyTargets? {
        return targetsByGoalID[goalProfileID]
    }

    func saveDailyTargets(_ targets: DailyTargets, goalProfileID: UUID) async throws {
        targetsByGoalID[goalProfileID] = targets
    }
}

final class MockFineTuneCorrectionRepository: FineTuneCorrectionRepository {
    private var corrections: [FineTuneCorrection] = []

    func fetchCorrections(ownerID: String, since: Date?) async throws -> [FineTuneCorrection] {
        let ownerScoped = corrections.filter { $0.ownerID == ownerID }
        guard let since else { return ownerScoped }
        return ownerScoped.filter { $0.createdAt >= since }
    }

    func saveCorrection(_ correction: FineTuneCorrection) async throws {
        corrections.append(correction)
    }
}

final class MockRecurringMealRepository: RecurringMealRepository {
    private var recurringMeals: [RecurringMeal]

    init() {
        self.recurringMeals = MockSeedData.makeRecurringMeals()
    }

    func fetchRecurringMeals(ownerID: String, activeOnly: Bool) async throws -> [RecurringMeal] {
        let ownerScoped = recurringMeals.filter { $0.ownerID == ownerID }
        return activeOnly ? ownerScoped.filter(\.isActive) : ownerScoped
    }

    func upsertRecurringMeal(_ recurringMeal: RecurringMeal) async throws {
        if let index = recurringMeals.firstIndex(where: { $0.id == recurringMeal.id }) {
            recurringMeals[index] = recurringMeal
        } else {
            recurringMeals.append(recurringMeal)
        }
    }
}

final class MockAlcoholPlanRepository: AlcoholPlanRepository {
    private var plansByOwnerID: [String: AlcoholPlan]

    init() {
        let plan = MockSeedData.makeAlcoholPlan()
        self.plansByOwnerID = [plan.ownerID: plan]
    }

    func fetchAlcoholPlan(ownerID: String) async throws -> AlcoholPlan? {
        return plansByOwnerID[ownerID]
    }

    func saveAlcoholPlan(_ plan: AlcoholPlan) async throws {
        plansByOwnerID[plan.ownerID] = plan
    }
}

final class MockWeightLogRepository: WeightLogRepository {
    private var logs: [WeightLog] = []

    func fetchWeightLogs(ownerID: String, limit: Int?) async throws -> [WeightLog] {
        let ownerScoped = logs.filter { $0.ownerID == ownerID }.sorted { $0.loggedAt > $1.loggedAt }
        guard let limit else { return ownerScoped }
        return Array(ownerScoped.prefix(limit))
    }

    func saveWeightLog(_ log: WeightLog) async throws {
        logs.append(log)
    }
}

final class MockAppConfigRepository: AppConfigRepository {
    private var configsByOwnerID: [String: AppConfig] = [:]

    func fetchAppConfig(ownerID: String) async throws -> AppConfig? {
        return configsByOwnerID[ownerID]
    }

    func saveAppConfig(_ config: AppConfig) async throws {
        configsByOwnerID[config.ownerID] = config
    }
}

private enum MockSeedData {
    static let ownerID = "preview.user"

    static func makeGoalProfileAndTargets() -> (profile: GoalProfile, targets: DailyTargets) {
        let targets = DailyTargets(
            calories: 2100,
            proteinGrams: 150,
            carbsGrams: 210,
            fatGrams: 70,
            fiberGrams: 30,
            waterMilliliters: 2600
        )
        let profile = GoalProfile(
            ownerID: ownerID,
            title: "Lean maintenance",
            notes: "Default seeded profile for dashboard-first flow."
        )
        profile.dailyTargets = targets
        return (profile, targets)
    }

    static func makeMealLogs() -> [MealLog] {
        let breakfast = MealLog(
            ownerID: ownerID,
            eatenAt: Calendar.current.date(byAdding: .hour, value: -4, to: .now) ?? .now,
            timing: .breakfast,
            notes: "High-protein breakfast."
        )
        breakfast.items = [
            MealItem(
                name: "Greek yogurt",
                amount: 220,
                unit: "g",
                calories: 210,
                proteinGrams: 22,
                carbsGrams: 10,
                fatGrams: 9,
                fiberGrams: 0
            ),
            MealItem(
                name: "Banana",
                amount: 1,
                unit: "item",
                calories: 110,
                proteinGrams: 1,
                carbsGrams: 28,
                fatGrams: 0,
                fiberGrams: 3
            )
        ]

        let lunch = MealLog(
            ownerID: ownerID,
            eatenAt: Calendar.current.date(byAdding: .hour, value: -1, to: .now) ?? .now,
            timing: .lunch,
            notes: "Lunch before meetings.",
            alcoholStandardDrinks: 1
        )
        lunch.items = [
            MealItem(
                name: "Chicken bowl",
                amount: 1,
                unit: "serving",
                calories: 610,
                proteinGrams: 44,
                carbsGrams: 54,
                fatGrams: 20,
                fiberGrams: 7
            ),
            MealItem(
                name: "Red wine",
                amount: 150,
                unit: "ml",
                calories: 120,
                proteinGrams: 0,
                carbsGrams: 4,
                fatGrams: 0,
                fiberGrams: 0,
                alcoholGrams: 14
            )
        ]
        return [breakfast, lunch]
    }

    static func makeRecurringMeals() -> [RecurringMeal] {
        let breakfast = RecurringMeal(
            ownerID: ownerID,
            name: "Weekday protein breakfast",
            cadenceDays: 1,
            preferredTiming: .breakfast
        )
        let dinner = RecurringMeal(
            ownerID: ownerID,
            name: "Fast high-fiber dinner bowl",
            cadenceDays: 2,
            preferredTiming: .dinner
        )
        let snack = RecurringMeal(
            ownerID: ownerID,
            name: "Post-lift snack",
            cadenceDays: 1,
            preferredTiming: .snack
        )
        return [breakfast, dinner, snack]
    }

    static func makeAlcoholPlan() -> AlcoholPlan {
        AlcoholPlan(
            ownerID: ownerID,
            maxStandardDrinksPerDay: 2,
            maxStandardDrinksPerWeek: 8,
            alcoholFreeDaysTarget: 3
        )
    }
}
