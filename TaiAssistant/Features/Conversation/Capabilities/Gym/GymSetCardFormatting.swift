import Foundation

enum GymSetCardValidation {
    static let supportedWeightUnits = ["kg", "lb"]

    static func canSave(
        selectedExerciseID: String,
        templateExerciseOptions: [GymTemplateExerciseOption],
        weightValue: Double?,
        repetitions: Int?,
        isSaved: Bool
    ) -> Bool {
        guard !isSaved else { return false }
        guard !selectedExerciseID.isEmpty else { return false }
        guard templateExerciseOptions.contains(where: { $0.exerciseID == selectedExerciseID }) else { return false }
        guard let weightValue, weightValue > 0 else { return false }
        guard let repetitions, repetitions > 0 else { return false }
        return true
    }

    static func templateExerciseOptions(for session: GymActiveSession) -> [GymTemplateExerciseOption] {
        var seen = Set<String>()
        var options: [GymTemplateExerciseOption] = []
        for exercise in session.exercises {
            for stableID in exercise.candidateStableIDs {
                guard seen.insert(stableID).inserted else { continue }
                let displayName: String
                if let catalogID = GymExerciseID(rawValue: stableID) {
                    displayName = catalogID.displayName
                } else {
                    displayName = exercise.displayName
                }
                options.append(
                    GymTemplateExerciseOption(
                        exerciseID: stableID,
                        displayName: displayName,
                        isOptional: exercise.isOptional
                    )
                )
            }
        }
        return options
    }

    static func parseWeight(_ text: String) -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ",", with: ".")
        guard !trimmed.isEmpty, let value = Double(trimmed), value > 0 else { return nil }
        return value
    }

    static func formatWeight(_ value: Double?) -> String {
        guard let value else { return "" }
        if value.truncatingRemainder(dividingBy: 1) == 0 {
            return String(format: "%.0f", value)
        }
        return String(format: "%.1f", value)
    }
}

enum GymSetCardFormatting {
    static func weightLabel(value: Double?, unit: String) -> String {
        guard let value else { return "Not detected — enter manually" }
        return "\(GymSetCardValidation.formatWeight(value)) \(unit)"
    }

    static func confidenceLabel(_ confidence: Double) -> String {
        "AI confidence \(Int((confidence * 100).rounded()))%"
    }

    static func setTitle(exerciseName: String, setNumber: Int) -> String {
        "\(exerciseName) — Set \(setNumber)"
    }

    static func workoutProgressLabel(session: GymActiveSession) -> String {
        let total = session.totalWorkingSets
        let done = session.completedSetCount
        return "Set \(done + 1) of \(total)"
    }

    static let notLoggedDisclaimer = "Nothing is saved until you tap Save Set."
}
