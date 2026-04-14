import Foundation

protocol MealRepository {
    func fetchMeals(for date: Date) async throws -> [MealRecord]
    func saveMeal(summary: String, date: Date) async throws
}
