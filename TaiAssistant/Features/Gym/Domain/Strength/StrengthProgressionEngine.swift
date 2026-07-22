import Foundation

struct StrengthProgressionInput: Equatable, Sendable {
    var exerciseID: String
    var exerciseName: String
    var repRangeLower: Int
    var repRangeUpper: Int
    var recentSessions: [StrengthExerciseHistorySession]
    var daysSinceLastSession: Int?
    var hasActivePainFlag: Bool
    var weightUnit: String
}

enum StrengthProgressionEngine {
    private static let minimumComparableSessions = 3
    private static let longGapDays = 14
    private static let moderateGapDays = 7

    static func evaluate(_ input: StrengthProgressionInput) -> StrengthProgressionProposal {
        let currentWeight = input.recentSessions.first?.sets.last?.weight

        if input.hasActivePainFlag {
            return holdProposal(
                input: input,
                currentWeight: currentWeight,
                observation: "You flagged pain or a constraint for \(input.exerciseName).",
                rule: "Training load is held while pain or an active constraint is reported.",
                recommendation: "Hold your current load and focus on pain-free reps.",
                confidence: .high
            )
        }

        if let gap = input.daysSinceLastSession, gap >= longGapDays {
            let reduced = currentWeight.map { StrengthWeightIncrement.previousWeight(from: $0, exerciseID: input.exerciseID) }
            return StrengthProgressionProposal(
                exerciseID: input.exerciseID,
                exerciseName: input.exerciseName,
                currentWeight: currentWeight,
                proposedWeight: reduced ?? currentWeight,
                decision: .decrease,
                repRangeLower: input.repRangeLower,
                repRangeUpper: input.repRangeUpper,
                reasoning: StrengthProgressionReasoning(
                    observation: "It has been \(gap) days since your last \(input.exerciseName) session.",
                    rule: "A gap of \(longGapDays)+ days calls for a conservative restart.",
                    recommendation: reduced.map { "Try \($0.formattedWeight) \(input.weightUnit)." } ?? "Start lighter and rebuild.",
                    targetRepsLabel: "\(input.repRangeLower)–\(input.repRangeUpper) reps per set.",
                    fallback: "If reps fall below \(input.repRangeLower), hold or reduce load next time."
                ),
                confidence: .medium,
                weightUnit: input.weightUnit
            )
        }

        let comparable = Array(input.recentSessions.prefix(minimumComparableSessions))
        guard comparable.count >= minimumComparableSessions else {
            return holdProposal(
                input: input,
                currentWeight: currentWeight,
                observation: historyObservation(for: comparable, exerciseName: input.exerciseName, weightUnit: input.weightUnit),
                rule: "At least \(minimumComparableSessions) comparable sessions are needed before progressing.",
                recommendation: currentWeight.map { "Hold \($0.formattedWeight) \(input.weightUnit)." } ?? "Establish a baseline this session.",
                confidence: comparable.isEmpty ? .low : .medium
            )
        }

        if let gap = input.daysSinceLastSession, gap >= moderateGapDays {
            return holdProposal(
                input: input,
                currentWeight: currentWeight,
                observation: "It has been \(gap) days since your last \(input.exerciseName) session.",
                rule: "After a \(moderateGapDays)+ day gap, hold load for one session.",
                recommendation: currentWeight.map { "Hold \($0.formattedWeight) \(input.weightUnit)." } ?? "Match your last session.",
                confidence: .medium
            )
        }

        let performances = comparable.map { sessionPerformance($0, repRangeUpper: input.repRangeUpper, repRangeLower: input.repRangeLower) }

        if performances.allSatisfy({ $0 == .belowMinimum }) {
            let reduced = currentWeight.map { StrengthWeightIncrement.previousWeight(from: $0, exerciseID: input.exerciseID) }
            return StrengthProgressionProposal(
                exerciseID: input.exerciseID,
                exerciseName: input.exerciseName,
                currentWeight: currentWeight,
                proposedWeight: reduced ?? currentWeight,
                decision: .decrease,
                repRangeLower: input.repRangeLower,
                repRangeUpper: input.repRangeUpper,
                reasoning: StrengthProgressionReasoning(
                    observation: historyObservation(for: comparable, exerciseName: input.exerciseName, weightUnit: input.weightUnit),
                    rule: "Repeated sessions below the minimum target call for a conservative reduction.",
                    recommendation: reduced.map { "Try \($0.formattedWeight) \(input.weightUnit)." } ?? "Reduce load slightly.",
                    targetRepsLabel: "\(input.repRangeLower)–\(input.repRangeUpper) reps per set.",
                    fallback: "If reps stay below \(input.repRangeLower), hold or reduce again next time."
                ),
                confidence: .high,
                weightUnit: input.weightUnit
            )
        }

        if performances.allSatisfy({ $0 == .atOrAboveTop }) {
            let proposed = currentWeight.map { StrengthWeightIncrement.nextWeight(from: $0, exerciseID: input.exerciseID) }
            return StrengthProgressionProposal(
                exerciseID: input.exerciseID,
                exerciseName: input.exerciseName,
                currentWeight: currentWeight,
                proposedWeight: proposed,
                decision: .increase,
                repRangeLower: input.repRangeLower,
                repRangeUpper: input.repRangeUpper,
                reasoning: StrengthProgressionReasoning(
                    observation: historyObservation(for: comparable, exerciseName: input.exerciseName, weightUnit: input.weightUnit),
                    rule: "\(minimumComparableSessions) sessions at the top of the \(input.repRangeLower)–\(input.repRangeUpper) rep range qualifies for progression.",
                    recommendation: proposed.map { "Try \($0.formattedWeight) \(input.weightUnit)." } ?? "Increase load slightly.",
                    targetRepsLabel: "\(input.repRangeLower)–\(input.repRangeUpper) reps per set.",
                    fallback: "If the final set falls below \(input.repRangeLower) reps, hold the new weight next time."
                ),
                confidence: .high,
                weightUnit: input.weightUnit
            )
        }

        return holdProposal(
            input: input,
            currentWeight: currentWeight,
            observation: historyObservation(for: comparable, exerciseName: input.exerciseName, weightUnit: input.weightUnit),
            rule: "Mixed performance — stabilise at the current load before progressing.",
            recommendation: currentWeight.map { "Hold \($0.formattedWeight) \(input.weightUnit)." } ?? "Match your last session.",
            confidence: .medium
        )
    }

    // MARK: - Private

    private enum SessionPerformance {
        case atOrAboveTop
        case mixed
        case belowMinimum
    }

    private static func sessionPerformance(
        _ session: StrengthExerciseHistorySession,
        repRangeUpper: Int,
        repRangeLower: Int
    ) -> SessionPerformance {
        let reps = session.sets.map(\.reps)
        guard !reps.isEmpty else { return .mixed }
        if reps.allSatisfy({ $0 >= repRangeUpper }) { return .atOrAboveTop }
        if reps.allSatisfy({ $0 < repRangeLower }) { return .belowMinimum }
        return .mixed
    }

    private static func historyObservation(
        for sessions: [StrengthExerciseHistorySession],
        exerciseName: String,
        weightUnit: String
    ) -> String {
        guard let latest = sessions.first, !latest.sets.isEmpty else {
            return "No recent history for \(exerciseName)."
        }
        let weight = latest.sets[0].weight.formattedWeight
        let repLine = latest.sets.map(\.reps).map(String.init).joined(separator: " / ")
        if sessions.count >= minimumComparableSessions {
            return "Your last \(sessions.count) \(exerciseName) sessions were \(weight) \(weightUnit) for \(repLine)."
        }
        return "Your last \(exerciseName) session was \(weight) \(weightUnit) for \(repLine)."
    }

    private static func holdProposal(
        input: StrengthProgressionInput,
        currentWeight: Double?,
        observation: String,
        rule: String,
        recommendation: String,
        confidence: StrengthProgressionConfidence
    ) -> StrengthProgressionProposal {
        StrengthProgressionProposal(
            exerciseID: input.exerciseID,
            exerciseName: input.exerciseName,
            currentWeight: currentWeight,
            proposedWeight: currentWeight,
            decision: .hold,
            repRangeLower: input.repRangeLower,
            repRangeUpper: input.repRangeUpper,
            reasoning: StrengthProgressionReasoning(
                observation: observation,
                rule: rule,
                recommendation: recommendation,
                targetRepsLabel: "\(input.repRangeLower)–\(input.repRangeUpper) reps per set.",
                fallback: "If reps fall below \(input.repRangeLower), hold or reduce load next time."
            ),
            confidence: confidence,
            weightUnit: input.weightUnit
        )
    }
}

private extension Double {
    var formattedWeight: String {
        truncatingRemainder(dividingBy: 1) == 0 ? String(format: "%.0f", self) : String(format: "%.1f", self)
    }
}
