import Foundation
import Observation

@Observable @MainActor
final class CheckInViewModel {
    struct DayProgress: Equatable {
        var consumedCalories: Int = 0
        var targetCalories: Int = 2100
        var consumedProtein: Int = 0
        var proteinTarget: Int = 150
    }

    private let mealRepository: MealRepository
    private let ownerID: String
    private let interpreter: any CheckInInterpreting
    private let onMealsSaved: (() -> Void)?

    var session = CheckInSessionDraft()
    var isInterpreting = false
    var isSaving = false
    var errorMessage: String?
    private(set) var dayProgress = DayProgress()

    init(
        mealRepository: MealRepository,
        ownerID: String,
        interpreter: any CheckInInterpreting,
        onMealsSaved: (() -> Void)? = nil
    ) {
        self.mealRepository = mealRepository
        self.ownerID = ownerID
        self.interpreter = interpreter
        self.onMealsSaved = onMealsSaved
    }

    func interpretCheckIn() async {
        guard !isInterpreting else { return }
        isInterpreting = true
        defer { isInterpreting = false }
        do {
            let interpretation = try await interpreter.interpret(
                input: session.userInput,
                photoData: session.selectedPhotoData
            )
            session.interpretedMeals = interpretation.meals
            session.interpretationNotes = interpretation.uiNotes
            await refreshDayProgress()
        } catch {
            errorMessage = "Could not interpret this check in. Please try again."
        }
    }

    func saveInterpretedMeals() {
        guard !isSaving else { return }
        Task {
            isSaving = true
            defer { isSaving = false }
            do {
                for draft in session.interpretedMeals {
                    let mealLog = MealLog(
                        ownerID: ownerID,
                        eatenAt: draft.eatenAt,
                        timing: draft.timing,
                        notes: draft.label
                    )
                    mealLog.items = draft.items.map { item in
                        MealItem(
                            name: item.name,
                            amount: item.amount,
                            unit: item.unit,
                            calories: item.calories,
                            proteinGrams: item.proteinGrams,
                            carbsGrams: item.carbsGrams,
                            fatGrams: item.fatGrams,
                            fiberGrams: item.fiberGrams
                        )
                    }
                    try await mealRepository.createMealLog(mealLog)
                }
                session = CheckInSessionDraft()
                onMealsSaved?()
                await refreshDayProgress()
            } catch {
                errorMessage = "Could not save check in meals. Please retry."
            }
        }
    }

    func refreshDayProgress() async {
        let calendar = Calendar.current
        let dayStart = calendar.startOfDay(for: .now)
        let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) ?? .now
        do {
            let meals = try await mealRepository.fetchMealLogs(ownerID: ownerID, from: dayStart, to: dayEnd)
            let consumedCalories = meals.flatMap(\.items).reduce(0) { $0 + $1.calories }
            let consumedProtein = Int(meals.flatMap(\.items).reduce(0.0) { $0 + $1.proteinGrams }.rounded())
            dayProgress.consumedCalories = consumedCalories
            dayProgress.consumedProtein = consumedProtein
        } catch {
            // Keep prior day progress values if refresh fails.
        }
    }

    func selectAlternative(_ alt: String, for mealId: UUID) {
        guard let idx = session.interpretedMeals.firstIndex(where: { $0.id == mealId }) else { return }
        var meal = session.interpretedMeals[idx]
        meal.label = alt
        meal.alternatives = []
        meal.isUserConfirmed = true
        meal.macrosNeedReview = shouldFlagMacrosForLabelChange(in: meal, newLabel: alt)
        session.interpretedMeals[idx] = meal
    }

    /// Call when the user edits the meal label field so their text stays authoritative and ambiguity chips clear.
    func registerUserEditedMealLabel(for mealId: UUID) {
        guard let idx = session.interpretedMeals.firstIndex(where: { $0.id == mealId }) else { return }
        var meal = session.interpretedMeals[idx]
        meal.isUserConfirmed = true
        meal.alternatives = []
        meal.macrosNeedReview = shouldFlagMacrosForLabelChange(in: meal, newLabel: meal.label)
        session.interpretedMeals[idx] = meal
    }

    // TODO(CheckIn): Add a lightweight per-meal "Re-estimate" that refreshes macros/items for corrected labels.
    // Current flow intentionally stays non-blocking: corrected label is saved while stale macro state is surfaced.
    private func shouldFlagMacrosForLabelChange(in meal: CheckInMealDraft, newLabel: String) -> Bool {
        let basis = normalizedMealLabel(meal.lastMacroEstimateBasis)
        let edited = normalizedMealLabel(newLabel)
        guard !edited.isEmpty else { return meal.macrosNeedReview }
        return basis != edited
    }

    private func normalizedMealLabel(_ value: String?) -> String {
        (value ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}
