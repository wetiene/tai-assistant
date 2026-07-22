import Foundation

enum StrengthCoachingMessages {
    static func messageAfterConfirmingSet(
        exercise: StrengthExerciseInstance,
        confirmedSet: StrengthSetRecord,
        prescription: GymProgramPrescription
    ) -> String? {
        let repRange = exercise.plannedExercise.effectiveRepRange(planPrescription: prescription)
        let workingSets = exercise.workingSets.filter { $0.status == .confirmed }
        guard let reps = confirmedSet.confirmedReps else { return nil }

        if confirmedSet.setNumber == 1 {
            if reps >= repRange.upper {
                return "Strong first set. Aim for \(max(repRange.lower, repRange.upper - 2))–\(repRange.upper - 1) on set 2."
            }
            return "Set 1 logged. Aim for \(repRange.lower)–\(repRange.upper) on the next set."
        }

        if reps < repRange.lower {
            return "Set \(confirmedSet.setNumber) fell below target. Hold the same weight and focus on clean reps."
        }

        if reps >= repRange.upper, workingSets.count >= 2 {
            let allAtTop = workingSets.allSatisfy { ($0.confirmedReps ?? 0) >= repRange.upper }
            if allAtTop {
                return "You reached the top of the range. Do not increase mid-exercise unless you choose to."
            }
        }

        if let previous = workingSets.dropLast().last, let previousReps = previous.confirmedReps, reps < previousReps {
            return "Reps dipped on set \(confirmedSet.setNumber). Keep the weight and aim for steady reps."
        }

        return nil
    }
}
