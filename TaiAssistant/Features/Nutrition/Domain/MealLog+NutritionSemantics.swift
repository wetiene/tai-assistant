import Foundation

extension MealLog {
    /// Nutrition day bucket for this meal, derived from `eatenAt`.
    func nutritionDay(calendar: Calendar = .current) -> NutritionDay {
        NutritionDay(containing: eatenAt, calendar: calendar)
    }

    /// True when the meal was first recorded on a later calendar day than when it occurred.
    ///
    /// Compares audit `createdAt` against occurrence `eatenAt` using device-local day boundaries.
    func wasRecordedAfterOccurrenceDay(calendar: Calendar = .current) -> Bool {
        nutritionDay(calendar: calendar).start < NutritionDay(containing: createdAt, calendar: calendar).start
    }
}

/// Repository write semantics for confirmed meal artifacts.
enum MealLogWriteSemantics {
    /// `createdAt` is immutable after the first persist. Updates must never rewrite it.
    static func assertCreatedAtImmutableOnUpdate(existing: MealLog, incoming: MealLog) {
        assert(
            existing.createdAt == incoming.createdAt,
            "MealLog.createdAt is immutable after creation (meal \(existing.id))."
        )
    }
}
