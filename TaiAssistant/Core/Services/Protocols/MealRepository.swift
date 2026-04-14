import Foundation

protocol MealRepository {
    func fetchMealLogs(ownerID: String, from startDate: Date, to endDate: Date) async throws -> [MealLog]
    func upsertMealLog(_ mealLog: MealLog) async throws
    func deleteMealLog(id: UUID) async throws
}
