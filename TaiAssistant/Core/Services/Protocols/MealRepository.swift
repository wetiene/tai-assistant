import Foundation

/// Explicit meal write failures (avoid silent ambiguous saves).
enum MealRepositoryError: Error, Equatable {
    case mealLogNotFound(id: UUID)
    case mealLogAlreadyExists(id: UUID)
}

/// Confirmed meal history: **create** (new log), **update** (replace truth on one log), **delete**.
/// **Repeats** are always `duplicateMealLog` → `createMealLog`, never `updateMealLog` on the source.
protocol MealRepository {
    func fetchMealLogs(ownerID: String, from startDate: Date, to endDate: Date) async throws -> [MealLog]

    /// Persists a **new** `MealLog` and its line items (insert-only). Typical path after capture / manual entry.
    func createMealLog(_ meal: MealLog) async throws

    /// Updates top-level fields and **fully replaces** all `MealItem` rows for this id (no partial item diff in V1).
    func updateMealLog(_ meal: MealLog) async throws

    /// Builds a new, **unsaved** meal graph from an existing log (new ids). Persist with `createMealLog`. Does not mutate `source`.
    func duplicateMealLog(from source: MealLog, eatenAt: Date) -> MealLog

    /// Builds a new, **unsaved** meal from a recurring shortcut template. Persist with `createMealLog`. Does not mutate `template`.
    func duplicateMealLog(fromRecurringTemplate template: RecurringMeal, eatenAt: Date) -> MealLog

    func deleteMealLog(id: UUID) async throws
}
