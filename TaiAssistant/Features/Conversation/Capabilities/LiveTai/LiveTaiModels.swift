import Foundation

// MARK: - Immutable Sendable snapshot (captured at repository / application boundary)

struct LiveTaiTurnSnippet: Equatable, Sendable {
    enum Role: String, Sendable {
        case user
        case assistant
    }

    let role: Role
    let text: String
}

struct LiveTaiMealSnapshot: Equatable, Sendable {
    let label: String
    let eatenAt: Date
    let calories: Int
    let proteinGrams: Double
    let carbsGrams: Double
    let fatGrams: Double
}

struct LiveTaiGoalSnapshot: Equatable, Sendable {
    let title: String
    let calorieTarget: Int
    let proteinTarget: Double
    let carbsTarget: Double
    let fatTarget: Double
}

struct LiveTaiDayNutritionSnapshot: Equatable, Sendable {
    let mealCount: Int
    let calories: Int
    let proteinGrams: Double
    let carbsGrams: Double
    let fatGrams: Double
    let calorieTarget: Int?
    let proteinTarget: Double?
    let carbsTarget: Double?
    let fatTarget: Double?
}

struct LiveTaiCapabilityFlags: Equatable, Sendable {
    let hasHealthKit: Bool
    let hasWorkouts: Bool
    let hasLocation: Bool
    let hasMealMemory: Bool

    static let p0Defaults = LiveTaiCapabilityFlags(
        hasHealthKit: false,
        hasWorkouts: false,
        hasLocation: false,
        hasMealMemory: false
    )
}

/// Lightweight immutable snapshot. Never contains SwiftData models, JPEG bytes or live Observable state.
struct LiveTaiContextSnapshot: Equatable, Sendable {
    let capturedAt: Date
    let localeIdentifier: String
    let timeZoneIdentifier: String
    let userAsk: String
    let recentTurns: [LiveTaiTurnSnippet]
    let dayNutrition: LiveTaiDayNutritionSnapshot
    let mealsToday: [LiveTaiMealSnapshot]
    let goal: LiveTaiGoalSnapshot?
    let capabilityFlags: LiveTaiCapabilityFlags
    /// Always included in the coach request; shown to the user only when material to the answer.
    let knownLimitations: [String]
}

enum LiveTaiContextLimits {
    static let maxRecentTurns = 10
    static let maxMealsToday = 12
    static let maxTurnCharacters = 500
}

enum LiveTaiKnownLimitations {
    static let defaults: [String] = [
        "Apple Health / HealthKit is not connected",
        "Sleep data is unavailable",
        "Weight data is unavailable",
        "Workout tracking is not available yet",
        "Location context is not available",
        "Meal Memory is not available yet",
    ]
}

// MARK: - Evidence / Why (message metadata card — not a coaching artifact)

struct LiveTaiEvidenceItem: Codable, Equatable, Sendable {
    var kind: String
    var label: String
    var detail: String?
}

struct LiveTaiEvidencePayload: Codable, Equatable, Sendable {
    var summary: String?
    var evidence: [LiveTaiEvidenceItem]
    var limitationsShown: [String]
    var confidence: String?
    var requiresUserDecision: Bool

    static let cardTypeID = "liveTai.evidence"
}

enum LiveTaiEvidenceCodec {
    static func encode(_ payload: LiveTaiEvidencePayload) -> Data {
        (try? JSONEncoder().encode(payload)) ?? Data()
    }

    static func decode(_ data: Data) -> LiveTaiEvidencePayload? {
        try? JSONDecoder().decode(LiveTaiEvidencePayload.self, from: data)
    }

    static func makeCard(payload: LiveTaiEvidencePayload) -> ConversationCard {
        ConversationCard(
            typeID: LiveTaiEvidencePayload.cardTypeID,
            payload: encode(payload),
            isInteractive: true
        )
    }
}
