import Foundation

struct MockAIService: AIService {
    func send(message: String, context: [String: String]) async throws -> String {
        "Mock response from Tai: \(message)"
    }

    func interpretMeal(request: AIInterpretMealRequest) async throws -> AIInterpretMealResponse {
        try await Task.sleep(nanoseconds: 300_000_000)

        let normalized = request.text?.lowercased() ?? ""
        let now = Date()
        let isoFormatter = ISO8601DateFormatter()
        let containsImage = request.image?.base64Data?.isEmpty == false || request.image?.uploadReference?.isEmpty == false

        let defaultMeal = AIInterpretedMeal(
            label: "Detected meal",
            timing: "other",
            eatenAtGuessISO8601: isoFormatter.string(from: now),
            items: [
                AIInterpretedMealItem(
                    name: "Main plate",
                    amount: 280,
                    unit: "g",
                    calories: 370,
                    proteinGrams: 24,
                    carbsGrams: 35,
                    fatGrams: 14,
                    fiberGrams: 4
                ),
                AIInterpretedMealItem(
                    name: "Side",
                    amount: 120,
                    unit: "g",
                    calories: 150,
                    proteinGrams: 8,
                    carbsGrams: 19,
                    fatGrams: 4,
                    fiberGrams: 3
                )
            ],
            calories: containsImage ? 610 : 520,
            proteinGrams: 32,
            carbsGrams: 54,
            fatGrams: 18,
            confidence: 0.63
        )

        if normalized.contains("breakfast") || normalized.contains("shake") {
            return AIInterpretMealResponse(
                interpretedMeals: [
                    AIInterpretedMeal(
                        label: normalized.contains("shake") ? "Protein shake" : "Usual breakfast",
                        timing: "breakfast",
                        eatenAtGuessISO8601: isoFormatter.string(from: now),
                        items: [
                            AIInterpretedMealItem(name: "Whey protein", amount: 35, unit: "g", calories: 140, proteinGrams: 28, carbsGrams: 3, fatGrams: 2, fiberGrams: 0),
                            AIInterpretedMealItem(name: "Banana", amount: 100, unit: "g", calories: 89, proteinGrams: 1.1, carbsGrams: 23, fatGrams: 0.3, fiberGrams: 2.6),
                            AIInterpretedMealItem(name: "Milk", amount: 240, unit: "ml", calories: 110, proteinGrams: 8, carbsGrams: 11, fatGrams: 5, fiberGrams: 0)
                        ],
                        calories: normalized.contains("shake") ? 280 : 430,
                        proteinGrams: normalized.contains("shake") ? 34 : 33,
                        carbsGrams: normalized.contains("shake") ? 24 : 46,
                        fatGrams: normalized.contains("shake") ? 7 : 14,
                        confidence: 0.83
                    )
                ],
                uiNotes: "Mock AI interpretation. Adjust items before saving."
            )
        }

        if normalized.contains("lunch") || normalized.contains("dinner") || normalized.contains("family") {
            return AIInterpretMealResponse(
                interpretedMeals: [
                    AIInterpretedMeal(
                        label: normalized.contains("family") ? "Family dinner" : "Inferred meal",
                        timing: normalized.contains("dinner") || normalized.contains("family") ? "dinner" : "lunch",
                        eatenAtGuessISO8601: isoFormatter.string(from: now),
                        items: [
                            AIInterpretedMealItem(name: "Chicken breast", amount: 140, unit: "g", calories: 220, proteinGrams: 43, carbsGrams: 0, fatGrams: 4.5, fiberGrams: 0),
                            AIInterpretedMealItem(name: "Rice", amount: 160, unit: "g", calories: 210, proteinGrams: 4, carbsGrams: 45, fatGrams: 0.5, fiberGrams: 1),
                            AIInterpretedMealItem(name: "Vegetables", amount: 110, unit: "g", calories: 80, proteinGrams: 3, carbsGrams: 13, fatGrams: 1, fiberGrams: 4)
                        ],
                        calories: normalized.contains("family") ? 760 : 620,
                        proteinGrams: normalized.contains("family") ? 42 : 36,
                        carbsGrams: normalized.contains("family") ? 71 : 58,
                        fatGrams: normalized.contains("family") ? 31 : 24,
                        confidence: 0.76
                    )
                ],
                uiNotes: "Mock AI interpretation. Nutrients are approximate."
            )
        }

        return AIInterpretMealResponse(
            interpretedMeals: [defaultMeal],
            uiNotes: "Mock AI interpretation from generic meal template."
        )
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
