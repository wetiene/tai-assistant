import Foundation

enum StrengthDebriefBuilder {
    static func build(
        session: StrengthWorkoutSession,
        completedAt: Date = .now
    ) -> StrengthWorkoutDebrief {
        var wins: [StrengthDebriefExerciseSummary] = []
        var watch: [StrengthDebriefExerciseSummary] = []
        var nextTime: [StrengthDebriefNextRecommendation] = []

        for exercise in session.exercises where exercise.status == .completed {
            let confirmed = exercise.confirmedWorkingSets
            guard !confirmed.isEmpty else { continue }

            let repRange = exercise.plannedExercise.effectiveRepRange(planPrescription: session.prescription)
            let summaryLine = formatSetLine(confirmed, unit: session.weightUnit)
            let weights = confirmed.compactMap(\.confirmedWeight)
            let uniqueWeights = Set(weights)

            if uniqueWeights.count == 1, let weight = weights.first {
                let firstWeight = exercise.sets.first?.suggestedWeight
                if let firstWeight, weight > firstWeight + 0.01 {
                    wins.append(
                        StrengthDebriefExerciseSummary(
                            exerciseID: exercise.exerciseID,
                            exerciseName: exercise.displayName,
                            summaryLine: summaryLine,
                            detail: "First completed session at \(weight.formattedWeight) \(session.weightUnit)."
                        )
                    )
                } else if confirmed.allSatisfy({ ($0.confirmedReps ?? 0) >= repRange.upper }) {
                    wins.append(
                        StrengthDebriefExerciseSummary(
                            exerciseID: exercise.exerciseID,
                            exerciseName: exercise.displayName,
                            summaryLine: summaryLine,
                            detail: "All working sets reached the top of the target range."
                        )
                    )
                }
            }

            if let last = confirmed.last, let lastReps = last.confirmedReps, lastReps < repRange.lower {
                watch.append(
                    StrengthDebriefExerciseSummary(
                        exerciseID: exercise.exerciseID,
                        exerciseName: exercise.displayName,
                        summaryLine: summaryLine,
                        detail: "Final set dropped below the target range."
                    )
                )
                nextTime.append(
                    StrengthDebriefNextRecommendation(
                        exerciseID: exercise.exerciseID,
                        exerciseName: exercise.displayName,
                        recommendation: "Hold the current weight."
                    )
                )
            } else if let weight = weights.last {
                let target = max(repRange.lower, repRange.upper - 1)
                nextTime.append(
                    StrengthDebriefNextRecommendation(
                        exerciseID: exercise.exerciseID,
                        exerciseName: exercise.displayName,
                        recommendation: "Repeat \(weight.formattedWeight) \(session.weightUnit) and aim for at least \(target) reps on each set."
                    )
                )
            }
        }

        let skipped = session.exercises.filter { $0.status == .skipped }.count
        let completed = session.exercises.filter { $0.status == .completed }.count

        return StrengthWorkoutDebrief(
            sessionID: session.sessionID,
            generatedAt: completedAt,
            durationSeconds: session.elapsedActiveSeconds,
            exercisesCompleted: completed,
            exercisesSkipped: skipped,
            totalWorkingSets: session.completedWorkingSetCount,
            wins: wins,
            watchItems: watch,
            nextTimeRecommendations: nextTime,
            recoveryNote: nil
        )
    }

    private static func formatSetLine(_ sets: [StrengthSetRecord], unit: String) -> String {
        guard let firstWeight = sets.first?.confirmedWeight else {
            return sets.compactMap(\.confirmedReps).map(String.init).joined(separator: " / ")
        }
        let weightLabel = firstWeight.formattedWeight
        let reps = sets.compactMap(\.confirmedReps).map(String.init).joined(separator: " / ")
        return "\(weightLabel) \(unit) × \(reps)"
    }
}

private extension Double {
    var formattedWeight: String {
        truncatingRemainder(dividingBy: 1) == 0 ? String(format: "%.0f", self) : String(format: "%.1f", self)
    }
}
