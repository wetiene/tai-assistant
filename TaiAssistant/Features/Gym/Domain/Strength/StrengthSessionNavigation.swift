import Foundation

enum StrengthExerciseDisplayState: Equatable, Sendable {
    case upcoming
    case active
    case partial(completed: Int, total: Int)
    case completed
    case skipped
}

enum StrengthSessionNavigation {
    static func firstUnresolvedSet(in exercise: StrengthExerciseInstance) -> StrengthSetRecord? {
        exercise.sets.first { $0.status == .pending }
    }

    static func displayState(
        for exercise: StrengthExerciseInstance,
        isCurrent: Bool
    ) -> StrengthExerciseDisplayState {
        if exercise.status == .skipped {
            return .skipped
        }
        if isCurrent {
            return .active
        }
        let working = exercise.workingSets
        let resolved = working.filter { $0.status == .confirmed || $0.status == .skipped }.count
        if working.isEmpty {
            return .upcoming
        }
        if resolved == working.count {
            return .completed
        }
        if resolved > 0 {
            return .partial(completed: resolved, total: working.count)
        }
        return .upcoming
    }

    static func recalculateStoredStatus(
        for exercise: StrengthExerciseInstance,
        isCurrent: Bool
    ) -> StrengthExerciseStatus {
        if exercise.status == .skipped {
            return .skipped
        }
        let working = exercise.workingSets
        if working.allSatisfy({ $0.status == .confirmed || $0.status == .skipped }) {
            return .completed
        }
        if isCurrent {
            return .active
        }
        return .pending
    }

    static func recalculateAllExerciseStatuses(
        _ session: inout StrengthWorkoutSession,
        currentExerciseID: UUID?
    ) {
        for index in session.exercises.indices {
            let id = session.exercises[index].id
            session.exercises[index].status = recalculateStoredStatus(
                for: session.exercises[index],
                isCurrent: id == currentExerciseID
            )
        }
    }

    static func hasUnresolvedWork(in session: StrengthWorkoutSession) -> Bool {
        session.exercises.contains { exercise in
            guard exercise.status != .skipped else { return false }
            return exercise.workingSets.contains { $0.status == .pending }
        }
    }

    static func unresolvedSetCount(in session: StrengthWorkoutSession) -> Int {
        session.exercises.reduce(0) { partial, exercise in
            guard exercise.status != .skipped else { return partial }
            return partial + exercise.workingSets.filter { $0.status == .pending }.count
        }
    }

    static func resolveCurrentSetID(for exercise: StrengthExerciseInstance) -> UUID? {
        if let pending = firstUnresolvedSet(in: exercise) {
            return pending.id
        }
        return exercise.workingSets.last?.id
    }
}
