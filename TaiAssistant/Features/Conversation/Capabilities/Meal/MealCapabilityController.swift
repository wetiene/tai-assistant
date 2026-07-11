import Foundation

enum MealCapabilitySaveError: Error, Equatable {
    case nothingToLog
    case persistenceFailed
}

/// Meal capability: interprets via existing Check In AI path; persists only via MealRepository after User Decision.
@MainActor
@Observable
final class MealCapabilityController {
    private let mealRepository: MealRepository
    private let ownerID: String

    /// Reuses Check In interpretation + merge/refinement behaviour.
    private let engine: CheckInViewModel

    private(set) var lastError: String?
    private(set) var phase: MealCapabilityID.Phase = .idle

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
    func interpret(userText: String, photoJPEG: Data?) async -> MealInterpretationOutcome {
        clearError()
        phase = .interpreting
        if let photoJPEG {
            engine.session.selectedPhotoData = photoJPEG
        }
        engine.session.userInput = userText
        await engine.onUpdateMealTapped()

        if let error = engine.errorMessage {
            lastError = error
            phase = currentDrafts.isEmpty ? .collecting : .reviewing
            return .failure(error)
        }

        let drafts = currentDrafts
        guard !drafts.isEmpty else {
            let message = "I couldn’t estimate that meal. Try another photo or a bit more detail."
            lastError = message
            phase = .collecting
            return .failure(message)
        }

        phase = .reviewing
        let notes = engine.session.interpretationNotes?.trimmingCharacters(in: .whitespacesAndNewlines)
        return .success(
            MealInterpretationOutcome.Success(
                drafts: drafts,
                assistantNote: (notes?.isEmpty == false) ? notes : defaultAssistantNote(for: drafts)
            )
        )
    }

    /// Persist confirmed drafts through the same MealLog → createMealLog path as Check In.
    func confirmAndSave() async -> Result<[CheckInMealDraft], MealCapabilitySaveError> {
        let drafts = currentDrafts
        guard !drafts.isEmpty else {
            return .failure(.nothingToLog)
        }
        phase = .saving
        clearError()
        do {
            try await persistDrafts(drafts)
            phase = .completed
            engine.session = CheckInSessionDraft()
            engine.contextRows = []
            return .success(drafts)
        } catch {
            phase = .readyToLog
            let message = "Could not save this meal. Please try again."
            lastError = message
            return .failure(.persistenceFailed)
        }
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
    }

    private func persistDrafts(_ drafts: [CheckInMealDraft]) async throws {
        for draft in drafts {
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
    }

    case success(Success)
    case failure(String)
}
