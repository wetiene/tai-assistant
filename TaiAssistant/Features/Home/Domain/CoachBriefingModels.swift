import Foundation

/// Where the primary Home / Coach CTA should take the user.
enum RecommendationActionDestination: Equatable, Sendable {
    case checkInMeal
    case reviewGoal
}

/// Structured reason Tai can show in a “Why this?” sheet.
struct RecommendationReason: Equatable, Sendable {
    /// Short, user-facing rule summary (no implementation jargon).
    let summary: String
    /// Confirmed facts used for the recommendation.
    let evidencePoints: [String]
    /// Explicit unknowns / uncertainty the user should know about.
    let unknowns: [String]
}

struct CoachRecommendation: Equatable, Sendable {
    let focusTitle: String
    let actionTitle: String
    let destination: RecommendationActionDestination
    let reason: RecommendationReason
}

struct NutritionProgressSnapshot: Equatable, Sendable {
    let caloriesConsumed: Int
    let calorieTarget: Int
    let proteinConsumed: Int
    let proteinTarget: Int
    let carbsConsumed: Int
    let carbsTarget: Int
    let fatConsumed: Int
    let fatTarget: Int
    let mealCountToday: Int

    var hasUsableTargets: Bool {
        calorieTarget > 0 || proteinTarget > 0 || carbsTarget > 0 || fatTarget > 0
    }
}

/// Deterministic daily briefing shared by Home and Coach.
struct DailyCoachBriefing: Equatable, Sendable {
    let greeting: String
    let headline: String
    let body: String
    let recommendation: CoachRecommendation
    let progress: NutritionProgressSnapshot
    let dataSufficiencyNote: String?
}

/// Plain inputs for briefing rules — no SwiftData / SwiftUI dependency.
struct CoachBriefingInput: Equatable, Sendable {
    let now: Date
    let calendar: Calendar
    let displayName: String?
    let hasActiveGoal: Bool
    let targets: CoachMacroTargets?
    let todayMealCount: Int
    let caloriesConsumed: Int
    let proteinGramsConsumed: Double
    let carbsGramsConsumed: Double
    let fatGramsConsumed: Double
    let assistantName: String
}

struct CoachMacroTargets: Equatable, Sendable {
    let calories: Int
    let proteinGrams: Double
    let carbsGrams: Double
    let fatGrams: Double

    var hasUsableValues: Bool {
        calories > 0 || proteinGrams > 0 || carbsGrams > 0 || fatGrams > 0
    }
}
