import Foundation

enum StrengthSetFormatting {
    static func formatWorkoutDuration(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        }
        return String(format: "%d:%02d", minutes, secs)
    }

    static func displayLine(for set: StrengthSetRecord, exercise: StrengthExerciseInstance) -> String {
        switch set.status {
        case .confirmed:
            return confirmedLine(for: set, exercise: exercise)
        case .skipped:
            return "Skipped"
        case .pending:
            return pendingLine(for: set)
        }
    }

    static func confirmedLine(for set: StrengthSetRecord, exercise: StrengthExerciseInstance) -> String {
        let reps = set.confirmedReps ?? 0
        if let weight = set.confirmedWeight, weight > 0 {
            return "\(weight.formattedStrengthWeight) \(set.weightUnit) × \(reps)"
        }
        if exercise.plannedExercise.tracksBodyweight {
            return "Bodyweight × \(reps)"
        }
        if set.confirmedWeight != nil {
            return "0 \(set.weightUnit) × \(reps)"
        }
        return "\(reps) reps"
    }

    static func pendingLine(for set: StrengthSetRecord) -> String {
        if let weight = set.suggestedWeight, weight > 0 {
            let reps = set.suggestedReps ?? set.plannedReps ?? 0
            return "\(weight.formattedStrengthWeight) \(set.weightUnit) suggested · \(reps) reps"
        }
        if let reps = set.suggestedReps ?? set.plannedReps {
            return "\(reps) reps"
        }
        return "Pending"
    }

    static func editorWeightLabel(for set: StrengthSetRecord, exercise: StrengthExerciseInstance) -> String {
        if exercise.plannedExercise.tracksBodyweight {
            return "Bodyweight"
        }
        if let weight = set.confirmedWeight ?? set.suggestedWeight {
            return "\(weight.formattedStrengthWeight) \(set.weightUnit)"
        }
        return "Weight not set"
    }
}

extension Double {
    var formattedStrengthWeight: String {
        truncatingRemainder(dividingBy: 1) == 0 ? String(format: "%.0f", self) : String(format: "%.1f", self)
    }
}

extension GymPlannedExercise {
    var tracksBodyweight: Bool {
        displayName.localizedCaseInsensitiveContains("bodyweight")
    }
}
