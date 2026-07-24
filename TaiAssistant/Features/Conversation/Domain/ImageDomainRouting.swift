import Foundation

// MARK: - Classification contract

enum MediaContentType: String, Codable, Sendable, Equatable {
    case meal
    case gymEquipment
    case ambiguous
    case unsupported
    case legacyUnknown
}

struct AIImageClassification: Codable, Equatable, Sendable {
    var contentType: MediaContentType
    var classificationConfidence: Double
    var classificationReason: String
    var containsFood: Bool
    var containsGymEquipment: Bool

    static let legacyUnknown = AIImageClassification(
        contentType: .legacyUnknown,
        classificationConfidence: 0,
        classificationReason: "Response did not include image classification.",
        containsFood: false,
        containsGymEquipment: false
    )
}

/// Durable image-classification metadata stored on conversation image artifacts.
struct PersistedImageClassification: Codable, Equatable, Sendable {
    var contentType: MediaContentType
    var classificationConfidence: Double?
    var containsFood: Bool?
    var containsGymEquipment: Bool?
    /// Attachment identity for supersession / correction flows.
    var sourceAttachmentID: UUID?

    init(
        contentType: MediaContentType,
        classificationConfidence: Double? = nil,
        containsFood: Bool? = nil,
        containsGymEquipment: Bool? = nil,
        sourceAttachmentID: UUID? = nil
    ) {
        self.contentType = contentType
        self.classificationConfidence = classificationConfidence
        self.containsFood = containsFood
        self.containsGymEquipment = containsGymEquipment
        self.sourceAttachmentID = sourceAttachmentID
    }

    init(classification: AIImageClassification, sourceAttachmentID: UUID? = nil) {
        self.init(
            contentType: classification.contentType,
            classificationConfidence: classification.classificationConfidence,
            containsFood: classification.containsFood,
            containsGymEquipment: classification.containsGymEquipment,
            sourceAttachmentID: sourceAttachmentID
        )
    }

    static func fromMealResponse(
        _ response: AIInterpretMealResponse,
        sourceAttachmentID: UUID? = nil
    ) -> PersistedImageClassification? {
        guard let contentType = response.contentType else { return nil }
        return PersistedImageClassification(
            contentType: contentType,
            classificationConfidence: response.classificationConfidence,
            containsFood: response.containsFood,
            containsGymEquipment: response.containsGymEquipment,
            sourceAttachmentID: sourceAttachmentID
        )
    }

    static func fromGymResponse(
        _ response: AIInterpretGymPhotoResponse,
        sourceAttachmentID: UUID? = nil
    ) -> PersistedImageClassification? {
        guard let contentType = response.contentType else { return nil }
        return PersistedImageClassification(
            contentType: contentType,
            classificationConfidence: response.classificationConfidence,
            containsFood: response.containsFood,
            containsGymEquipment: response.containsGymEquipment,
            sourceAttachmentID: sourceAttachmentID
        )
    }
}

enum ImageArtifactRestoration {
    static func isActionablePhotoReview(_ payload: StrengthPhotoReviewCardPayload) -> Bool {
        guard !payload.isApplied else { return false }
        guard let classification = payload.imageClassification else { return false }
        return classification.contentType == .gymEquipment
    }

    /// Text-only meal estimates omit `imageClassification` and remain actionable.
    static func isActionableMealEstimate(_ payload: MealEstimateCardPayload) -> Bool {
        guard !payload.isLogged else { return false }
        guard let classification = payload.imageClassification else { return true }
        return classification.contentType == .meal
    }

    static func sanitizeConversation(_ conversation: ActiveConversation) -> (ActiveConversation, didSanitize: Bool) {
        var sanitized = conversation
        var didSanitize = false

        sanitized.messages = conversation.messages.map { message in
            guard let card = message.card, card.isInteractive else { return message }

            if card.typeID == StrengthConversationCapabilityID.photoReviewCardType,
               let payload = StrengthPhotoReviewCardCodec.decode(card.payload),
               !isActionablePhotoReview(payload)
            {
                didSanitize = true
                return messageWithFrozenCard(message)
            }

            if card.typeID == MealCapabilityID.estimateCardType,
               let payload = MealCardCodec.decode(card.payload),
               !isActionableMealEstimate(payload)
            {
                didSanitize = true
                return messageWithFrozenCard(message)
            }

            return message
        }

        return (sanitized, didSanitize)
    }

    private static func messageWithFrozenCard(_ message: ConversationMessage) -> ConversationMessage {
        guard let card = message.card else { return message }
        let frozen = ConversationCard(
            id: card.id,
            typeID: card.typeID,
            payload: card.payload,
            isInteractive: false
        )
        return ConversationMessage(
            id: message.id,
            actor: message.actor,
            createdAt: message.createdAt,
            text: message.text,
            attachment: message.attachment,
            card: frozen,
            quickActions: message.quickActions
        )
    }
}

enum ImageInterpretationFailure: Error, Equatable, Sendable {
    case missingClassification
    case wrongDomain(expected: MediaContentType, actual: MediaContentType, classification: AIImageClassification)
    case ambiguous(AIImageClassification)
    case unsupported(AIImageClassification)
    case contradictory(String)
}

enum ImageDomainCorrectionIntent: Equatable, Sendable {
    case reclassifyAsMeal
    case reclassifyAsGym
}

enum ImageDomainCorrectionClassifier {
    private static let mealPatterns = [
        #"that['']?s my lunch"#,
        #"thats my lunch"#,
        #"this is (my )?food"#,
        #"that['']?s food"#,
        #"is(n't| not) a gym"#,
        #"not gym equipment"#,
        #"not a gym photo"#,
        #"it['']?s a meal"#,
        #"log (this|that|it) as a meal"#,
    ]

    private static let gymPatterns = [
        #"that['']?s the machine"#,
        #"that['']?s gym equipment"#,
        #"not my meal"#,
        #"is(n't| not) (my )?food"#,
        #"it['']?s (the )?machine"#,
        #"apply (this|that|it) to (my )?workout"#,
    ]

    static func detect(in text: String) -> ImageDomainCorrectionIntent? {
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalized.isEmpty else { return nil }

        if mealPatterns.contains(where: { normalized.range(of: $0, options: .regularExpression) != nil }) {
            return .reclassifyAsMeal
        }
        if gymPatterns.contains(where: { normalized.range(of: $0, options: .regularExpression) != nil }) {
            return .reclassifyAsGym
        }
        return nil
    }
}

enum ImageInterpretationValidator {
    private static let equipmentLabelTokens = [
        "equipment",
        "machine",
        "cable",
        "gym",
        "exercise",
        "weight stack",
        "selector pin",
    ]

    static func classification(from response: AIInterpretMealResponse) -> AIImageClassification {
        guard let contentType = response.contentType else { return .legacyUnknown }
        return AIImageClassification(
            contentType: contentType,
            classificationConfidence: response.classificationConfidence ?? 0,
            classificationReason: response.classificationReason ?? "",
            containsFood: response.containsFood ?? false,
            containsGymEquipment: response.containsGymEquipment ?? false
        )
    }

    static func classification(from response: AIInterpretGymPhotoResponse) -> AIImageClassification {
        guard let contentType = response.contentType else { return .legacyUnknown }
        return AIImageClassification(
            contentType: contentType,
            classificationConfidence: response.classificationConfidence ?? 0,
            classificationReason: response.classificationReason ?? "",
            containsFood: response.containsFood ?? false,
            containsGymEquipment: response.containsGymEquipment ?? false
        )
    }

    static func validateMealResponse(
        _ response: AIInterpretMealResponse,
        requiresImageClassification: Bool
    ) -> Result<AIInterpretMealResponse, ImageInterpretationFailure> {
        let classification = Self.classification(from: response)

        if requiresImageClassification {
            guard classification.contentType != .legacyUnknown else {
                return .failure(.missingClassification)
            }
            switch classification.contentType {
            case .meal:
                break
            case .gymEquipment:
                return .failure(.wrongDomain(expected: .meal, actual: .gymEquipment, classification: classification))
            case .ambiguous:
                return .failure(.ambiguous(classification))
            case .unsupported:
                return .failure(.unsupported(classification))
            case .legacyUnknown:
                return .failure(.missingClassification)
            }
        }

        if let contradiction = mealContradiction(in: response, classification: classification) {
            return .failure(.contradictory(contradiction))
        }

        let meals = response.interpretedMeals.filter { !isBogusNonFoodMeal($0) }
        guard !meals.isEmpty else {
            if requiresImageClassification {
                return .failure(.contradictory("Meal payload is empty or describes non-food content."))
            }
            return .failure(.contradictory("Could not build a meal estimate from that input."))
        }

        var validated = response
        validated.interpretedMeals = meals
        return .success(validated)
    }

    static func validateGymResponse(
        _ response: AIInterpretGymPhotoResponse
    ) -> Result<AIInterpretGymPhotoResponse, ImageInterpretationFailure> {
        let classification = Self.classification(from: response)

        guard classification.contentType != .legacyUnknown else {
            return .failure(.missingClassification)
        }

        switch classification.contentType {
        case .gymEquipment:
            break
        case .meal:
            return .failure(.wrongDomain(expected: .gymEquipment, actual: .meal, classification: classification))
        case .ambiguous:
            return .failure(.ambiguous(classification))
        case .unsupported:
            return .failure(.unsupported(classification))
        case .legacyUnknown:
            return .failure(.missingClassification)
        }

        if let contradiction = gymContradiction(in: response, classification: classification) {
            return .failure(.contradictory(contradiction))
        }

        return .success(response)
    }

    static func isBogusNonFoodMeal(_ meal: AIInterpretedMeal) -> Bool {
        let label = meal.label.lowercased()
        let looksLikeEquipment = equipmentLabelTokens.contains { label.contains($0) }
        let hasNoNutrition = meal.calories <= 0
            && meal.proteinGrams <= 0
            && meal.carbsGrams <= 0
            && meal.fatGrams <= 0
        let hasNoItems = meal.items.isEmpty
        return looksLikeEquipment && hasNoNutrition && hasNoItems
    }

    private static func mealContradiction(
        in response: AIInterpretMealResponse,
        classification: AIImageClassification
    ) -> String? {
        if classification.contentType == .meal, classification.containsFood == false {
            return "Classification says meal but food visibility is false."
        }
        if response.interpretedMeals.allSatisfy(isBogusNonFoodMeal) {
            return "Meal payload describes equipment rather than food."
        }
        if classification.containsGymEquipment == true,
           classification.containsFood != true,
           classification.contentType == .meal,
           response.interpretedMeals.allSatisfy({ $0.calories <= 0 })
        {
            return "Gym equipment visible without food evidence."
        }
        return nil
    }

    private static func gymContradiction(
        in response: AIInterpretGymPhotoResponse,
        classification: AIImageClassification
    ) -> String? {
        if classification.containsFood == true,
           classification.containsGymEquipment == false,
           !response.exerciseCandidates.isEmpty
        {
            return "Food is visible but gym exercise candidates were returned."
        }

        if classification.contentType == .gymEquipment,
           classification.containsGymEquipment == false,
           !response.exerciseCandidates.isEmpty
        {
            return "Gym equipment classification conflicts with visibility flags."
        }

        if classification.contentType == .gymEquipment,
           classification.containsFood == true,
           classification.containsGymEquipment == false
        {
            return "Image appears to show food, not gym equipment."
        }

        if classification.contentType == .ambiguous || classification.contentType == .unsupported,
           !response.exerciseCandidates.isEmpty
        {
            return "Ambiguous or unsupported classification cannot include gym exercise candidates."
        }

        return nil
    }
}

enum ImageInterpretationFailurePresentation {
    static func message(for failure: ImageInterpretationFailure) -> String {
        switch failure {
        case .missingClassification:
            return "I couldn't classify that photo safely. Try another angle or describe what you want to log."
        case .wrongDomain(_, let actual, _):
            switch actual {
            case .meal:
                return "This looks like a meal rather than gym equipment."
            case .gymEquipment:
                return "This looks like gym equipment rather than a meal."
            default:
                return "That photo doesn't match the requested flow."
            }
        case .ambiguous(let classification):
            let reason = classification.classificationReason.trimmingCharacters(in: .whitespacesAndNewlines)
            if reason.isEmpty {
                return "Is this a meal you want to log, or gym equipment for your workout?"
            }
            return reason
        case .unsupported(let classification):
            let reason = classification.classificationReason.trimmingCharacters(in: .whitespacesAndNewlines)
            return reason.isEmpty
                ? "I couldn't use that photo. Try another image, add a short description, or cancel."
                : reason
        case .contradictory:
            return "I couldn't reconcile what I saw in that photo. Try another angle or tell me whether it's a meal or gym equipment."
        }
    }
}
