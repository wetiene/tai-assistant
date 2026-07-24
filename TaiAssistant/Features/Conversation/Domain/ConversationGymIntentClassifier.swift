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
        case arrivedAtGym
        case general
    }

    static func classify(_ text: String) -> Classification {
        let normalized = text.lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if isExcludedGymArrivalPhrase(normalized) {
            return .general
        }

        if matchesArrivedAtGym(normalized) {
            return .arrivedAtGym
        }

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

    private static func matchesArrivedAtGym(_ normalized: String) -> Bool {
        if normalized.contains("arrived at the gym")
            || normalized.contains("i've arrived at the gym")
            || normalized.contains("ive arrived at the gym")
            || normalized.contains("just got to the gym")
            || normalized.contains("just arrived at the gym")
        {
            return true
        }

        if normalized.contains("i'm at the gym")
            || normalized.contains("im at the gym")
            || normalized == "at the gym"
        {
            return true
        }

        return false
    }

    private static func isExcludedGymArrivalPhrase(_ normalized: String) -> Bool {
        if normalized.contains("at the gym") {
            if normalized.contains("later")
                || normalized.contains("will be")
                || normalized.contains("going to")
                || normalized.contains("before i go")
                || normalized.contains("before going")
                || normalized.contains("yesterday")
                || normalized.contains("wasn't at")
                || normalized.contains("wasnt at")
                || normalized.contains("was at the gym")
                || normalized.contains("weren't at")
                || normalized.contains("werent at")
                || normalized.hasPrefix("how ")
                || normalized.hasPrefix("what ")
                || normalized.hasPrefix("when ")
                || normalized.hasPrefix("where ")
                || normalized.hasPrefix("why ")
                || normalized.contains("how often")
            {
                return true
            }
        }
        return false
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
