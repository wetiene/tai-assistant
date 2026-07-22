import Foundation

extension MealRepository {
    /// Fetches confirmed meals whose `eatenAt` falls on `day` using half-open day bounds.
    func fetchMealLogs(
        ownerID: String,
        on day: NutritionDay,
        calendar: Calendar = .current
    ) async throws -> [MealLog] {
        let bounds = day.queryBounds(calendar: calendar)
        return try await fetchMealLogs(ownerID: ownerID, from: bounds.start, to: bounds.end)
    }
}
