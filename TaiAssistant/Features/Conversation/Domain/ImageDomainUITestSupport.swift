import Foundation

enum ImageDomainUITestScenario: String, Sendable {
    case mealViaGymPhoto
    case gymViaMealPhoto
    case wrongGymArtifact
    case partialGymWeight
    case ambiguousImage
}

enum ImageDomainUITestSupport {
    static var isEnabled: Bool {
        ProcessInfo.processInfo.arguments.contains("-UITestImageDomain")
            || ProcessInfo.processInfo.environment["UITEST_IMAGE_DOMAIN"] == "1"
    }

    static var scenario: ImageDomainUITestScenario? {
        guard isEnabled,
              let raw = ProcessInfo.processInfo.environment["UITEST_IMAGE_DOMAIN_SCENARIO"]?
                .trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty
        else { return nil }
        return ImageDomainUITestScenario(rawValue: raw)
    }

    static var autoSubmitPhoto: Bool {
        ProcessInfo.processInfo.environment["UITEST_AUTO_SUBMIT_IMAGE_DOMAIN_PHOTO"] == "1"
    }

    static var autoSubmitCorrection: Bool {
        ProcessInfo.processInfo.environment["UITEST_AUTO_SUBMIT_IMAGE_DOMAIN_CORRECTION"] == "1"
    }
}

enum ImageDomainUITestFixtures {
    static func interpretGymPhoto(
        request: AIInterpretGymPhotoRequest,
        scenario: ImageDomainUITestScenario
    ) -> AIInterpretGymPhotoResponse {
        switch scenario {
        case .mealViaGymPhoto:
            return mealClassificationResponse
        case .gymViaMealPhoto, .partialGymWeight:
            return gymEquipmentResponse(
                exerciseID: GymExerciseID.legPress.rawValue,
                weight: scenario == .partialGymWeight ? nil : 90
            )
        case .wrongGymArtifact:
            return gymEquipmentResponse(
                exerciseID: GymExerciseID.legPress.rawValue,
                weight: nil
            )
        case .ambiguousImage:
            return AIInterpretGymPhotoResponse(
                schemaVersion: 1,
                exerciseCandidates: [],
                detectedWeight: nil,
                limitations: ["Could not tell whether this is food or gym equipment."],
                requiresConfirmation: true,
                contentType: .ambiguous,
                classificationConfidence: 0.35,
                classificationReason: "Is this a meal you want to log, or gym equipment for your workout?",
                containsFood: false,
                containsGymEquipment: false
            )
        }
    }

    static func interpretMeal(
        request: AIInterpretMealRequest,
        scenario: ImageDomainUITestScenario
    ) -> AIInterpretMealResponse {
        switch scenario {
        case .gymViaMealPhoto:
            return AIInterpretMealResponse(
                interpretedMeals: [],
                uiNotes: nil,
                contentType: .gymEquipment,
                classificationConfidence: 0.94,
                classificationReason: "Leg press machine visible.",
                containsFood: false,
                containsGymEquipment: true
            )
        case .mealViaGymPhoto, .wrongGymArtifact:
            return saladMealResponse
        case .partialGymWeight, .ambiguousImage:
            return saladMealResponse
        }
    }

    private static var mealClassificationResponse: AIInterpretGymPhotoResponse {
        AIInterpretGymPhotoResponse(
            schemaVersion: 1,
            exerciseCandidates: [],
            detectedWeight: nil,
            limitations: ["Food and drinks visible on the table."],
            requiresConfirmation: true,
            contentType: .meal,
            classificationConfidence: 0.97,
            classificationReason: "Salad bowl and drinks visible.",
            containsFood: true,
            containsGymEquipment: false
        )
    }

    private static var saladMealResponse: AIInterpretMealResponse {
        AIInterpretMealResponse(
            interpretedMeals: [
                AIInterpretedMeal(
                    label: "Garden salad bowl",
                    timing: "lunch",
                    eatenAtGuessISO8601: nil,
                    items: [
                        AIInterpretedMealItem(
                            name: "Salad",
                            amount: 250,
                            unit: "g",
                            calories: 220,
                            proteinGrams: 8,
                            carbsGrams: 18,
                            fatGrams: 12,
                            fiberGrams: 6
                        ),
                    ],
                    calories: 220,
                    proteinGrams: 8,
                    carbsGrams: 18,
                    fatGrams: 12,
                    confidence: 0.88,
                    alternatives: []
                ),
            ],
            uiNotes: nil,
            contentType: .meal,
            classificationConfidence: 0.88,
            classificationReason: "Salad bowl visible.",
            containsFood: true,
            containsGymEquipment: false
        )
    }

    private static func gymEquipmentResponse(exerciseID: String, weight: Double?) -> AIInterpretGymPhotoResponse {
        AIInterpretGymPhotoResponse(
            schemaVersion: 1,
            exerciseCandidates: [
                AIInterpretGymExerciseCandidate(
                    exerciseID: exerciseID,
                    confidence: 0.9,
                    reason: "Machine label matches \(exerciseID)"
                ),
            ],
            detectedWeight: weight.map {
                AIInterpretGymDetectedWeight(
                    value: $0,
                    unit: "kg",
                    confidence: 0.8,
                    reason: "Selector pin visible"
                )
            },
            limitations: weight == nil ? ["Weight label not visible"] : [],
            requiresConfirmation: true,
            contentType: .gymEquipment,
            classificationConfidence: 0.92,
            classificationReason: "Gym equipment visible.",
            containsFood: false,
            containsGymEquipment: true
        )
    }
}
