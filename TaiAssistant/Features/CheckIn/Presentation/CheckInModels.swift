import Foundation

/// Centralised thresholds for check-in AI meal UI (ambiguity, low-confidence hints).
enum CheckInAIConfidence {
    /// When model confidence is below this, nudge the user if there are no alternative labels.
    static let mealAmbiguityThreshold: Double = 0.72
    /// After explicit user-authored refinement text, cap model confidence so it is not treated as fully observation-backed.
    static let userRefinementConfidenceCeiling: Double = 0.88
}

extension Array where Element == CheckInContextRow {
    /// Groups end at each Tai (`.ai`) row; any trailing rows without a following `.ai` form one open tail group.
    func checkIn_interactionGroups() -> [[CheckInContextRow]] {
        var groups: [[CheckInContextRow]] = []
        var current: [CheckInContextRow] = []
        for row in self {
            current.append(row)
            if row.kind == .ai {
                groups.append(current)
                current = []
            }
        }
        if !current.isEmpty {
            groups.append(current)
        }
        return groups
    }
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

enum CheckInContextRowKind {
    case photo
    case user
    case ai
}

struct CheckInContextRow: Identifiable {
    let id: UUID
    let kind: CheckInContextRowKind
    let text: String
}

struct CheckInMealDraft: Identifiable {
    let id: UUID
    var label: String
    var timing: MealTiming
    var eatenAt: Date
    /// Immutable nutrition day this draft logs against. Set at first interpretation, never retargeted.
    let nutritionDay: NutritionDay
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

    init(
        id: UUID = UUID(),
        label: String,
        timing: MealTiming,
        eatenAt: Date,
        nutritionDay: NutritionDay = .today(),
        calories: Int,
        proteinGrams: Int,
        carbsGrams: Int,
        fatGrams: Int,
        confidence: Double,
        alternatives: [String],
        items: [CheckInMealItemDraft],
        isUserConfirmed: Bool = false,
        macrosNeedReview: Bool = false,
        originalAILabel: String? = nil,
        lastMacroEstimateBasis: String? = nil
    ) {
        self.id = id
        self.label = label
        self.timing = timing
        self.eatenAt = eatenAt
        self.nutritionDay = nutritionDay
        self.calories = calories
        self.proteinGrams = proteinGrams
        self.carbsGrams = carbsGrams
        self.fatGrams = fatGrams
        self.confidence = confidence
        self.alternatives = alternatives
        self.items = items
        self.isUserConfirmed = isUserConfirmed
        self.macrosNeedReview = macrosNeedReview
        self.originalAILabel = originalAILabel
        self.lastMacroEstimateBasis = lastMacroEstimateBasis
    }
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
    func interpret(
        input: String,
        photoData: Data?,
        mealRefinement: AIProxyMealRefinementPayload?
    ) async throws -> CheckInInterpretationResult
}

extension CheckInInterpreting {
    func interpret(input: String, photoData: Data?) async throws -> CheckInInterpretationResult {
        try await interpret(input: input, photoData: photoData, mealRefinement: nil)
    }
}

struct CheckInInterpretationResult {
    var meals: [CheckInMealDraft]
    var uiNotes: String?
}

extension CheckInMealDraft {
    init(aiMeal: AIInterpretedMeal, now: Date = .now, nutritionDay: NutritionDay? = nil) {
        let parsedEatenAt = ISO8601DateFormatter().date(from: aiMeal.eatenAtGuessISO8601 ?? "")
        self.id = UUID()
        self.label = aiMeal.label
        self.timing = MealTiming(rawValue: aiMeal.timing.lowercased()) ?? .other
        self.eatenAt = parsedEatenAt ?? now
        self.nutritionDay = nutritionDay ?? .today(now: now)
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
