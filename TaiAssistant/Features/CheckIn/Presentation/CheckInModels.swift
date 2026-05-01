import Foundation

/// Centralised thresholds for check-in AI meal UI (ambiguity, low-confidence hints).
enum CheckInAIConfidence {
    /// When model confidence is below this, nudge the user if there are no alternative labels.
    static let mealAmbiguityThreshold: Double = 0.72
}

struct CheckInSessionDraft {
    var userInput: String = ""
    var selectedPhotoData: Data?
    var interpretedMeals: [CheckInMealDraft] = []
    var interpretationNotes: String?
    var createdAt: Date = .now

    var confirmTitle: String {
        "Confirm \(interpretedMeals.count) Meal\(interpretedMeals.count == 1 ? "" : "s")"
    }
}

struct CheckInMealDraft: Identifiable {
    let id: UUID
    var label: String
    var timing: MealTiming
    var eatenAt: Date
    var calories: Int
    var proteinGrams: Int
    var carbsGrams: Int
    var fatGrams: Int
    var confidence: Double
    var alternatives: [String]
    var items: [CheckInMealItemDraft]
    /// User chose a label (chip or manual edit); not persisted.
    var isUserConfirmed: Bool = false
    /// True when label changed after AI macro estimate and macros may be stale.
    var macrosNeedReview: Bool = false
    /// Original AI label used when the draft was first created.
    var originalAILabel: String? = nil
    /// Label text that current macro estimate is based on.
    var lastMacroEstimateBasis: String? = nil
}

extension CheckInMealDraft {
    var isAmbiguous: Bool { !alternatives.isEmpty }

    var isLowConfidence: Bool { confidence < CheckInAIConfidence.mealAmbiguityThreshold }

    var shouldShowAmbiguityUI: Bool { isAmbiguous || isLowConfidence }
}

struct CheckInMealItemDraft: Identifiable {
    let id: UUID
    var name: String
    var amount: Double
    var unit: String
    var calories: Int
    var proteinGrams: Double
    var carbsGrams: Double
    var fatGrams: Double
    var fiberGrams: Double
}

protocol CheckInInterpreting {
    func interpret(input: String, photoData: Data?) async throws -> CheckInInterpretationResult
}

struct CheckInInterpretationResult {
    var meals: [CheckInMealDraft]
    var uiNotes: String?
}

extension CheckInMealDraft {
    init(aiMeal: AIInterpretedMeal, now: Date = .now) {
        let parsedEatenAt = ISO8601DateFormatter().date(from: aiMeal.eatenAtGuessISO8601 ?? "")
        self.id = UUID()
        self.label = aiMeal.label
        self.timing = MealTiming(rawValue: aiMeal.timing.lowercased()) ?? .other
        self.eatenAt = parsedEatenAt ?? now
        self.calories = aiMeal.calories
        self.proteinGrams = Int(aiMeal.proteinGrams.rounded())
        self.carbsGrams = Int(aiMeal.carbsGrams.rounded())
        self.fatGrams = Int(aiMeal.fatGrams.rounded())
        self.confidence = min(max(aiMeal.confidence, 0), 1)
        self.alternatives = aiMeal.alternatives
        self.items = aiMeal.items.map {
            CheckInMealItemDraft(
                id: UUID(),
                name: $0.name,
                amount: $0.amount,
                unit: $0.unit,
                calories: $0.calories,
                proteinGrams: $0.proteinGrams,
                carbsGrams: $0.carbsGrams,
                fatGrams: $0.fatGrams,
                fiberGrams: $0.fiberGrams
            )
        }
        self.isUserConfirmed = false
        self.macrosNeedReview = false
        self.originalAILabel = aiMeal.label
        self.lastMacroEstimateBasis = aiMeal.label
    }
}
