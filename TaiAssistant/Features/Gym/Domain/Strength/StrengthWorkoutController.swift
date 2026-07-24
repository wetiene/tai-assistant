import Foundation

enum StrengthWorkoutStartError: Error, Equatable {
    case activeSessionInProgress(sessionID: UUID)
}

@MainActor
@Observable
final class StrengthWorkoutController {
    private let workoutRepository: WorkoutRepository
    private let ownerID: String

    private(set) var session: StrengthWorkoutSession?
    private(set) var debrief: StrengthWorkoutDebrief?
    private(set) var lastError: String?

    init(workoutRepository: WorkoutRepository, ownerID: String) {
        self.workoutRepository = workoutRepository
        self.ownerID = ownerID
    }

    func clearError() {
        lastError = nil
    }

    func loadSession(_ active: StrengthWorkoutSession) {
        session = active
    }

    func reportError(_ message: String) {
        lastError = message
    }

    func userFacingMessage(for error: Error) -> String {
        if error is StrengthSessionPersistenceError {
            return "Could not save workout progress. Please try again."
        }
        if let repoError = error as? WorkoutRepositoryError {
            switch repoError {
            case .sessionNotFound, .sessionAlreadyExists, .activeSessionAlreadyExists, .nothingToSave, .invalidSet:
                return "Could not save workout progress. Please try again."
            }
        }
        return "Something went wrong. Please try again."
    }

    // MARK: - Restore

    func restoreInProgressSession() async throws -> StrengthWorkoutSession? {
        guard let log = try await workoutRepository.fetchInProgressSession(ownerID: ownerID),
              let restored = StrengthSessionPersistence.decodeStrength(from: log.activeSessionJSON)
        else {
            session = nil
            return nil
        }
        session = restored
        return restored
    }

    // MARK: - Pre-flight

    func prepareSession(
        plan: GymResolvablePlan,
        proposals: [StrengthProgressionProposal],
        acceptedProposals: [String: StrengthAcceptedProposal],
        historySessions: [WorkoutSessionLog],
        weightUnit: String = "kg",
        origin: StrengthWorkoutEntrySource = .home,
        preFlightCompleted: Bool = false
    ) -> StrengthWorkoutSession {
        StrengthSessionBuilder.makeSession(
            plan: plan,
            proposals: proposals,
            acceptedProposals: acceptedProposals,
            historySessions: historySessions,
            weightUnit: weightUnit,
            origin: origin,
            preFlightCompleted: preFlightCompleted
        )
    }

    // MARK: - Start

    func startSession(
        _ prepared: StrengthWorkoutSession,
        replacingExisting: Bool = false,
        activateFirstExercise: Bool = true
    ) async throws {
        clearError()
        if !replacingExisting, let existing = try await workoutRepository.fetchInProgressSession(ownerID: ownerID) {
            throw StrengthWorkoutStartError.activeSessionInProgress(sessionID: existing.id)
        }
        if replacingExisting, let existing = try await workoutRepository.fetchInProgressSession(ownerID: ownerID) {
            try await workoutRepository.abandonSession(id: existing.id)
        }

        var active = prepared
        if activateFirstExercise {
            self.activateFirstExercise(&active)
        }
        try StrengthSessionInvariants.validate(active)

        let log = WorkoutSessionLog(
            id: active.sessionID,
            ownerID: ownerID,
            templateID: active.planReference.storageKey,
            title: active.title,
            startedAt: active.startedAt,
            statusRaw: GymWorkoutSessionStatus.inProgress.rawValue,
            activeSessionJSON: try StrengthSessionPersistence.encode(active)
        )
        do {
            try await workoutRepository.createSession(log)
        } catch WorkoutRepositoryError.activeSessionAlreadyExists(let existingID) {
            throw StrengthWorkoutStartError.activeSessionInProgress(sessionID: existingID)
        }
        session = active
        debrief = nil
    }

    // MARK: - Progression decisions

    func recordProgressionDecision(_ accepted: StrengthAcceptedProposal) async throws {
        guard var active = session else { return }
        active.acceptedProposals[accepted.exerciseID] = accepted

        if let exerciseIndex = active.exercises.firstIndex(where: { $0.exerciseID == accepted.exerciseID }) {
            for setIndex in active.exercises[exerciseIndex].sets.indices
                where active.exercises[exerciseIndex].sets[setIndex].status == .pending
            {
                active.exercises[exerciseIndex].sets[setIndex].suggestedWeight = accepted.weight
            }
        }

        if let proposals = active.preFlightProposals, !proposals.isEmpty {
            active.preFlightCompleted = proposals.allSatisfy {
                active.acceptedProposals[$0.exerciseID] != nil
            }
        }

        try await persistSession(active)
        session = active
    }

    // MARK: - Set operations

    func confirmCurrentSet(weight: Double, reps: Int) async throws {
        guard var active = session else { return }
        guard let setID = active.currentSetID,
              let exerciseIndex = active.exercises.firstIndex(where: { $0.id == active.currentExerciseInstanceID }),
              let setIndex = active.exercises[exerciseIndex].sets.firstIndex(where: { $0.id == setID })
        else { return }

        active.exercises[exerciseIndex].sets[setIndex].confirmedWeight = weight
        active.exercises[exerciseIndex].sets[setIndex].confirmedReps = reps
        active.exercises[exerciseIndex].sets[setIndex].status = .confirmed

        let confirmedSet = active.exercises[exerciseIndex].sets[setIndex]
        let exercise = active.exercises[exerciseIndex]

        let setLog = WorkoutSetLog(
            exerciseID: exercise.exerciseID,
            exerciseName: exercise.displayName,
            setNumber: confirmedSet.setNumber,
            weightValue: weight,
            weightUnit: confirmedSet.weightUnit,
            repetitions: reps
        )
        try await workoutRepository.appendSet(setLog, to: active.sessionID)

        active.lastCoachingMessage = StrengthCoachingMessages.messageAfterConfirmingSet(
            exercise: exercise,
            confirmedSet: confirmedSet,
            prescription: active.prescription
        )

        advanceAfterConfirmedSet(&active)
        try await persistSession(active)
        session = active
    }

    func skipCurrentSet() async throws {
        guard var active = session else { return }
        guard let setID = active.currentSetID,
              let exerciseIndex = active.exercises.firstIndex(where: { $0.id == active.currentExerciseInstanceID }),
              let setIndex = active.exercises[exerciseIndex].sets.firstIndex(where: { $0.id == setID })
        else { return }

        active.exercises[exerciseIndex].sets[setIndex].status = .skipped
        advanceAfterConfirmedSet(&active)
        try await persistSession(active)
        session = active
    }

    func addExtraSet(to exerciseInstanceID: UUID) async throws {
        guard var active = session else { return }
        guard let exerciseIndex = active.exercises.firstIndex(where: { $0.id == exerciseInstanceID }) else { return }

        let exercise = active.exercises[exerciseIndex]
        let nextNumber = (exercise.sets.map(\.setNumber).max() ?? 0) + 1
        let lastConfirmed = exercise.sets.last { $0.status == .confirmed }
        let newSet = StrengthSetRecord(
            id: UUID(),
            setNumber: nextNumber,
            isWarmup: false,
            plannedReps: lastConfirmed?.plannedReps,
            suggestedWeight: lastConfirmed?.confirmedWeight ?? lastConfirmed?.suggestedWeight,
            suggestedReps: lastConfirmed?.confirmedReps ?? lastConfirmed?.suggestedReps,
            confirmedWeight: nil,
            confirmedReps: nil,
            weightUnit: active.weightUnit,
            status: .pending,
            isUserAdded: true
        )
        active.exercises[exerciseIndex].sets.append(newSet)
        active.exercises[exerciseIndex].status = .active
        active.currentExerciseInstanceID = exerciseInstanceID
        active.currentSetID = newSet.id
        try await persistSession(active)
        session = active
    }

    func skipExercise(exerciseInstanceID: UUID) async throws {
        guard var active = session else { return }
        guard let exerciseIndex = active.exercises.firstIndex(where: { $0.id == exerciseInstanceID }) else { return }

        active.exercises[exerciseIndex].status = .skipped
        for index in active.exercises[exerciseIndex].sets.indices {
            if active.exercises[exerciseIndex].sets[index].status == .pending {
                active.exercises[exerciseIndex].sets[index].status = .skipped
            }
        }
        if active.currentExerciseInstanceID == exerciseInstanceID {
            active.currentExerciseInstanceID = nil
            active.currentSetID = nil
        }
        StrengthSessionNavigation.recalculateAllExerciseStatuses(
            &active,
            currentExerciseID: active.currentExerciseInstanceID
        )
        try await persistSession(active)
        session = active
    }

    func completeExercise(exerciseInstanceID: UUID) async throws {
        guard var active = session else { return }
        guard let exerciseIndex = active.exercises.firstIndex(where: { $0.id == exerciseInstanceID }) else { return }
        for index in active.exercises[exerciseIndex].sets.indices where active.exercises[exerciseIndex].sets[index].status == .pending {
            active.exercises[exerciseIndex].sets[index].status = .skipped
        }
        active.exercises[exerciseIndex].status = .completed
        if active.currentExerciseInstanceID == exerciseInstanceID {
            active.currentSetID = nil
        }
        StrengthSessionNavigation.recalculateAllExerciseStatuses(
            &active,
            currentExerciseID: active.currentExerciseInstanceID
        )
        try await persistSession(active)
        session = active
    }

    // MARK: - Flexible navigation

    func selectExercise(exerciseInstanceID: UUID) async throws {
        guard var active = session else { return }
        guard active.exercises.contains(where: { $0.id == exerciseInstanceID }) else { return }

        active.currentExerciseInstanceID = exerciseInstanceID
        if let index = active.exercises.firstIndex(where: { $0.id == exerciseInstanceID }),
           active.exercises[index].status != .skipped
        {
            active.currentSetID = StrengthSessionNavigation.resolveCurrentSetID(
                for: active.exercises[index]
            )
        }
        StrengthSessionNavigation.recalculateAllExerciseStatuses(
            &active,
            currentExerciseID: exerciseInstanceID
        )
        active.lastCoachingMessage = nil
        try await persistSession(active)
        session = active
    }

    func selectSet(exerciseInstanceID: UUID, setID: UUID) async throws {
        guard var active = session else { return }
        guard let exerciseIndex = active.exercises.firstIndex(where: { $0.id == exerciseInstanceID }),
              active.exercises[exerciseIndex].sets.contains(where: { $0.id == setID })
        else { return }

        active.currentExerciseInstanceID = exerciseInstanceID
        active.currentSetID = setID
        StrengthSessionNavigation.recalculateAllExerciseStatuses(
            &active,
            currentExerciseID: exerciseInstanceID
        )
        try await persistSession(active)
        session = active
    }

    func applySuggestedValuesToCurrentSet(weight: Double?, reps: Int?) async throws {
        guard var active = session,
              let exerciseIndex = active.exercises.firstIndex(where: { $0.id == active.currentExerciseInstanceID }),
              let setID = active.currentSetID,
              let setIndex = active.exercises[exerciseIndex].sets.firstIndex(where: { $0.id == setID }),
              active.exercises[exerciseIndex].sets[setIndex].status == .pending
        else { return }

        if let weight {
            active.exercises[exerciseIndex].sets[setIndex].suggestedWeight = weight
        }
        if let reps {
            active.exercises[exerciseIndex].sets[setIndex].suggestedReps = reps
        }
        try await persistSession(active)
        session = active
    }

    func editConfirmedSet(
        exerciseInstanceID: UUID,
        setID: UUID,
        weight: Double,
        reps: Int
    ) async throws {
        try await mutateSet(exerciseInstanceID: exerciseInstanceID, setID: setID) { set in
            set.confirmedWeight = weight
            set.confirmedReps = reps
            set.status = .confirmed
        }
    }

    func markSetSkipped(exerciseInstanceID: UUID, setID: UUID) async throws {
        try await mutateSet(exerciseInstanceID: exerciseInstanceID, setID: setID) { set in
            set.status = .skipped
            set.confirmedWeight = nil
            set.confirmedReps = nil
        }
    }

    func restoreSkippedSet(exerciseInstanceID: UUID, setID: UUID) async throws {
        try await mutateSet(exerciseInstanceID: exerciseInstanceID, setID: setID) { set in
            set.status = .pending
            set.confirmedWeight = nil
            set.confirmedReps = nil
        }
    }

    func deleteExtraSet(exerciseInstanceID: UUID, setID: UUID) async throws {
        guard var active = session else { return }
        guard let exerciseIndex = active.exercises.firstIndex(where: { $0.id == exerciseInstanceID }),
              let setIndex = active.exercises[exerciseIndex].sets.firstIndex(where: { $0.id == setID }),
              active.exercises[exerciseIndex].sets[setIndex].isUserAdded
        else { return }

        active.exercises[exerciseIndex].sets.remove(at: setIndex)
        if active.currentSetID == setID {
            active.currentSetID = StrengthSessionNavigation.resolveCurrentSetID(
                for: active.exercises[exerciseIndex]
            )
        }
        StrengthSessionNavigation.recalculateAllExerciseStatuses(
            &active,
            currentExerciseID: active.currentExerciseInstanceID
        )
        try await persistSession(active)
        session = active
    }

    func persistActiveSession() async throws {
        guard let active = session else { return }
        try await persistSession(active)
    }

    var hasUnresolvedWork: Bool {
        guard let session else { return false }
        return StrengthSessionNavigation.hasUnresolvedWork(in: session)
    }

    func skipRemainingSetsAndComplete() async throws -> StrengthWorkoutDebrief {
        guard var active = session else {
            throw WorkoutRepositoryError.sessionNotFound(id: UUID())
        }
        for exerciseIndex in active.exercises.indices where active.exercises[exerciseIndex].status != .skipped {
            for setIndex in active.exercises[exerciseIndex].sets.indices
                where active.exercises[exerciseIndex].sets[setIndex].status == .pending
            {
                active.exercises[exerciseIndex].sets[setIndex].status = .skipped
            }
            active.exercises[exerciseIndex].status = .completed
        }
        session = active
        return try await finishWorkout()
    }

    // MARK: - Pause / resume

    func pauseSession() async throws {
        guard var active = session, active.pausedAt == nil else { return }
        active.pausedAt = .now
        try await persistSession(active)
        session = active
    }

    func resumeSession() async throws {
        guard var active = session, let pausedAt = active.pausedAt else { return }
        active.accumulatedPauseSeconds += Date.now.timeIntervalSince(pausedAt)
        active.pausedAt = nil
        try await persistSession(active)
        session = active
    }

    // MARK: - Finish / abandon

    func finishWorkout() async throws -> StrengthWorkoutDebrief {
        guard var active = session else {
            throw WorkoutRepositoryError.sessionNotFound(id: UUID())
        }
        active.status = .completed
        let built = StrengthDebriefBuilder.build(session: active)
        try await workoutRepository.completeSession(
            id: active.sessionID,
            completedAt: .now,
            debriefJSON: try StrengthSessionPersistence.encodeDebrief(built)
        )
        session = nil
        debrief = built
        return built
    }

    func abandonWorkout() async throws {
        guard let active = session else { return }
        try await workoutRepository.abandonSession(id: active.sessionID)
        session = nil
        debrief = nil
    }

    // MARK: - Navigation helpers

    private func activateFirstExercise(_ session: inout StrengthWorkoutSession) {
        guard let firstIndex = session.exercises.firstIndex(where: { $0.status != .skipped }) else { return }
        session.exercises[firstIndex].status = .active
        session.currentExerciseInstanceID = session.exercises[firstIndex].id
        session.currentSetID = session.exercises[firstIndex].sets.first { $0.status == .pending }?.id
    }

    private func advanceAfterConfirmedSet(_ session: inout StrengthWorkoutSession) {
        guard let exerciseIndex = session.exercises.firstIndex(where: { $0.id == session.currentExerciseInstanceID }) else {
            return
        }

        if let nextIndex = session.exercises[exerciseIndex].sets.firstIndex(where: { $0.status == .pending }) {
            let confirmedSet = session.exercises[exerciseIndex].sets.first {
                $0.status == .confirmed && $0.setNumber < session.exercises[exerciseIndex].sets[nextIndex].setNumber
            } ?? session.exercises[exerciseIndex].sets.first { $0.status == .confirmed }
            if let confirmedSet {
                session.exercises[exerciseIndex].sets[nextIndex].suggestedWeight =
                    confirmedSet.confirmedWeight ?? confirmedSet.suggestedWeight
                session.exercises[exerciseIndex].sets[nextIndex].suggestedReps =
                    confirmedSet.confirmedReps ?? confirmedSet.suggestedReps
            }
            session.currentSetID = session.exercises[exerciseIndex].sets[nextIndex].id
            return
        }

        session.exercises[exerciseIndex].status = .completed
        session.currentSetID = StrengthSessionNavigation.resolveCurrentSetID(
            for: session.exercises[exerciseIndex]
        )
        session.lastCoachingMessage = "Exercise complete — choose your next move."
        StrengthSessionNavigation.recalculateAllExerciseStatuses(
            &session,
            currentExerciseID: session.currentExerciseInstanceID
        )
    }

    private func mutateSet(
        exerciseInstanceID: UUID,
        setID: UUID,
        mutation: (inout StrengthSetRecord) -> Void
    ) async throws {
        guard var active = session else { return }
        guard let exerciseIndex = active.exercises.firstIndex(where: { $0.id == exerciseInstanceID }),
              let setIndex = active.exercises[exerciseIndex].sets.firstIndex(where: { $0.id == setID })
        else { return }

        mutation(&active.exercises[exerciseIndex].sets[setIndex])
        StrengthSessionNavigation.recalculateAllExerciseStatuses(
            &active,
            currentExerciseID: active.currentExerciseInstanceID
        )
        try await persistSession(active)
        session = active
    }

    private func persistSession(_ active: StrengthWorkoutSession) async throws {
        try StrengthSessionInvariants.validate(active)
        let log = WorkoutSessionLog(
            id: active.sessionID,
            ownerID: ownerID,
            templateID: active.planReference.storageKey,
            title: active.title,
            startedAt: active.startedAt,
            statusRaw: active.status.rawValue,
            activeSessionJSON: active.status == .inProgress ? try StrengthSessionPersistence.encode(active) : nil
        )
        try await workoutRepository.updateSession(log)
    }

    private func handlePersistenceFailure(_ error: Error) {
        reportError(userFacingMessage(for: error))
    }
}

private extension Optional where Wrapped: Collection {
    var isNilOrEmpty: Bool {
        switch self {
        case .none: return true
        case .some(let value): return value.isEmpty
        }
    }
}
