import Foundation

enum MealCapabilitySaveError: Error, Equatable {
    case nothingToLog
    case persistenceFailed
    case validationFailed(String)
    case alreadyLogged
    case draftNotFound
    case draftMismatch
}

/// Meal capability: interprets via existing Check In AI path; persists only via MealRepository after User Decision.
/// Concurrent drafts are addressed by `draftID` — never by a single global “current meal.”
@MainActor
@Observable
final class MealCapabilityController {
    private let mealRepository: MealRepository
    private let ownerID: String

    /// Reuses Check In interpretation + merge/refinement behaviour.
    private let engine: CheckInViewModel

    private(set) var lastError: String?
    private(set) var phase: MealCapabilityID.Phase = .idle
    /// Drafts that have already produced a MealLog Artifact this session.
    private(set) var loggedDraftIDs: Set<UUID> = []
    /// In-flight log attempts (idempotent double-tap guard).
    private var inFlightDraftIDs: Set<UUID> = []

    var isBusy: Bool { engine.isInterpreting || phase == .saving || phase == .interpreting }

    init(
        mealRepository: MealRepository,
        ownerID: String,
        interpreter: any CheckInInterpreting
    ) {
        self.mealRepository = mealRepository
        self.ownerID = ownerID
        self.engine = CheckInViewModel(
            mealRepository: mealRepository,
            ownerID: ownerID,
            interpreter: interpreter
        )
    }

    var currentDrafts: [CheckInMealDraft] {
        engine.session.interpretedMeals
    }

    func clearError() {
        lastError = nil
        engine.errorMessage = nil
    }

    func beginCollecting() {
        phase = .collecting
    }

    func attachPhoto(_ jpeg: Data) {
        engine.session.selectedPhotoData = jpeg
        phase = .collecting
    }

    /// Run AI interpretation using the existing Check In interpreter (unchanged backend).
    /// - Parameter targetDraftID: When set (targeted meal refinement), only that draft is re-estimated.
    /// - Parameter captureNutritionDay: Nutrition day stamped onto newly created drafts only.
    func interpret(
        userText: String,
        photoJPEG: Data?,
        targetDraftID: UUID? = nil,
        captureNutritionDay: NutritionDay? = nil
    ) async -> MealInterpretationOutcome {
        clearError()
        phase = .interpreting
        let captureDay = captureNutritionDay ?? .today()
        let priorNutritionDays = Dictionary(uniqueKeysWithValues: currentDrafts.map { ($0.id, $0.nutritionDay) })
        if let photoJPEG {
            engine.session.selectedPhotoData = photoJPEG
        }
        engine.session.userInput = userText
        await engine.interpretFromConversation(
            userText: userText,
            photoData: photoJPEG,
            explicitReestimateMealID: targetDraftID
        )

        if let error = engine.errorMessage {
            lastError = error
            phase = currentDrafts.isEmpty ? .collecting : .reviewing
            if let imageFailure = engine.lastImageInterpretationFailure {
                return .imageFailure(imageFailure)
            }
            return .failure(error)
        }

        let drafts = stampAndNormalizeDrafts(
            currentDrafts,
            priorNutritionDays: priorNutritionDays,
            captureDay: captureDay
        )
        engine.session.interpretedMeals = drafts
        guard !drafts.isEmpty else {
            let message = "I couldn’t estimate that meal. Try another photo or a bit more detail."
            lastError = message
            phase = .collecting
            return .failure(message)
        }

        phase = .reviewing
        let notes = engine.session.interpretationNotes?.trimmingCharacters(in: .whitespacesAndNewlines)
        let successDrafts: [CheckInMealDraft]
        if let targetDraftID {
            successDrafts = drafts.filter { $0.id == targetDraftID }
            if successDrafts.isEmpty {
                let message = "I couldn’t update that meal estimate. Try again or change another detail."
                lastError = message
                return .failure(message)
            }
        } else {
            successDrafts = drafts
        }
        return .success(
            MealInterpretationOutcome.Success(
                drafts: successDrafts,
                assistantNote: (notes?.isEmpty == false) ? notes : defaultAssistantNote(for: successDrafts),
                imageClassification: engine.lastImageClassification
            )
        )
    }

    /// Persist exactly one draft identified by `draftID`, using the card payload as the User Decision source.
    func confirmAndSaveDraft(
        draftID: UUID,
        payload: MealEstimateCardPayload
    ) async -> Result<CheckInMealDraft, MealCapabilitySaveError> {
        if loggedDraftIDs.contains(draftID) || payload.isLogged {
            return .failure(.alreadyLogged)
        }
        guard !inFlightDraftIDs.contains(draftID) else {
            return .failure(.alreadyLogged)
        }
        guard payload.draft.id == draftID else {
            return .failure(.draftMismatch)
        }
        guard payload.refinementAccepted else {
            return .failure(.validationFailed("Confirm this estimate looks right before logging it."))
        }

        let draft = normalizeDraft(payload.draft.asCheckInDraft())
        if let validationError = Self.validateDraftForPersistence(draft) {
            lastError = validationError
            return .failure(.validationFailed(validationError))
        }

        inFlightDraftIDs.insert(draftID)
        phase = .saving
        clearError()
        defer { inFlightDraftIDs.remove(draftID) }

        do {
            try await persistSingleDraft(draft)
            loggedDraftIDs.insert(draftID)
            engine.session.interpretedMeals.removeAll { $0.id == draftID }
            refreshPhaseAfterDraftChange()
            return .success(draft)
        } catch {
            refreshPhaseAfterDraftChange()
            let message = "Could not save this meal. Please try again."
            lastError = message
            return .failure(.persistenceFailed)
        }
    }

    /// - Warning: Legacy multi-draft save. Prefer `confirmAndSaveDraft`. Kept for older call sites/tests.
    func confirmAndSave() async -> Result<[CheckInMealDraft], MealCapabilitySaveError> {
        let drafts = currentDrafts
        guard !drafts.isEmpty else {
            return .failure(.nothingToLog)
        }
        var saved: [CheckInMealDraft] = []
        for draft in drafts {
            let payload = MealEstimateCardPayload(
                draft: MealEstimateSnapshot(draft: draft),
                refinementAccepted: true,
                isLogged: false
            )
            switch await confirmAndSaveDraft(draftID: draft.id, payload: payload) {
            case .success(let one):
                saved.append(one)
            case .failure(let error):
                if saved.isEmpty {
                    return .failure(error)
                }
                return .success(saved)
            }
        }
        phase = .completed
        return .success(saved)
    }

    func markReadyToLog() {
        guard !currentDrafts.isEmpty else { return }
        phase = .readyToLog
    }

    func markReviewing() {
        guard !currentDrafts.isEmpty else {
            phase = .collecting
            return
        }
        phase = .reviewing
    }

    func resetAfterCompletion() {
        phase = .idle
        engine.session = CheckInSessionDraft()
        engine.contextRows = []
        // Keep loggedDraftIDs so restored cards marked logged stay idempotent within the process.
    }

    /// Rebuild meal capability drafts from interactive estimate cards after Conversation restore.
    func restoreFromConversation(_ conversation: ActiveConversation) {
        let payloads = ConversationRestoration.interactiveUnloggedMealPayloads(in: conversation)
        loggedDraftIDs = Set(
            conversation.messages.compactMap { message -> UUID? in
                guard let card = message.card,
                      card.typeID == MealCapabilityID.estimateCardType,
                      let payload = MealCardCodec.decode(card.payload),
                      payload.isLogged
                else { return nil }
                return payload.draft.id
            }
        )
        guard !payloads.isEmpty else {
            engine.session.interpretedMeals = []
            if case .capability(let capabilityID, let phaseID, _) = conversation.activity,
               capabilityID == MealCapabilityID.capability,
               phaseID == MealCapabilityID.Phase.collecting.rawValue
            {
                phase = .collecting
            } else {
                phase = .idle
            }
            return
        }
        engine.session.interpretedMeals = payloads.map { $0.draft.asCheckInDraft() }
        if payloads.contains(where: \.refinementAccepted) {
            phase = .readyToLog
        } else {
            phase = .reviewing
        }
    }

    /// Sync session drafts to remaining interactive card payloads after a single-draft log.
    func syncUnloggedDrafts(from payloads: [MealEstimateCardPayload]) {
        engine.session.interpretedMeals = payloads
            .filter { !$0.isLogged && !loggedDraftIDs.contains($0.draft.id) }
            .map { $0.draft.asCheckInDraft() }
        refreshPhaseAfterDraftChange()
    }

    /// Updates the nutrition day for a single in-session draft. Returns nil when the draft is not loaded.
    func applyLoggingDayChange(draftID: UUID, to day: NutritionDay, now: Date = .now) -> CheckInMealDraft? {
        guard let index = engine.session.interpretedMeals.firstIndex(where: { $0.id == draftID }) else {
            return nil
        }
        let updated = Self.draft(
            engine.session.interpretedMeals[index],
            retargetedTo: day,
            now: now
        )
        engine.session.interpretedMeals[index] = updated
        return updated
    }

    static func draft(
        _ draft: CheckInMealDraft,
        retargetedTo day: NutritionDay,
        now: Date = .now
    ) -> CheckInMealDraft {
        CheckInMealDraft(
            id: draft.id,
            label: draft.label,
            timing: draft.timing,
            eatenAt: day.resolveOccurrenceTimestamp(aiGuess: draft.eatenAt, timing: draft.timing, now: now),
            nutritionDay: day,
            calories: draft.calories,
            proteinGrams: draft.proteinGrams,
            carbsGrams: draft.carbsGrams,
            fatGrams: draft.fatGrams,
            confidence: draft.confidence,
            alternatives: draft.alternatives,
            items: draft.items,
            isUserConfirmed: draft.isUserConfirmed,
            macrosNeedReview: draft.macrosNeedReview,
            originalAILabel: draft.originalAILabel,
            lastMacroEstimateBasis: draft.lastMacroEstimateBasis
        )
    }

    static func validateDraftForPersistence(_ draft: CheckInMealDraft) -> String? {
        let name = draft.label.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else {
            return "This meal is missing a name, so it can’t be logged yet."
        }
        guard draft.calories > 0 else {
            return "This meal estimate has no calories, so it can’t be logged."
        }
        guard !draft.items.isEmpty else {
            return "This meal estimate is missing food details, so it can’t be logged."
        }
        let itemCalories = draft.items.reduce(0) { $0 + $1.calories }
        guard itemCalories > 0 else {
            return "This meal estimate has incomplete nutrition details, so it can’t be logged."
        }
        // Reject empty/default-shaped payloads that would show as 0 kcal on Home.
        let looksDefaultEmpty = draft.items.allSatisfy {
            $0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && $0.calories == 0
        }
        if looksDefaultEmpty {
            return "This meal estimate looks incomplete, so it can’t be logged."
        }
        return nil
    }

    // MARK: - Private

    private func persistSingleDraft(_ draft: CheckInMealDraft) async throws {
        let eatenAt = draft.nutritionDay.resolveOccurrenceTimestamp(
            aiGuess: draft.eatenAt,
            timing: draft.timing
        )
        let mealLog = MealLog(
            ownerID: ownerID,
            eatenAt: eatenAt,
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

    private func normalizeDraft(_ draft: CheckInMealDraft, now: Date = .now) -> CheckInMealDraft {
        let eatenAt = draft.nutritionDay.resolveOccurrenceTimestamp(
            aiGuess: draft.eatenAt,
            timing: draft.timing,
            now: now
        )
        guard eatenAt != draft.eatenAt else { return draft }
        return CheckInMealDraft(
            id: draft.id,
            label: draft.label,
            timing: draft.timing,
            eatenAt: eatenAt,
            nutritionDay: draft.nutritionDay,
            calories: draft.calories,
            proteinGrams: draft.proteinGrams,
            carbsGrams: draft.carbsGrams,
            fatGrams: draft.fatGrams,
            confidence: draft.confidence,
            alternatives: draft.alternatives,
            items: draft.items,
            isUserConfirmed: draft.isUserConfirmed,
            macrosNeedReview: draft.macrosNeedReview,
            originalAILabel: draft.originalAILabel,
            lastMacroEstimateBasis: draft.lastMacroEstimateBasis
        )
    }

    private func stampAndNormalizeDrafts(
        _ drafts: [CheckInMealDraft],
        priorNutritionDays: [UUID: NutritionDay],
        captureDay: NutritionDay,
        now: Date = .now
    ) -> [CheckInMealDraft] {
        drafts.map { draft in
            let day = priorNutritionDays[draft.id] ?? captureDay
            let resolved = day.resolveOccurrenceTimestamp(
                aiGuess: draft.eatenAt,
                timing: draft.timing,
                now: now
            )
            return CheckInMealDraft(
                id: draft.id,
                label: draft.label,
                timing: draft.timing,
                eatenAt: resolved,
                nutritionDay: day,
                calories: draft.calories,
                proteinGrams: draft.proteinGrams,
                carbsGrams: draft.carbsGrams,
                fatGrams: draft.fatGrams,
                confidence: draft.confidence,
                alternatives: draft.alternatives,
                items: draft.items,
                isUserConfirmed: draft.isUserConfirmed,
                macrosNeedReview: draft.macrosNeedReview,
                originalAILabel: draft.originalAILabel,
                lastMacroEstimateBasis: draft.lastMacroEstimateBasis
            )
        }
    }

    private func refreshPhaseAfterDraftChange() {
        if engine.session.interpretedMeals.isEmpty {
            phase = .idle
        } else {
            phase = .readyToLog
        }
    }

    private func defaultAssistantNote(for drafts: [CheckInMealDraft]) -> String {
        if drafts.count == 1, let draft = drafts.first {
            let confidencePct = Int((draft.confidence * 100).rounded())
            return "Here’s my estimate for \(draft.label) — about \(draft.calories) kcal (\(confidencePct)% confidence). Does this look right?"
        }
        return "Here’s what I estimated. Does this look right, or should we change something?"
    }
}

enum MealInterpretationOutcome {
    struct Success {
        var drafts: [CheckInMealDraft]
        var assistantNote: String?
        var imageClassification: PersistedImageClassification?
    }

    case success(Success)
    case failure(String)
    case imageFailure(ImageInterpretationFailure)
}
