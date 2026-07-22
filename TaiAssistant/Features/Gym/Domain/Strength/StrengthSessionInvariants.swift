import Foundation

enum StrengthSessionInvariantViolation: Error, Equatable {
    case setCannotBeConfirmedAndSkipped
    case confirmedSetMissingValues(setID: UUID)
    case proposalReferencesMissingExercise(exerciseID: String)
    case completedSessionCannotBeActive
    case cannotResumeCompletedSession
}

enum StrengthSessionInvariants {
    static func validate(_ session: StrengthWorkoutSession) throws {
        guard session.status == .inProgress else {
            if session.status == .completed {
                throw StrengthSessionInvariantViolation.completedSessionCannotBeActive
            }
            return
        }

        for exercise in session.exercises {
            for set in exercise.sets {
                if set.status == .confirmed {
                    guard set.confirmedWeight != nil, set.confirmedReps != nil else {
                        throw StrengthSessionInvariantViolation.confirmedSetMissingValues(setID: set.id)
                    }
                }
            }
        }

        let exerciseIDs = Set(session.exercises.map(\.exerciseID))
        for exerciseID in session.acceptedProposals.keys where !exerciseIDs.contains(exerciseID) {
            throw StrengthSessionInvariantViolation.proposalReferencesMissingExercise(exerciseID: exerciseID)
        }
    }

    static func pruneAcceptedProposals(
        _ accepted: [String: StrengthAcceptedProposal],
        for planExerciseIDs: Set<String>
    ) -> [String: StrengthAcceptedProposal] {
        accepted.filter { planExerciseIDs.contains($0.key) }
    }

    static func reconcileAcceptedProposals(
        _ accepted: [String: StrengthAcceptedProposal],
        refreshedProposals: [StrengthProgressionProposal]
    ) -> [String: StrengthAcceptedProposal] {
        let refreshedByID = Dictionary(uniqueKeysWithValues: refreshedProposals.map { ($0.exerciseID, $0) })
        return accepted.compactMapValues { entry in
            guard let refreshed = refreshedByID[entry.exerciseID] else { return nil }
            switch entry.decision {
            case .accepted:
                guard refreshed.proposedWeight == entry.originalProposal.proposedWeight else { return nil }
                return entry
            case .hold:
                guard refreshed.currentWeight == entry.originalProposal.currentWeight else { return nil }
                return entry
            case .custom:
                return entry
            }
        }
    }
}
