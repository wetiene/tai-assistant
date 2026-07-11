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
    var contextRows: [CheckInContextRow] = []
    var isInterpreting = false
    var isSaving = false
    var errorMessage: String?
    #if DEBUG
    /// Dev-only: full AI interpret failure detail for screenshot / triage (not used for meal save errors).
    var aiInterpretFailureDebugText: String?
    #endif
    private(set) var dayProgress = DayProgress()
    /// Row cap for scroll-back history (not the on-screen row count).
    private let maxStoredContextRows = 24

    private enum AutomatedInterpretationPrompt {
        static let photoOnlyNewSession = "Interpret this meal from the attached image."
        static let photoOnlyRefinement = "Update the meal estimate using structured meal context and the image if present."
        static func reestimate(label: String) -> String {
            "Re-estimate this meal based on current confirmed label: \(label)."
        }
    }

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
        if hasPhoto {
            ensurePhotoContextRow()
        }
        if !rawInput.isEmpty {
            appendContextRow(kind: .user, text: rawInput)
        }
        session.userInput = ""

        let activeMealIDForRefinement = (session.interpretedMeals.count == 1) ? session.interpretedMeals[0].id : nil
        await runInterpretation(
            input: buildInterpretationInput(from: rawInput),
            rawUserMessageForRefinement: rawInput,
            explicitReestimateMealID: activeMealIDForRefinement
        )
    }

    func updateEstimate(for mealId: UUID) async {
        guard !isInterpreting else { return }
        guard let meal = session.interpretedMeals.first(where: { $0.id == mealId }) else { return }
        let request = AutomatedInterpretationPrompt.reestimate(label: meal.label)
        await runInterpretation(
            input: buildInterpretationInput(from: request),
            rawUserMessageForRefinement: request,
            explicitReestimateMealID: mealId
        )
    }

    private func runInterpretation(
        input: String,
        rawUserMessageForRefinement: String? = nil,
        explicitReestimateMealID: UUID? = nil
    ) async {
        guard !isInterpreting else { return }
        #if DEBUG
        aiInterpretFailureDebugText = nil
        #endif
        isInterpreting = true
        defer { isInterpreting = false }
        let interpretRequestStarted = Date()
        do {
            let refinementPayload = buildMealRefinementPayload(
                rawUserMessageToExcludeFromPrior: rawUserMessageForRefinement
            )
            let interpretation = try await interpreter.interpret(
                input: input,
                photoData: session.selectedPhotoData,
                mealRefinement: refinementPayload
            )
            let capConfidence = shouldApplyUserLedRefinementConfidenceCap(rawUserMessage: rawUserMessageForRefinement)
            let reconciliation = mergeAIResponseIntoDrafts(
                existingDrafts: session.interpretedMeals,
                aiMeals: interpretation.meals,
                explicitReestimateMealID: explicitReestimateMealID,
                applyUserLedRefinementConfidenceCap: capConfidence
            )
            session.interpretedMeals = reconciliation.drafts
            for idx in session.interpretedMeals.indices {
                let draftID = session.interpretedMeals[idx].id
                guard reconciliation.reestimatedDraftIDs.contains(draftID) else { continue }
                session.interpretedMeals[idx].macrosNeedReview = false
                session.interpretedMeals[idx].lastMacroEstimateBasis = session.interpretedMeals[idx].label
            }
            session.interpretationNotes = interpretation.uiNotes
            appendContextRow(kind: .ai, text: aiSummaryText(from: interpretation))
            await refreshDayProgress()
        } catch {
            if let raw = rawUserMessageForRefinement?.trimmingCharacters(in: .whitespacesAndNewlines),
               !raw.isEmpty,
               !isAutomatedProxyUserText(raw),
               session.userInput.isEmpty {
                session.userInput = raw
            }
            errorMessage = "Could not interpret this check in. Please try again."
            #if DEBUG
            let elapsed = Date().timeIntervalSince(interpretRequestStarted)
            aiInterpretFailureDebugText = Self.formatInterpretFailureForDebug(error: error, requestDuration: elapsed)
            #endif
        }
    }

    func saveInterpretedMeals() {
        guard !isSaving, !isInterpreting else { return }
        isSaving = true
        let draftsToSave = session.interpretedMeals
        Task {
            defer { isSaving = false }
            var savedCount = 0
            do {
                for draft in draftsToSave {
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
                    savedCount += 1
                }
                session = CheckInSessionDraft()
                contextRows = []
                onMealsSaved?()
                await refreshDayProgress()
            } catch {
                if savedCount > 0 {
                    session.interpretedMeals = Array(draftsToSave.dropFirst(savedCount))
                    onMealsSaved?()
                    await refreshDayProgress()
                    let remaining = draftsToSave.count - savedCount
                    errorMessage = "Saved \(savedCount) meal\(savedCount == 1 ? "" : "s"). \(remaining) still need saving — tap Add to today to retry."
                } else {
                    errorMessage = "Could not save check in meals. Please retry."
                }
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
        if cleaned.isEmpty {
            if session.interpretedMeals.isEmpty {
                return AutomatedInterpretationPrompt.photoOnlyNewSession
            }
            return AutomatedInterpretationPrompt.photoOnlyRefinement
        }
        return cleaned
    }

    private func shouldApplyUserLedRefinementConfidenceCap(rawUserMessage: String?) -> Bool {
        guard let raw = rawUserMessage?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
            return false
        }
        if isAutomatedProxyUserText(raw) { return false }
        return true
    }

    private func isAutomatedProxyUserText(_ text: String) -> Bool {
        if text == AutomatedInterpretationPrompt.photoOnlyNewSession { return true }
        if text == AutomatedInterpretationPrompt.photoOnlyRefinement { return true }
        if text.hasPrefix("Re-estimate this meal based on current confirmed label:") { return true }
        return false
    }

    private func adjustedMergeConfidence(_ modelConfidence: Double, applyUserLedCap: Bool) -> Double {
        let clamped = min(max(modelConfidence, 0), 1)
        guard applyUserLedCap else { return clamped }
        return min(clamped, CheckInAIConfidence.userRefinementConfidenceCeiling)
    }

    private func buildMealRefinementPayload(rawUserMessageToExcludeFromPrior: String?) -> AIProxyMealRefinementPayload? {
        guard !session.interpretedMeals.isEmpty else { return nil }
        let meals = session.interpretedMeals.map { draft in
            AIProxyMealRefinementPayload.Meal(
                label: draft.label,
                timing: draft.timing.rawValue,
                calories: draft.calories,
                proteinGrams: Double(draft.proteinGrams),
                carbsGrams: Double(draft.carbsGrams),
                fatGrams: Double(draft.fatGrams),
                confidence: draft.confidence,
                isUserConfirmedLabel: draft.isUserConfirmed,
                items: draft.items.map { item in
                    AIProxyMealRefinementPayload.LineItem(
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
            )
        }
        let userLines = contextRows.filter { $0.kind == .user }.map(\.text)
        let latestTrimmed = rawUserMessageToExcludeFromPrior?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let priorUserTextLines: [String]
        if !latestTrimmed.isEmpty, userLines.last == latestTrimmed {
            priorUserTextLines = Array(userLines.dropLast())
        } else {
            priorUserTextLines = userLines
        }
        return AIProxyMealRefinementPayload(
            meals: meals,
            priorUserTextLines: priorUserTextLines,
            hasPhotoAttachment: session.selectedPhotoData != nil
        )
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
        explicitReestimateMealID: UUID?,
        applyUserLedRefinementConfidenceCap: Bool
    ) -> MealReconciliationResult {
        var drafts = existingDrafts
        var availableIDs = Set(existingDrafts.map(\.id))
        var reestimatedDraftIDs = Set<UUID>()
        var newDrafts: [CheckInMealDraft] = []

        if let explicitReestimateMealID,
           let targetIndex = drafts.firstIndex(where: { $0.id == explicitReestimateMealID }) {
            if aiMeals.count == 1, let aiMeal = aiMeals.first {
                let current = drafts[targetIndex]
                var merged = current
                merged.timing = aiMeal.timing
                merged.eatenAt = aiMeal.eatenAt
                merged.calories = aiMeal.calories
                merged.proteinGrams = aiMeal.proteinGrams
                merged.carbsGrams = aiMeal.carbsGrams
                merged.fatGrams = aiMeal.fatGrams
                merged.confidence = adjustedMergeConfidence(
                    aiMeal.confidence,
                    applyUserLedCap: applyUserLedRefinementConfidenceCap
                )
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
            merged.confidence = adjustedMergeConfidence(
                aiMeal.confidence,
                applyUserLedCap: applyUserLedRefinementConfidenceCap
            )
            merged.items = aiMeal.items
            merged.alternatives = current.isUserConfirmed ? [] : aiMeal.alternatives
            if !current.isUserConfirmed {
                merged.label = aiMeal.label
            }
            merged.originalAILabel = current.originalAILabel ?? aiMeal.originalAILabel
            drafts[targetIndex] = merged
            availableIDs.remove(explicitReestimateMealID)
            reestimatedDraftIDs.insert(explicitReestimateMealID)

            let matchedKey = normalizedMealKey(for: aiMeal)
            let remainingAIMeals = aiMeals.filter { normalizedMealKey(for: $0) != matchedKey }
            for extraAIMeal in remainingAIMeals {
                guard let matchedID = bestMatchExistingDraft(
                    for: extraAIMeal,
                    existingDrafts: existingDrafts,
                    availableIDs: availableIDs,
                    explicitReestimateMealID: nil
                ) else {
                    var extra = extraAIMeal
                    extra.confidence = adjustedMergeConfidence(
                        extraAIMeal.confidence,
                        applyUserLedCap: applyUserLedRefinementConfidenceCap
                    )
                    newDrafts.append(extra)
                    reestimatedDraftIDs.insert(extra.id)
                    continue
                }
                guard let idx = drafts.firstIndex(where: { $0.id == matchedID }) else { continue }
                let currentExtra = drafts[idx]
                var mergedExtra = currentExtra
                mergedExtra.timing = extraAIMeal.timing
                mergedExtra.eatenAt = extraAIMeal.eatenAt
                mergedExtra.calories = extraAIMeal.calories
                mergedExtra.proteinGrams = extraAIMeal.proteinGrams
                mergedExtra.carbsGrams = extraAIMeal.carbsGrams
                mergedExtra.fatGrams = extraAIMeal.fatGrams
                mergedExtra.confidence = adjustedMergeConfidence(
                    extraAIMeal.confidence,
                    applyUserLedCap: applyUserLedRefinementConfidenceCap
                )
                mergedExtra.items = extraAIMeal.items
                mergedExtra.alternatives = currentExtra.isUserConfirmed ? [] : extraAIMeal.alternatives
                if !currentExtra.isUserConfirmed {
                    mergedExtra.label = extraAIMeal.label
                }
                mergedExtra.originalAILabel = currentExtra.originalAILabel ?? extraAIMeal.originalAILabel
                drafts[idx] = mergedExtra
                availableIDs.remove(matchedID)
                reestimatedDraftIDs.insert(matchedID)
            }

            drafts.append(contentsOf: newDrafts)
            return MealReconciliationResult(drafts: drafts, reestimatedDraftIDs: reestimatedDraftIDs)
        }

        for aiMeal in aiMeals {
            guard let matchedID = bestMatchExistingDraft(
                for: aiMeal,
                existingDrafts: existingDrafts,
                availableIDs: availableIDs,
                explicitReestimateMealID: explicitReestimateMealID
            ) else {
                var added = aiMeal
                added.confidence = adjustedMergeConfidence(
                    aiMeal.confidence,
                    applyUserLedCap: applyUserLedRefinementConfidenceCap
                )
                newDrafts.append(added)
                reestimatedDraftIDs.insert(added.id)
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
            merged.confidence = adjustedMergeConfidence(
                aiMeal.confidence,
                applyUserLedCap: applyUserLedRefinementConfidenceCap
            )
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

    private func ensurePhotoContextRow() {
        let alreadyHasPhoto = contextRows.contains { $0.kind == .photo }
        guard !alreadyHasPhoto else { return }
        appendContextRow(kind: .photo, text: "Photo attached")
    }

    private func appendContextRow(kind: CheckInContextRowKind, text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if contextRows.last?.kind == kind, contextRows.last?.text == trimmed {
            return
        }
        contextRows.append(CheckInContextRow(id: UUID(), kind: kind, text: trimmed))
        if contextRows.count > maxStoredContextRows {
            contextRows = Array(contextRows.suffix(maxStoredContextRows))
        }
    }

    private func aiSummaryText(from interpretation: CheckInInterpretationResult) -> String {
        let notes = interpretation.uiNotes?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !notes.isEmpty {
            return Self.clipForContextSummary(notes)
        }
        return "Estimate updated."
    }

    private static let contextSummaryCharacterLimit = 160

    private static func clipForContextSummary(_ text: String) -> String {
        guard text.count > contextSummaryCharacterLimit else { return text }
        let end = text.index(text.startIndex, offsetBy: contextSummaryCharacterLimit - 1)
        let prefix = text[..<end].trimmingCharacters(in: .whitespacesAndNewlines)
        return prefix + "…"
    }

}

#if DEBUG
extension CheckInViewModel {
    fileprivate static func formatInterpretFailureForDebug(error: Error, requestDuration: TimeInterval) -> String {
        let swiftLine = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription

        if let ai = error as? AIServiceError {
            switch ai {
            case .invalidURL:
                return debugErrorBlock(
                    statusLine: "—",
                    backendLine: "—",
                    bodyLine: "—",
                    swiftLine: swiftLine,
                    requestDuration: requestDuration
                )
            case .invalidRequestPayload:
                return debugErrorBlock(
                    statusLine: "—",
                    backendLine: "—",
                    bodyLine: "—",
                    swiftLine: swiftLine,
                    requestDuration: requestDuration
                )
            case .transport:
                return debugErrorBlock(
                    statusLine: "—",
                    backendLine: "—",
                    bodyLine: "—",
                    swiftLine: swiftLine,
                    requestDuration: requestDuration
                )
            case .unexpectedStatusCode(let code, let body):
                let backend = extractBackendErrorCode(fromJSONBody: body) ?? "—"
                let bodyDisplay = body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "—" : body
                return debugErrorBlock(
                    statusLine: "\(code)",
                    backendLine: backend,
                    bodyLine: bodyDisplay,
                    swiftLine: swiftLine,
                    requestDuration: requestDuration
                )
            case .malformedResponse(let preview):
                let raw = preview?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                let backend = raw.isEmpty ? "—" : (extractBackendErrorCode(fromJSONBody: raw) ?? "—")
                let bodyDisplay = raw.isEmpty ? "—" : raw
                return debugErrorBlock(
                    statusLine: "200 (decode failed)",
                    backendLine: backend,
                    bodyLine: bodyDisplay,
                    swiftLine: swiftLine,
                    requestDuration: requestDuration
                )
            }
        }

        return debugErrorBlock(
            statusLine: "—",
            backendLine: "—",
            bodyLine: "—",
            swiftLine: swiftLine,
            requestDuration: requestDuration
        )
    }

    fileprivate static func extractBackendErrorCode(fromJSONBody body: String) -> String? {
        guard let data = body.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        if let err = obj["error"] as? String { return err }
        if let code = obj["code"] as? String { return code }
        if let code = obj["code"] as? Int { return String(code) }
        return nil
    }

    private static func debugErrorBlock(
        statusLine: String,
        backendLine: String,
        bodyLine: String,
        swiftLine: String,
        requestDuration: TimeInterval
    ) -> String {
        let durationText = String(format: "%.2fs", requestDuration)
        return [
            "Status: \(statusLine)",
            "Backend: \(backendLine)",
            "Body: \(bodyLine)",
            "",
            "Swift error:",
            swiftLine,
            "",
            "Duration: \(durationText)",
        ].joined(separator: "\n")
    }
}
#endif
