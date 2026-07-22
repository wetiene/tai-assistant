import Foundation

enum GymWorkoutStartError: Error, Equatable {
    case activeSessionInProgress(GymActiveSession)
}

/// Gym capability: camera-first set logging with transient photo analysis only.
@MainActor
@Observable
final class GymCapabilityController {
    private let workoutRepository: WorkoutRepository
    private let aiService: AIService
    private let ownerID: String

    private(set) var phase: GymCapabilityID.Phase = .idle
    private(set) var session: GymActiveSession?
    private(set) var hasActiveStrengthSession = false
    private(set) var activeStrengthSessionID: UUID?
    private(set) var pendingSetDraft: GymSetDraft?
    private(set) var lastError: String?
    private var inFlightSaveDraftIDs: Set<UUID> = []
    private var savedDraftIDs: Set<UUID> = []

    /// Transient analysis input — never persisted.
    private var transientPhotoJPEG: Data?

    var isBusy: Bool {
        phase == .interpreting || phase == .savingSet
    }

    var hasActiveSession: Bool {
        session?.status == .inProgress || hasActiveStrengthSession
    }

    init(workoutRepository: WorkoutRepository, aiService: AIService, ownerID: String) {
        self.workoutRepository = workoutRepository
        self.aiService = aiService
        self.ownerID = ownerID
    }

    func clearError() {
        lastError = nil
    }

    func releaseTransientPhoto() {
        transientPhotoJPEG = nil
    }

    // MARK: - Session lifecycle

    func activeSessionSnapshot() async throws -> GymActiveSession? {
        if let persisted = try await workoutRepository.fetchInProgressSession(ownerID: ownerID) {
            if StrengthSessionPersistence.decodeStrengthEnvelope(from: persisted.activeSessionJSON) != nil {
                hasActiveStrengthSession = true
                activeStrengthSessionID = persisted.id
                session = nil
                phase = .idle
                return nil
            }
            if let restored = decodeActiveSession(from: persisted) {
                hasActiveStrengthSession = false
                activeStrengthSessionID = nil
                session = restored
                phase = .active
                return restored
            }
        }
        hasActiveStrengthSession = false
        activeStrengthSessionID = nil
        if let session, session.status == .inProgress {
            return session
        }
        return nil
    }

    func startWorkout(plan: GymResolvablePlan, replacingExisting: Bool = false) async throws -> GymActiveSession {
        clearError()
        if !replacingExisting {
            if let existing = try await workoutRepository.fetchInProgressSession(ownerID: ownerID) {
                if let legacy = decodeActiveSession(from: existing) {
                    throw GymWorkoutStartError.activeSessionInProgress(legacy)
                }
                if StrengthSessionPersistence.decodeStrengthEnvelope(from: existing.activeSessionJSON) != nil {
                    throw GymWorkoutStartError.activeSessionInProgress(
                        GymActiveSession(
                            sessionID: existing.id,
                            planReference: GymPlanReference.decode(storageKey: existing.templateID) ?? .starter(.upperBody),
                            title: existing.title,
                            exercises: plan.exercises,
                            prescription: plan.prescription,
                            currentExerciseIndex: 0,
                            currentSetNumber: 1,
                            startedAt: existing.startedAt,
                            status: .inProgress
                        )
                    )
                }
            }
            if let existing = try await activeSessionSnapshot() {
                throw GymWorkoutStartError.activeSessionInProgress(existing)
            }
        }

        if replacingExisting {
            if let existing = try await workoutRepository.fetchInProgressSession(ownerID: ownerID) {
                try await workoutRepository.abandonSession(id: existing.id)
            }
            session = nil
            hasActiveStrengthSession = false
            activeStrengthSessionID = nil
            phase = .idle
        }

        let active = GymActiveSession(
            sessionID: UUID(),
            planReference: plan.reference,
            title: plan.title,
            exercises: plan.exercises,
            prescription: plan.prescription,
            currentExerciseIndex: 0,
            currentSetNumber: 1,
            startedAt: .now,
            status: .inProgress
        )

        let log = WorkoutSessionLog(
            id: active.sessionID,
            ownerID: ownerID,
            templateID: plan.reference.storageKey,
            title: plan.title,
            startedAt: active.startedAt,
            statusRaw: GymWorkoutSessionStatus.inProgress.rawValue,
            activeSessionJSON: encodeActiveSession(active)
        )
        try await workoutRepository.createSession(log)

        session = active
        phase = .active
        return active
    }

    func startWorkout(templateID: GymProgramTemplateID) async throws -> GymActiveSession {
        try await startWorkout(plan: GymProgramTemplateLibrary.resolvableStarter(templateID))
    }

    func restoreSession(_ active: GymActiveSession) {
        session = active
        phase = active.status == .completed ? .completed : .active
    }

    func restoreFromConversation(_ conversation: ActiveConversation) async {
        if let persisted = try? await workoutRepository.fetchInProgressSession(ownerID: ownerID),
           StrengthSessionPersistence.decodeStrengthEnvelope(from: persisted.activeSessionJSON) != nil {
            hasActiveStrengthSession = true
            activeStrengthSessionID = persisted.id
            session = nil
            phase = .idle
            return
        }

        if let active = GymCapabilityActivityCodec.activeSession(from: conversation.activity) {
            hasActiveStrengthSession = false
            activeStrengthSessionID = nil
            session = active
            phase = active.status == .completed ? .completed : .active
            return
        }

        if let persisted = try? await workoutRepository.fetchInProgressSession(ownerID: ownerID),
           let active = decodeActiveSession(from: persisted) {
            hasActiveStrengthSession = false
            activeStrengthSessionID = nil
            session = active
            phase = .active
        }
    }

    func makeWorkoutPlanCardPayload() -> GymWorkoutPlanCardPayload? {
        guard let session else { return nil }
        return Self.planCardPayload(from: session)
    }

    // MARK: - Photo interpretation (transient)

    func attachTransientPhoto(_ jpeg: Data) {
        transientPhotoJPEG = jpeg
    }

    func interpretCurrentSet(
        photoJPEG: Data,
        localeIdentifier: String,
        weightUnitPreference: String
    ) async -> GymInterpretationOutcome {
        clearError()
        releaseTransientPhoto()
        attachTransientPhoto(photoJPEG)

        guard var active = session, let exercise = active.currentExercise else {
            releaseTransientPhoto()
            return .failure("No active workout set to log.")
        }

        phase = .interpreting
        defer {
            releaseTransientPhoto()
            if phase == .interpreting {
                phase = .active
            }
        }

        let base64 = photoJPEG.base64EncodedString()
        let allowedExerciseIDs = Set(active.exercises.flatMap(\.candidateStableIDs))
        let request = AIInterpretGymPhotoRequest(
            image: AIInterpretMealImageInput(base64Data: base64, mimeType: "image/jpeg", uploadReference: nil),
            context: AIInterpretGymPhotoContext(
                localeIdentifier: localeIdentifier,
                weightUnitPreference: weightUnitPreference,
                plannedWorkout: AIProxyGymPlannedWorkoutContext(
                    templateID: active.planReference.storageKey,
                    title: active.title,
                    exercises: active.exercises.map {
                        AIProxyGymExerciseCandidateContext(
                            exerciseID: $0.reference.stableID,
                            displayName: $0.displayName,
                            isOptional: $0.isOptional
                        )
                    }
                ),
                expectedExerciseID: exercise.reference.stableID,
                allowedExerciseCandidates: exercise.candidateStableIDs.map { stableID in
                    AIProxyGymExerciseCandidateContext(
                        exerciseID: stableID,
                        displayName: GymExerciseCatalog.displayName(for: stableID),
                        isOptional: false
                    )
                }
            )
        )

        do {
            let response = try await aiService.interpretGymPhoto(request: request)
            let interpretation = mapInterpretation(response, allowedExerciseIDs: allowedExerciseIDs)
            let allowedOptions = GymSetCardValidation.templateExerciseOptions(for: active)
            let topCandidate = interpretation.exerciseCandidates.first
            let selectedID: String
            let selectedName: String
            if let top = topCandidate, allowedOptions.contains(where: { $0.exerciseID == top.exerciseID }) {
                selectedID = top.exerciseID
                selectedName = top.displayName
            } else {
                selectedID = ""
                selectedName = ""
            }

            let draft = GymSetDraft(
                draftID: UUID(),
                sessionID: active.sessionID,
                plannedExerciseID: exercise.reference.stableID,
                plannedExerciseName: exercise.displayName,
                setNumber: active.currentSetNumber,
                selectedExerciseID: selectedID,
                selectedExerciseName: selectedName,
                weightValue: interpretation.detectedWeight?.value,
                weightUnit: interpretation.detectedWeight?.unit ?? weightUnitPreference,
                repetitions: nil,
                interpretation: interpretation
            )
            pendingSetDraft = draft
            phase = .reviewingSet
            return .success(GymInterpretationOutcome.Success(
                draft: draft,
                assistantNote: assistantNote(for: interpretation)
            ))
        } catch {
            let message = "I couldn’t read that setup. Try another angle with the weight label visible."
            lastError = message
            return .failure(message)
        }
    }

    func updatePendingDraft(_ draft: GymSetDraft) {
        pendingSetDraft = draft
    }

    func clearPendingSetDraft() {
        pendingSetDraft = nil
    }

    func confirmAndSaveSet(payload: GymSetConfirmationCardPayload) async -> Result<WorkoutSetLog, GymCapabilitySaveError> {
        if savedDraftIDs.contains(payload.draftID) || payload.isSaved {
            return .failure(.alreadySaved)
        }
        guard !inFlightSaveDraftIDs.contains(payload.draftID) else {
            return .failure(.alreadySaved)
        }
        guard payload.canSaveSet else {
            return .failure(.validationFailed("Select exercise, enter weight, and enter repetitions before saving."))
        }
        guard var active = session, active.sessionID == payload.sessionID else {
            return .failure(.noActiveSession)
        }
        guard let reps = payload.repetitions, let weight = payload.weightValue else {
            return .failure(.validationFailed("Enter repetitions and confirm weight before saving."))
        }

        inFlightSaveDraftIDs.insert(payload.draftID)
        phase = .savingSet
        defer {
            inFlightSaveDraftIDs.remove(payload.draftID)
            if phase == .savingSet {
                phase = .active
            }
        }

        let setLog = WorkoutSetLog(
            exerciseID: payload.selectedExerciseID,
            exerciseName: payload.selectedExerciseName,
            setNumber: payload.setNumber,
            weightValue: weight,
            weightUnit: payload.weightUnit,
            repetitions: reps
        )

        do {
            try await workoutRepository.appendSet(setLog, to: active.sessionID)
            active.advanceAfterSavedSet()
            session = active
            savedDraftIDs.insert(payload.draftID)
            pendingSetDraft = nil

            let persisted = WorkoutSessionLog(
                id: active.sessionID,
                ownerID: ownerID,
                templateID: active.planReference.storageKey,
                title: active.title,
                startedAt: active.startedAt,
                statusRaw: active.status.rawValue,
                activeSessionJSON: active.status == .inProgress ? encodeActiveSession(active) : nil
            )
            try await workoutRepository.updateSession(persisted)

            if active.status == .completed {
                try await workoutRepository.completeSession(id: active.sessionID, completedAt: .now, debriefJSON: nil)
                phase = .completed
            } else {
                phase = .active
            }
            return .success(setLog)
        } catch {
            lastError = "Could not save this set. Please try again."
            return .failure(.persistenceFailed)
        }
    }

    func finishWorkoutExplicitly() async -> Result<WorkoutSessionLog, GymCapabilitySaveError> {
        guard var active = session else {
            return .failure(.noActiveSession)
        }
        active.status = .completed
        session = active
        phase = .completed
        do {
            try await workoutRepository.completeSession(id: active.sessionID, completedAt: .now, debriefJSON: nil)
            guard let log = try await workoutRepository.fetchSessions(
                ownerID: ownerID,
                from: active.startedAt.addingTimeInterval(-1),
                to: .now.addingTimeInterval(1)
            ).first(where: { $0.id == active.sessionID }) else {
                return .failure(.persistenceFailed)
            }
            return .success(log)
        } catch {
            lastError = "Could not finish the workout."
            return .failure(.persistenceFailed)
        }
    }

    func resetAfterCompletion() {
        session = nil
        pendingSetDraft = nil
        phase = .idle
        releaseTransientPhoto()
    }

    func discardActiveWorkout() async throws {
        guard let active = try await activeSessionSnapshot() else { return }
        try await workoutRepository.abandonSession(id: active.sessionID)
        resetAfterCompletion()
    }

    // MARK: - Helpers

    static func planCardPayload(from session: GymActiveSession) -> GymWorkoutPlanCardPayload {
        GymWorkoutPlanCardPayload(
            sessionID: session.sessionID,
            title: session.title,
            exercises: session.exercises.map { exercise in
                let index = exercise.orderIndex
                let completedSets: Int
                if index < session.currentExerciseIndex {
                    completedSets = session.prescription.workingSetsPerExercise
                } else if index == session.currentExerciseIndex {
                    completedSets = max(0, session.currentSetNumber - 1)
                } else {
                    completedSets = 0
                }
                return GymPlanExerciseRow(
                    exerciseID: exercise.reference.stableID,
                    displayName: exercise.displayName,
                    isOptional: exercise.isOptional,
                    isCurrent: index == session.currentExerciseIndex,
                    completedSets: completedSets,
                    workingSets: session.prescription.workingSetsPerExercise
                )
            },
            currentExerciseIndex: session.currentExerciseIndex,
            currentSetNumber: session.currentSetNumber,
            workingSetsPerExercise: session.prescription.workingSetsPerExercise,
            repRangeLabel: session.prescription.repRangeLabel,
            coachingNote: session.prescription.coachingNote,
            isActive: session.status == .inProgress
        )
    }

    static func setCardPayload(from draft: GymSetDraft, session: GymActiveSession) -> GymSetConfirmationCardPayload {
        GymSetConfirmationCardPayload(
            draftID: draft.draftID,
            sessionID: draft.sessionID,
            plannedExerciseID: draft.plannedExerciseID,
            plannedExerciseName: draft.plannedExerciseName,
            setNumber: draft.setNumber,
            selectedExerciseID: draft.selectedExerciseID,
            selectedExerciseName: draft.selectedExerciseName,
            weightValue: draft.weightValue,
            weightUnit: draft.weightUnit,
            repetitions: draft.repetitions,
            interpretation: draft.interpretation,
            templateExerciseOptions: GymSetCardValidation.templateExerciseOptions(for: session),
            isSaved: false
        )
    }

    private func mapInterpretation(
        _ response: AIInterpretGymPhotoResponse,
        allowedExerciseIDs: Set<String>
    ) -> GymPhotoInterpretationSnapshot {
        GymPhotoInterpretationMapper.map(response, allowedExerciseIDs: allowedExerciseIDs)
    }

    private func mapInterpretation(_ response: AIInterpretGymPhotoResponse) -> GymPhotoInterpretationSnapshot {
        mapInterpretation(response, allowedExerciseIDs: Set(GymExerciseID.allCases.map(\.rawValue)))
    }

    private func assistantNote(for interpretation: GymPhotoInterpretationSnapshot) -> String? {
        var parts: [String] = ["Review the fields below, then tap Save Set when ready."]
        if !interpretation.limitations.isEmpty {
            parts.append(interpretation.limitations.joined(separator: " "))
        }
        return parts.joined(separator: " ")
    }

    private func encodeActiveSession(_ session: GymActiveSession) -> Data? {
        try? JSONEncoder().encode(session)
    }

    private func decodeActiveSession(from log: WorkoutSessionLog) -> GymActiveSession? {
        guard let data = log.activeSessionJSON else { return nil }
        return try? JSONDecoder().decode(GymActiveSession.self, from: data)
    }
}
