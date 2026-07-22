import Foundation

enum NutritionDayAggregation {
    struct MacroTotals: Equatable, Sendable {
        let mealCount: Int
        let calories: Int
        let proteinGrams: Double
        let carbsGrams: Double
        let fatGrams: Double
    }

    /// Aggregates confirmed meal line items for one nutrition day.
    ///
    /// Callers must pass meals already filtered to the target day via `MealLog.eatenAt`.
    static func macroTotals(from meals: [MealLog]) -> MacroTotals {
        let items = meals.flatMap(\.items)
        return MacroTotals(
            mealCount: meals.count,
            calories: items.reduce(0) { $0 + $1.calories },
            proteinGrams: items.reduce(0) { $0 + $1.proteinGrams },
            carbsGrams: items.reduce(0) { $0 + $1.carbsGrams },
            fatGrams: items.reduce(0) { $0 + $1.fatGrams }
        )
    }
}
