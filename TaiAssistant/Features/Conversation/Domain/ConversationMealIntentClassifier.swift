import Foundation

/// Local, deterministic meal-vs-question intent for Conversation routing.
/// No network. No Artifact writes. Not a keyword dump inside the ViewModel.
enum ConversationMealIntent: Equatable, Sendable {
    /// High-confidence statement that food was consumed / should be logged.
    case mealLogStatement
    /// Question or advice request (including food-related questions).
    case coachingQuestion
    /// Short food fragment that could be either log or ask.
    case ambiguousFoodFragment
    /// No meal signal — treat as general coaching.
    case general
}

enum ConversationMealIntentClassifier {
    static func classify(_ raw: String) -> ConversationMealIntent {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return .general }

        let normalized = normalize(text)

        if looksLikeQuestion(normalized, original: text) {
            return .coachingQuestion
        }
        if looksLikeMealLogStatement(normalized) {
            return .mealLogStatement
        }
        if looksLikeAmbiguousFoodFragment(normalized) {
            return .ambiguousFoodFragment
        }
        return .general
    }

    // MARK: - Rules

    private static func normalize(_ text: String) -> String {
        text
            .lowercased()
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func looksLikeQuestion(_ normalized: String, original: String) -> Bool {
        if original.contains("?") { return true }

        let interrogativePrefixes = [
            "can i ", "could i ", "should i ", "may i ", "shall i ",
            "what ", "when ", "where ", "why ", "how ", "which ",
            "is my ", "was my ", "are my ", "were my ",
            "is it ", "was it ", "am i ",
            "do i ", "did i ", "does ",
            "would ", "will ",
            "any chance ", "is there ",
        ]
        if interrogativePrefixes.contains(where: { normalized.hasPrefix($0) }) {
            return true
        }

        // Advice / comparison / remaining-macro asks without leading interrogative.
        let questionPhrases = [
            "what should i eat",
            "what did i eat",
            "how much protein",
            "how many calories",
            "protein left",
            "calories left",
            "too heavy",
            "too much",
            "ok to have",
            "okay to have",
            "alright to have",
            "good idea to",
            "recommend",
            "suggestion",
            "advise",
            "better than",
            "compare",
        ]
        if questionPhrases.contains(where: { normalized.contains($0) }) {
            return true
        }

        return false
    }

    private static func looksLikeMealLogStatement(_ normalized: String) -> Bool {
        // Explicit meal-slot labels: "Breakfast was…", "Dinner: …"
        let mealLabelPatterns = [
            #"^(breakfast|lunch|dinner|brunch|snack)\s*(was|is|:|-)"#,
            #"^(breakfast|lunch|dinner|brunch|snack)\s+.+"#,
        ]
        for pattern in mealLabelPatterns {
            if normalized.range(of: pattern, options: .regularExpression) != nil {
                return true
            }
        }

        // Past-tense / just-ate consumption phrasing.
        let consumptionPrefixes = [
            "had ", "ate ", "eaten ", "just ate ", "just had ",
            "i had ", "i ate ", "i've had ", "ive had ", "i have had ",
            "i've eaten ", "ive eaten ", "i have eaten ",
            "finished ", "polished off ", "grabbed ",
            "logged ", "logging ",
        ]
        if consumptionPrefixes.contains(where: { normalized.hasPrefix($0) }) {
            return true
        }

        // Quantity + food entry style: "two coffees", "half a pizza", "a protein shake"
        let quantityFood = [
            #"^(a|an|one|two|three|four|five|\d+)\s+.+"#,
            #"^(half|quarter)\s+(an?\s+)?.+"#,
        ]
        if quantityFood.contains(where: { normalized.range(of: $0, options: .regularExpression) != nil }),
           containsFoodSignal(normalized)
        {
            return true
        }

        // Multi-token food entries without question cues (e.g. "Protein shake", "chicken wrap").
        let tokens = normalized.split(separator: " ").map(String.init)
        if tokens.count >= 2, tokens.count <= 16, containsFoodSignal(normalized) {
            return true
        }

        return false
    }

    private static func looksLikeAmbiguousFoodFragment(_ normalized: String) -> Bool {
        let tokens = normalized.split(separator: " ").map(String.init)
        // Single-token food nouns only — "Pizza", "Coffee". Longer entries are meal statements.
        guard tokens.count == 1 else { return false }
        return containsFoodSignal(normalized)
    }

    /// Compact food lexicon for structural matching — kept here (testable), not in the ViewModel.
    private static func containsFoodSignal(_ normalized: String) -> Bool {
        let foods = [
            "pizza", "burger", "chip", "fries", "chicken", "rice", "oat", "coffee", "coffees",
            "tea", "shake", "protein", "sushi", "salmon", "broccoli", "egg", "eggs", "toast",
            "sandwich", "wrap", "salad", "pasta", "noodle", "steak", "fish", "yogurt", "yoghurt",
            "banana", "apple", "avocado", "bagel", "muffin", "croissant", "burrito", "taco",
            "ramen", "soup", "porridge", "cereal", "smoothie", "juice", "beer", "wine",
            "dessert", "cake", "cookie", "biscuit", "chocolate", "ice cream", "icecream",
            "breakfast", "lunch", "dinner", "brunch", "snack", "meal",
        ]
        return foods.contains { food in
            normalized == food
                || normalized.hasPrefix(food + " ")
                || normalized.hasSuffix(" " + food)
                || normalized.contains(" " + food + " ")
                || normalized.contains(food + "s") // simple plural
                || normalized.hasPrefix(food + "s ")
                || normalized.hasSuffix(" " + food + "s")
        }
    }
}
