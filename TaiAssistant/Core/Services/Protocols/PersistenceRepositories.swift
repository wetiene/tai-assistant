import Foundation

protocol FineTuneCorrectionRepository {
    func fetchCorrections(ownerID: String, since: Date?) async throws -> [FineTuneCorrection]
    func saveCorrection(_ correction: FineTuneCorrection) async throws
}

protocol RecurringMealRepository {
    func fetchRecurringMeals(ownerID: String, activeOnly: Bool) async throws -> [RecurringMeal]
    func upsertRecurringMeal(_ recurringMeal: RecurringMeal) async throws
}

protocol AlcoholPlanRepository {
    func fetchAlcoholPlan(ownerID: String) async throws -> AlcoholPlan?
    func saveAlcoholPlan(_ plan: AlcoholPlan) async throws
}

protocol WeightLogRepository {
    func fetchWeightLogs(ownerID: String, limit: Int?) async throws -> [WeightLog]
    func saveWeightLog(_ log: WeightLog) async throws
}

protocol AppConfigRepository {
    func fetchAppConfig(ownerID: String) async throws -> AppConfig?
    func saveAppConfig(_ config: AppConfig) async throws
}
