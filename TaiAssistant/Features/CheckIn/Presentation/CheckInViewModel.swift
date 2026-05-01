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
        await runInterpretation(input: buildInterpretationInput(from: request), explicitReestimateMealID: mealId)
    }

    private func runInterpretation(input: String, explicitReestimateMealID: UUID? = nil) async {
        guard !isInterpreting else { return }
        isInterpreting = true
        defer { isInterpreting = false }
        do {
            let interpretation = try await interpreter.interpret(
                input: input,
                photoData: session.selectedPhotoData
            )
            let reconciliation = mergeAIResponseIntoDrafts(
                existingDrafts: session.interpretedMeals,
                aiMeals: interpretation.meals,
                explicitReestimateMealID: explicitReestimateMealID
            )
            session.interpretedMeals = reconciliation.drafts
            for idx in session.interpretedMeals.indices {
                let draftID = session.interpretedMeals[idx].id
                guard reconciliation.reestimatedDraftIDs.contains(draftID) else { continue }
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

    private struct MealReconciliationResult {
        var drafts: [CheckInMealDraft]
        var reestimatedDraftIDs: Set<UUID>
    }

    private enum MealMatchScoring {
        /// Highest confidence when normalized labels are identical.
        static let exactMatchScore = 100
        /// Strong confidence when one normalized label contains the other.
        static let containsScore = 75
        /// Small boost for each overlapping normalized label token.
        static let tokenOverlapWeight = 8
        /// Timing agreement nudges otherwise similar labels.
        static let timingScore = 12
        /// Require at least this score to accept a match.
        static let minimumMatchScore = 60
    }

    private func normalizedMealKey(for meal: CheckInMealDraft) -> String {
        let candidates = [
            normalizedMealLabel(meal.label),
            normalizedMealLabel(meal.originalAILabel),
            normalizedMealLabel(meal.lastMacroEstimateBasis),
        ].filter { !$0.isEmpty }
        return candidates.first ?? ""
    }

    private func bestMatchExistingDraft(
        for aiMeal: CheckInMealDraft,
        existingDrafts: [CheckInMealDraft],
        availableIDs: Set<UUID>,
        explicitReestimateMealID: UUID?
    ) -> UUID? {
        if let explicitReestimateMealID, availableIDs.contains(explicitReestimateMealID) {
            return explicitReestimateMealID
        }

        let aiKey = normalizedMealKey(for: aiMeal)
        let aiLabelTokens = Set(aiKey.split(separator: " ").map(String.init))

        var scored: [(id: UUID, score: Int)] = []
        for draft in existingDrafts where availableIDs.contains(draft.id) {
            let draftKey = normalizedMealKey(for: draft)
            if draftKey.isEmpty || aiKey.isEmpty { continue }

            var score = 0
            if draftKey == aiKey {
                score += MealMatchScoring.exactMatchScore
            } else if draftKey.contains(aiKey) || aiKey.contains(draftKey) {
                score += MealMatchScoring.containsScore
            }

            let draftTokens = Set(draftKey.split(separator: " ").map(String.init))
            if !draftTokens.isEmpty && !aiLabelTokens.isEmpty {
                let overlap = draftTokens.intersection(aiLabelTokens).count
                if overlap > 0 {
                    score += overlap * MealMatchScoring.tokenOverlapWeight
                }
            }

            if draft.timing == aiMeal.timing {
                score += MealMatchScoring.timingScore
            }

            if score > 0 {
                scored.append((id: draft.id, score: score))
            }
        }

        guard let top = scored.max(by: { $0.score < $1.score }) else { return nil }
        let tiedTopCount = scored.filter { $0.score == top.score }.count
        if tiedTopCount > 1 {
            return nil
        }
        return top.score >= MealMatchScoring.minimumMatchScore ? top.id : nil
    }

    private func mergeAIResponseIntoDrafts(
        existingDrafts: [CheckInMealDraft],
        aiMeals: [CheckInMealDraft],
        explicitReestimateMealID: UUID?
    ) -> MealReconciliationResult {
        var drafts = existingDrafts
        var availableIDs = Set(existingDrafts.map(\.id))
        var reestimatedDraftIDs = Set<UUID>()
        var newDrafts: [CheckInMealDraft] = []

        if let explicitReestimateMealID,
           let targetIndex = drafts.firstIndex(where: { $0.id == explicitReestimateMealID }) {
            guard let aiMeal = bestAIResultForExplicitReestimate(target: drafts[targetIndex], aiMeals: aiMeals) else {
                // Explicit re-estimate should fail safe: keep current draft and surface macro review state.
                drafts[targetIndex].macrosNeedReview = true
                return MealReconciliationResult(drafts: drafts, reestimatedDraftIDs: reestimatedDraftIDs)
            }

            let current = drafts[targetIndex]
            var merged = current
            merged.timing = aiMeal.timing
            merged.eatenAt = aiMeal.eatenAt
            merged.calories = aiMeal.calories
            merged.proteinGrams = aiMeal.proteinGrams
            merged.carbsGrams = aiMeal.carbsGrams
            merged.fatGrams = aiMeal.fatGrams
            merged.confidence = aiMeal.confidence
            merged.items = aiMeal.items
            merged.alternatives = current.isUserConfirmed ? [] : aiMeal.alternatives
            if !current.isUserConfirmed {
                merged.label = aiMeal.label
            }
            merged.originalAILabel = current.originalAILabel ?? aiMeal.originalAILabel
            drafts[targetIndex] = merged
            reestimatedDraftIDs.insert(explicitReestimateMealID)
            return MealReconciliationResult(drafts: drafts, reestimatedDraftIDs: reestimatedDraftIDs)
        }

        for aiMeal in aiMeals {
            guard let matchedID = bestMatchExistingDraft(
                for: aiMeal,
                existingDrafts: existingDrafts,
                availableIDs: availableIDs,
                explicitReestimateMealID: explicitReestimateMealID
            ) else {
                newDrafts.append(aiMeal)
                reestimatedDraftIDs.insert(aiMeal.id)
                continue
            }

            guard let idx = drafts.firstIndex(where: { $0.id == matchedID }) else { continue }
            let current = drafts[idx]

            var merged = current
            merged.timing = aiMeal.timing
            merged.eatenAt = aiMeal.eatenAt
            merged.calories = aiMeal.calories
            merged.proteinGrams = aiMeal.proteinGrams
            merged.carbsGrams = aiMeal.carbsGrams
            merged.fatGrams = aiMeal.fatGrams
            merged.confidence = aiMeal.confidence
            merged.items = aiMeal.items
            merged.alternatives = current.isUserConfirmed ? [] : aiMeal.alternatives
            if !current.isUserConfirmed {
                merged.label = aiMeal.label
            }
            merged.originalAILabel = current.originalAILabel ?? aiMeal.originalAILabel

            drafts[idx] = merged
            availableIDs.remove(matchedID)
            reestimatedDraftIDs.insert(matchedID)
        }

        drafts.append(contentsOf: newDrafts)
        return MealReconciliationResult(drafts: drafts, reestimatedDraftIDs: reestimatedDraftIDs)
    }

    private func bestAIResultForExplicitReestimate(
        target: CheckInMealDraft,
        aiMeals: [CheckInMealDraft]
    ) -> CheckInMealDraft? {
        guard !aiMeals.isEmpty else { return nil }
        let targetKey = normalizedMealKey(for: target)
        guard !targetKey.isEmpty else { return nil }

        let targetTokens = Set(targetKey.split(separator: " ").map(String.init))
        let scored = aiMeals.map { aiMeal -> (meal: CheckInMealDraft, score: Int) in
            let aiKey = normalizedMealKey(for: aiMeal)
            if aiKey.isEmpty { return (aiMeal, 0) }
            var score = 0
            if aiKey == targetKey {
                score += MealMatchScoring.exactMatchScore
            } else if aiKey.contains(targetKey) || targetKey.contains(aiKey) {
                score += MealMatchScoring.containsScore
            }
            let aiTokens = Set(aiKey.split(separator: " ").map(String.init))
            let overlap = aiTokens.intersection(targetTokens).count
            score += overlap * MealMatchScoring.tokenOverlapWeight
            if aiMeal.timing == target.timing {
                score += MealMatchScoring.timingScore
            }
            return (aiMeal, score)
        }
        guard let top = scored.max(by: { $0.score < $1.score }) else { return nil }
        let tiedTopCount = scored.filter { $0.score == top.score }.count
        guard tiedTopCount == 1 else { return nil }
        guard top.score >= MealMatchScoring.minimumMatchScore else { return nil }
        return top.meal
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
