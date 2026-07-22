import Foundation
import OSLog

enum StrengthSessionPersistenceError: Error, Equatable {
    case encodingFailed(operation: String, underlyingDescription: String)
}

enum StrengthSessionPersistence {
    static let currentSnapshotVersion = 2
    private static let logger = Logger(subsystem: "com.taiassistant", category: "StrengthSessionPersistence")

    struct EncodingHandlers: Sendable {
        var encodeSession: @Sendable (StrengthWorkoutSession) throws -> Data
        var encodeDebrief: @Sendable (StrengthWorkoutDebrief) throws -> Data
        var encodeLegacy: @Sendable (GymActiveSession) throws -> Data
    }

    static var encoding = EncodingHandlers(
        encodeSession: { session in
            var encoded = session
            encoded.snapshotVersion = currentSnapshotVersion
            return try JSONEncoder().encode(WorkoutSessionSnapshotEnvelope.strength(encoded))
        },
        encodeDebrief: { debrief in
            try JSONEncoder().encode(debrief)
        },
        encodeLegacy: { legacy in
            try JSONEncoder().encode(WorkoutSessionSnapshotEnvelope.legacy(legacy))
        }
    )

    static func encode(_ session: StrengthWorkoutSession) throws -> Data {
        do {
            return try encoding.encodeSession(session)
        } catch {
            logger.error("Strength snapshot encode failed: \(error.localizedDescription, privacy: .public)")
            throw StrengthSessionPersistenceError.encodingFailed(
                operation: "strength_session_snapshot",
                underlyingDescription: String(describing: type(of: error))
            )
        }
    }

    static func encodeLegacy(_ session: GymActiveSession) throws -> Data {
        do {
            return try encoding.encodeLegacy(session)
        } catch {
            logger.error("Legacy snapshot encode failed: \(error.localizedDescription, privacy: .public)")
            throw StrengthSessionPersistenceError.encodingFailed(
                operation: "legacy_session_snapshot",
                underlyingDescription: String(describing: type(of: error))
            )
        }
    }

    static func encodeDebrief(_ debrief: StrengthWorkoutDebrief) throws -> Data {
        do {
            return try encoding.encodeDebrief(debrief)
        } catch {
            logger.error("Debrief encode failed: \(error.localizedDescription, privacy: .public)")
            throw StrengthSessionPersistenceError.encodingFailed(
                operation: "workout_debrief",
                underlyingDescription: String(describing: type(of: error))
            )
        }
    }

    enum DecodeResult: Equatable {
        case strength(StrengthWorkoutSession)
        case legacyMigrated(StrengthWorkoutSession)
        case malformed
    }

    static func decode(from data: Data?) -> DecodeResult? {
        guard let data else { return nil }
        if let envelope = try? JSONDecoder().decode(WorkoutSessionSnapshotEnvelope.self, from: data) {
            switch envelope.kind {
            case .strengthCoach:
                if let strength = envelope.strengthSession {
                    return .strength(validateRestoredSession(strength))
                }
                return .malformed
            case .legacyGymActive:
                if let legacy = envelope.legacySession {
                    return .legacyMigrated(validateRestoredSession(migrateLegacySession(legacy)))
                }
                return .malformed
            }
        }
        if let legacy = try? JSONDecoder().decode(GymActiveSession.self, from: data) {
            return .legacyMigrated(validateRestoredSession(migrateLegacySession(legacy)))
        }
        return .malformed
    }

    static func decodeStrength(from data: Data?) -> StrengthWorkoutSession? {
        switch decode(from: data) {
        case .strength(let session), .legacyMigrated(let session):
            return session
        case .malformed, .none:
            return nil
        }
    }

    /// Returns a strength session only when the envelope is explicitly `strength_coach`.
    static func decodeStrengthEnvelope(from data: Data?) -> StrengthWorkoutSession? {
        guard let data,
              let envelope = try? JSONDecoder().decode(WorkoutSessionSnapshotEnvelope.self, from: data),
              envelope.kind == .strengthCoach,
              let strength = envelope.strengthSession
        else {
            return nil
        }
        return validateRestoredSession(strength)
    }

    static func decodeLegacyGymActive(from data: Data?) -> GymActiveSession? {
        guard let data else { return nil }
        if let envelope = try? JSONDecoder().decode(WorkoutSessionSnapshotEnvelope.self, from: data),
           envelope.kind == .legacyGymActive,
           let legacy = envelope.legacySession {
            return legacy
        }
        return try? JSONDecoder().decode(GymActiveSession.self, from: data)
    }

    static func decodeDebrief(from data: Data?) -> StrengthWorkoutDebrief? {
        guard let data else { return nil }
        return try? JSONDecoder().decode(StrengthWorkoutDebrief.self, from: data)
    }

    static func migrateLegacySession(_ legacy: GymActiveSession) -> StrengthWorkoutSession {
        let weightUnit = "kg"
        let exercises: [StrengthExerciseInstance] = legacy.exercises.enumerated().map { index, planned in
            let setCount = planned.effectiveSets(planPrescription: legacy.prescription)
            let repRange = planned.effectiveRepRange(planPrescription: legacy.prescription)
            let sets = (1...setCount).map { setNumber in
                StrengthSetRecord(
                    id: UUID(),
                    setNumber: setNumber,
                    isWarmup: false,
                    plannedReps: repRange.upper,
                    suggestedWeight: nil,
                    suggestedReps: repRange.upper,
                    confirmedWeight: nil,
                    confirmedReps: nil,
                    weightUnit: weightUnit,
                    status: .pending
                )
            }
            let status: StrengthExerciseStatus
            if index < legacy.currentExerciseIndex {
                status = .completed
            } else if index == legacy.currentExerciseIndex {
                status = .active
            } else {
                status = .pending
            }
            return StrengthExerciseInstance(
                id: UUID(),
                plannedExercise: planned,
                status: status,
                sets: sets
            )
        }

        let currentExercise = exercises.indices.contains(legacy.currentExerciseIndex)
            ? exercises[legacy.currentExerciseIndex]
            : exercises.first
        let currentSet = currentExercise?.sets.first { $0.setNumber == legacy.currentSetNumber }

        return StrengthWorkoutSession(
            sessionID: legacy.sessionID,
            planReference: legacy.planReference,
            title: legacy.title,
            sectionName: nil,
            sectionIndex: 0,
            prescription: legacy.prescription,
            exercises: exercises,
            currentExerciseInstanceID: currentExercise?.id,
            currentSetID: currentSet?.id,
            startedAt: legacy.startedAt,
            pausedAt: nil,
            accumulatedPauseSeconds: 0,
            status: legacy.status,
            mission: "Continue your workout.",
            acceptedProposals: [:],
            preFlightProposals: nil,
            preFlightCompleted: false,
            origin: .conversation,
            snapshotVersion: currentSnapshotVersion,
            weightUnit: weightUnit,
            lastCoachingMessage: nil
        )
    }

    private static func validateRestoredSession(_ session: StrengthWorkoutSession) -> StrengthWorkoutSession {
        var restored = session
        restored.exercises = restored.exercises.map { exercise in
            var copy = exercise
            copy.sets = exercise.sets.map { set in
                guard set.status == .confirmed else { return set }
                var confirmed = set
                if confirmed.confirmedWeight == nil { confirmed.confirmedWeight = confirmed.suggestedWeight }
                if confirmed.confirmedReps == nil { confirmed.confirmedReps = confirmed.suggestedReps }
                return confirmed
            }
            return copy
        }
        restored.acceptedProposals = restored.acceptedProposals.filter { key, _ in
            restored.exercises.contains { $0.exerciseID == key }
        }
        return restored
    }
}
