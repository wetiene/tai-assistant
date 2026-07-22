import Foundation

enum ConversationGymIntentClassifier {
    enum Classification: Equatable, Sendable {
        case startUpperBody
        case startLowerBody
        case finishWorkout
        case openPlanImport
        case pastePlanText(String)
        case showCurrentProgram
        case replacePlan
        case general
    }

    static func classify(_ text: String) -> Classification {
        let normalized = text.lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if normalized.contains("finish workout")
            || normalized.contains("end workout")
            || normalized == "finish"
            || normalized.contains("done with workout")
        {
            return .finishWorkout
        }

        if normalized.contains("show my current program")
            || normalized.contains("show my current plan")
            || normalized.contains("what is my gym plan")
            || normalized.contains("what's my gym plan")
            || normalized.contains("my current workout program")
        {
            return .showCurrentProgram
        }

        if normalized.contains("replace my current gym plan")
            || normalized.contains("replace my workout plan")
            || normalized.contains("new trainer program")
        {
            return .replacePlan
        }

        if normalized.contains("import my trainer plan")
            || normalized.contains("import trainer plan")
            || normalized.contains("upload my workout program")
            || normalized.contains("upload workout program")
            || normalized.contains("upload my gym plan")
        {
            return .openPlanImport
        }

        if normalized.contains("paste a new workout plan")
            || normalized.contains("paste workout plan")
            || normalized.contains("paste my trainer plan")
            || normalized.contains("paste plan")
        {
            if looksLikeWorkoutPlanText(text) {
                return .pastePlanText(text)
            }
            return .openPlanImport
        }

        if looksLikeWorkoutPlanText(text) {
            return .pastePlanText(text)
        }

        if normalized.contains("upper body")
            || normalized.contains("upper workout")
            || normalized.contains("start upper")
            || normalized == "upper"
        {
            return .startUpperBody
        }

        if normalized.contains("lower body")
            || normalized.contains("lower workout")
            || normalized.contains("start lower")
            || normalized == "lower"
        {
            return .startLowerBody
        }

        return .general
    }

    /// Heuristic for pasted trainer programs (multi-section bullet lists).
    static func looksLikeWorkoutPlanText(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 40 else { return false }
        let lines = trimmed.components(separatedBy: .newlines)
        let bulletLines = lines.filter {
            let line = $0.trimmingCharacters(in: .whitespaces)
            return line.hasPrefix("-") || line.hasPrefix("•")
        }
        let sectionHeaders = lines.filter {
            let line = $0.trimmingCharacters(in: .whitespaces).lowercased()
            return line.hasSuffix(":") && (line.contains("upper") || line.contains("lower") || line.contains("body") || line.contains("day"))
        }
        return bulletLines.count >= 3 || (sectionHeaders.count >= 1 && bulletLines.count >= 2)
    }
}
