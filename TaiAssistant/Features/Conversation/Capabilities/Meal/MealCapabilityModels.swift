import Foundation

enum MealCapabilityID {
    static let capability = "meal"
    static let estimateCardType = "meal.estimate"

    enum Phase: String, Sendable {
        case idle
        case collecting
        case interpreting
        case reviewing
        case readyToLog
        case saving
        case completed
    }

    enum QuickAction {
        static let takePhoto = "meal.takePhoto"
        static let describeMeal = "meal.describeMeal"
        static let askTai = "meal.askTai"
        static let cancelRefine = "meal.cancelRefine"
    }

    enum CardAction: String, Codable, Sendable {
        case looksRight
        case changeSomething
        case logMeal
    }
}

/// Durable meal capability activity payload (persisted in `ConversationActivity.capability.payload`).
struct MealCapabilityActivityPayload: Codable, Equatable, Sendable {
    /// Explicit draft targeted for refinement after "Change something". Nil when not refining.
    var targetedDraftID: UUID?

    static func encode(_ payload: MealCapabilityActivityPayload) -> Data? {
        try? JSONEncoder().encode(payload)
    }

    static func decode(_ data: Data?) -> MealCapabilityActivityPayload? {
        guard let data, !data.isEmpty else { return nil }
        return try? JSONDecoder().decode(MealCapabilityActivityPayload.self, from: data)
    }
}

enum MealCapabilityActivityCodec {
    static func makeActivity(
        phase: MealCapabilityID.Phase,
        targetedDraftID: UUID? = nil
    ) -> ConversationActivity {
        let payload: Data?
        if let targetedDraftID {
            payload = MealCapabilityActivityPayload.encode(
                MealCapabilityActivityPayload(targetedDraftID: targetedDraftID)
            )
        } else {
            payload = nil
        }
        return .capability(
            capabilityID: MealCapabilityID.capability,
            phaseID: phase.rawValue,
            payload: payload
        )
    }

    static func targetedDraftID(from activity: ConversationActivity) -> UUID? {
        guard case let .capability(capabilityID, _, payload) = activity,
              capabilityID == MealCapabilityID.capability
        else { return nil }
        return MealCapabilityActivityPayload.decode(payload)?.targetedDraftID
    }
}

struct MealEstimateCardPayload: Codable, Equatable, Sendable {
    var draft: MealEstimateSnapshot
    var refinementAccepted: Bool
    var isLogged: Bool

    var showsLogMeal: Bool { refinementAccepted && !isLogged }
}

/// Codable snapshot of a meal estimate for conversation cards (history-safe).
struct MealEstimateSnapshot: Codable, Equatable, Sendable {
    var id: UUID
    var label: String
    var timingRaw: String
    var eatenAt: Date
    var calories: Int
    var proteinGrams: Int
    var carbsGrams: Int
    var fatGrams: Int
    var confidence: Double
    var alternatives: [String]
    var items: [MealEstimateItemSnapshot]
    var isUserConfirmed: Bool
    var macrosNeedReview: Bool
    /// Normalized start-of-day for the draft's immutable nutrition day. Nil on legacy card payloads.
    var nutritionDayStart: Date?

    var nutritionDay: NutritionDay {
        if let nutritionDayStart {
            return NutritionDay(normalizedStart: nutritionDayStart)
        }
        return NutritionDay(containing: eatenAt)
    }

    init(draft: CheckInMealDraft) {
        id = draft.id
        label = draft.label
        timingRaw = draft.timing.rawValue
        eatenAt = draft.eatenAt
        nutritionDayStart = draft.nutritionDay.start
        calories = draft.calories
        proteinGrams = draft.proteinGrams
        carbsGrams = draft.carbsGrams
        fatGrams = draft.fatGrams
        confidence = draft.confidence
        alternatives = draft.alternatives
        items = draft.items.map(MealEstimateItemSnapshot.init)
        isUserConfirmed = draft.isUserConfirmed
        macrosNeedReview = draft.macrosNeedReview
    }

    func asCheckInDraft() -> CheckInMealDraft {
        CheckInMealDraft(
            id: id,
            label: label,
            timing: MealTiming(rawValue: timingRaw) ?? .other,
            eatenAt: eatenAt,
            nutritionDay: nutritionDay,
            calories: calories,
            proteinGrams: proteinGrams,
            carbsGrams: carbsGrams,
            fatGrams: fatGrams,
            confidence: confidence,
            alternatives: alternatives,
            items: items.map { $0.asCheckInItem() },
            isUserConfirmed: isUserConfirmed,
            macrosNeedReview: macrosNeedReview,
            originalAILabel: label,
            lastMacroEstimateBasis: label
        )
    }
}

struct MealEstimateItemSnapshot: Codable, Equatable, Sendable {
    var id: UUID
    var name: String
    var amount: Double
    var unit: String
    var calories: Int
    var proteinGrams: Double
    var carbsGrams: Double
    var fatGrams: Double
    var fiberGrams: Double

    init(item: CheckInMealItemDraft) {
        id = item.id
        name = item.name
        amount = item.amount
        unit = item.unit
        calories = item.calories
        proteinGrams = item.proteinGrams
        carbsGrams = item.carbsGrams
        fatGrams = item.fatGrams
        fiberGrams = item.fiberGrams
    }

    func asCheckInItem() -> CheckInMealItemDraft {
        CheckInMealItemDraft(
            id: id,
            name: name,
            amount: amount,
            unit: unit,
            calories: calories,
            proteinGrams: proteinGrams,
            carbsGrams: carbsGrams,
            fatGrams: fatGrams,
            fiberGrams: fiberGrams
        )
    }
}

enum MealCardCodec {
    static func encode(_ payload: MealEstimateCardPayload) -> Data {
        (try? JSONEncoder().encode(payload)) ?? Data()
    }

    static func decode(_ data: Data) -> MealEstimateCardPayload? {
        try? JSONDecoder().decode(MealEstimateCardPayload.self, from: data)
    }

    static func makeCard(payload: MealEstimateCardPayload, interactive: Bool = true) -> ConversationCard {
        ConversationCard(
            typeID: MealCapabilityID.estimateCardType,
            payload: encode(payload),
            isInteractive: interactive
        )
    }
}
