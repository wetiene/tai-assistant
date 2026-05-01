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
    var messages: [CheckInMessage] = []
    var isInterpreting = false
    var isSaving = false
    var errorMessage: String?
    private(set) var dayProgress = DayProgress()
    private let maxMessages = 6

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

    func onUpdateMealTapped() async {
        guard !isInterpreting else { return }
        let rawInput = session.userInput.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasPhoto = session.selectedPhotoData != nil
        if rawInput.isEmpty && !hasPhoto && session.interpretedMeals.isEmpty {
            return
        }
        if !rawInput.isEmpty || hasPhoto {
            appendMessage(role: .user, text: rawInput.isEmpty ? "Updated meal details from photo" : rawInput)
        }
        session.userInput = ""

        await runInterpretation(input: buildInterpretationInput(from: rawInput))
    }

    func updateEstimate(for mealId: UUID) async {
        guard !isInterpreting else { return }
        guard let meal = session.interpretedMeals.first(where: { $0.id == mealId }) else { return }
        let request = "Re-estimate this meal based on current confirmed label: \(meal.label)."
        appendMessage(role: .user, text: "Update estimate: \(meal.label)")
        await runInterpretation(input: buildInterpretationInput(from: request))
    }

    private func runInterpretation(input: String) async {
        guard !isInterpreting else { return }
        isInterpreting = true
        defer { isInterpreting = false }
        do {
            let interpretation = try await interpreter.interpret(
                input: input,
                photoData: session.selectedPhotoData
            )
            session.interpretedMeals = mergeMeals(existing: session.interpretedMeals, updated: interpretation.meals)
            for idx in session.interpretedMeals.indices {
                session.interpretedMeals[idx].macrosNeedReview = false
                session.interpretedMeals[idx].lastMacroEstimateBasis = session.interpretedMeals[idx].label
            }
            session.interpretationNotes = interpretation.uiNotes
            appendMessage(role: .tai, text: "Updated estimate")
            await refreshDayProgress()
        } catch {
            errorMessage = "Could not interpret this check in. Please try again."
            appendMessage(role: .tai, text: "Couldn't update estimate. Please try again.")
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
        meal.macrosNeedReview = true
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

    private func buildInterpretationInput(from userText: String) -> String {
        let cleaned = userText.trimmingCharacters(in: .whitespacesAndNewlines)
        let mealContext = session.interpretedMeals.enumerated().map { idx, meal in
            "Meal \(idx + 1): \(meal.label)"
        }
        let contextLine = mealContext.isEmpty ? "" : "\nCurrent meal state:\n" + mealContext.joined(separator: "\n")
        if cleaned.isEmpty {
            return "Update the meal estimate using the current meal state and photo context if present.\(contextLine)"
        }
        return "\(cleaned)\(contextLine)"
    }

    private func mergeMeals(existing: [CheckInMealDraft], updated: [CheckInMealDraft]) -> [CheckInMealDraft] {
        guard !existing.isEmpty else { return updated }
        var merged: [CheckInMealDraft] = []
        for (idx, freshMeal) in updated.enumerated() {
            guard idx < existing.count else {
                merged.append(freshMeal)
                continue
            }
            let current = existing[idx]
            var meal = current
            meal.timing = freshMeal.timing
            meal.eatenAt = freshMeal.eatenAt
            meal.calories = freshMeal.calories
            meal.proteinGrams = freshMeal.proteinGrams
            meal.carbsGrams = freshMeal.carbsGrams
            meal.fatGrams = freshMeal.fatGrams
            meal.confidence = freshMeal.confidence
            meal.items = freshMeal.items
            meal.alternatives = current.isUserConfirmed ? [] : freshMeal.alternatives
            meal.label = current.isUserConfirmed ? current.label : freshMeal.label
            meal.isUserConfirmed = current.isUserConfirmed
            meal.originalAILabel = current.originalAILabel ?? freshMeal.originalAILabel
            merged.append(meal)
        }
        if existing.count > updated.count {
            merged.append(contentsOf: existing.dropFirst(updated.count))
        }
        return merged
    }

    private func appendMessage(role: MessageRole, text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        messages.append(CheckInMessage(id: UUID(), role: role, text: trimmed))
        if messages.count > maxMessages {
            messages = Array(messages.suffix(maxMessages))
        }
    }
}
