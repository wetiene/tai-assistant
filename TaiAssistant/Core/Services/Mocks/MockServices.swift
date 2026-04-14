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

actor MockMealRepository: MealRepository {
    private var meals: [MealLog] = []

    func fetchMealLogs(ownerID: String, from startDate: Date, to endDate: Date) async throws -> [MealLog] {
        meals.filter {
            $0.ownerID == ownerID && $0.eatenAt >= startDate && $0.eatenAt < endDate
        }
    }

    func upsertMealLog(_ mealLog: MealLog) async throws {
        if let index = meals.firstIndex(where: { $0.id == mealLog.id }) {
            meals[index] = mealLog
        } else {
            meals.append(mealLog)
        }
    }

    func deleteMealLog(id: UUID) async throws {
        meals.removeAll { $0.id == id }
    }
}

actor MockGoalRepository: GoalRepository {
    private var goals: [GoalProfile] = []
    private var targetsByGoalID: [UUID: DailyTargets] = [:]

    func fetchGoalProfiles(ownerID: String) async throws -> [GoalProfile] {
        goals.filter { $0.ownerID == ownerID }
    }

    func upsertGoalProfile(_ profile: GoalProfile) async throws {
        if let index = goals.firstIndex(where: { $0.id == profile.id }) {
            goals[index] = profile
        } else {
            goals.append(profile)
        }
    }

    func fetchDailyTargets(goalProfileID: UUID) async throws -> DailyTargets? {
        targetsByGoalID[goalProfileID]
    }

    func saveDailyTargets(_ targets: DailyTargets, goalProfileID: UUID) async throws {
        targetsByGoalID[goalProfileID] = targets
    }
}

actor MockFineTuneCorrectionRepository: FineTuneCorrectionRepository {
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

actor MockRecurringMealRepository: RecurringMealRepository {
    private var recurringMeals: [RecurringMeal] = []

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

actor MockAlcoholPlanRepository: AlcoholPlanRepository {
    private var plansByOwnerID: [String: AlcoholPlan] = [:]

    func fetchAlcoholPlan(ownerID: String) async throws -> AlcoholPlan? {
        plansByOwnerID[ownerID]
    }

    func saveAlcoholPlan(_ plan: AlcoholPlan) async throws {
        plansByOwnerID[plan.ownerID] = plan
    }
}

actor MockWeightLogRepository: WeightLogRepository {
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

actor MockAppConfigRepository: AppConfigRepository {
    private var configsByOwnerID: [String: AppConfig] = [:]

    func fetchAppConfig(ownerID: String) async throws -> AppConfig? {
        configsByOwnerID[ownerID]
    }

    func saveAppConfig(_ config: AppConfig) async throws {
        configsByOwnerID[config.ownerID] = config
    }
}
