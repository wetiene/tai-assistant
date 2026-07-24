import XCTest
@testable import TaiAssistant

@MainActor
final class ImageDomainClassificationTests: XCTestCase {
    private let ownerID = "image.domain.tests"

    override func setUp() {
        super.setUp()
        ConversationAttachmentStore.shared = .makeEphemeralForTests()
        AIDataProcessingConsentStore.resetForTests()
        AIDataProcessingConsentStore.accept(version: AIDataProcessingConsentStore.gymPhotoVersion)
        AIDataProcessingConsentStore.accept(version: AIDataProcessingConsentStore.mealAndGoalVersion)
    }

    override func tearDown() {
        AIDataProcessingConsentStore.resetForTests()
        super.tearDown()
    }

    func testMealSubmittedThroughGymRouteDoesNotCreatePhotoReview() async throws {
        let mealPhotoAI = ConfigurableGymPhotoAIService(
            response: AIInterpretGymPhotoResponse(
                schemaVersion: 1,
                exerciseCandidates: [],
                detectedWeight: nil,
                limitations: ["Food and drinks visible on the table."],
                requiresConfirmation: true,
                contentType: .meal,
                classificationConfidence: 0.97,
                classificationReason: "The image shows a salad bowl and drinks.",
                containsFood: true,
                containsGymEquipment: false
            )
        )
        let store = ConversationSessionStore()
        let (vm, _) = ConversationTestSupport.makeViewModel(
            store: store,
            workoutRepository: MockWorkoutRepository(),
            aiService: mealPhotoAI,
            ownerID: ownerID
        )
        await vm.beginConversationalStrengthWorkout(
            target: GymPlanWorkoutTarget(reference: .starter(.lowerBody), sectionIndex: 0)
        )
        vm.appendPendingPhotos([Data("salad-photo".utf8)])
        await vm.sendComposer()

        XCTAssertFalse(
            store.active.messages.contains {
                $0.card?.typeID == StrengthConversationCapabilityID.photoReviewCardType
                    && ($0.card?.isInteractive == true)
            }
        )
        XCTAssertTrue(
            store.active.messages.contains {
                $0.card?.typeID == MealCapabilityID.estimateCardType
                    && ($0.card?.isInteractive == true)
            }
        )
    }

    func testContradictoryGymResponseIsRejected() {
        let response = AIInterpretGymPhotoResponse(
            schemaVersion: 1,
            exerciseCandidates: [
                AIInterpretGymExerciseCandidate(
                    exerciseID: GymExerciseID.seatedShoulderPress.rawValue,
                    confidence: 0.9,
                    reason: "Seated shoulder press machine"
                ),
            ],
            detectedWeight: nil,
            limitations: ["No exercise machine or weight stack is visible. Image shows food and beverages."],
            requiresConfirmation: true,
            contentType: .gymEquipment,
            classificationConfidence: 0.9,
            classificationReason: "Seated shoulder press machine visible.",
            containsFood: true,
            containsGymEquipment: false
        )

        let result = ImageInterpretationValidator.validateGymResponse(response)
        guard case .failure(.contradictory) = result else {
            return XCTFail("Expected contradictory failure, got \(result)")
        }
    }

    func testWeightVisibilityLimitationDoesNotRejectGymEquipment() {
        let response = AIInterpretGymPhotoResponse(
            schemaVersion: 1,
            exerciseCandidates: [
                AIInterpretGymExerciseCandidate(
                    exerciseID: GymExerciseID.legPress.rawValue,
                    confidence: 0.9,
                    reason: "Leg press stack visible"
                ),
            ],
            detectedWeight: nil,
            limitations: ["Weight label not visible"],
            requiresConfirmation: true,
            contentType: .gymEquipment,
            classificationConfidence: 0.9,
            classificationReason: "Leg press machine visible.",
            containsFood: false,
            containsGymEquipment: true
        )

        let result = ImageInterpretationValidator.validateGymResponse(response)
        guard case .success = result else {
            return XCTFail("Expected partial-evidence gym response to pass, got \(result)")
        }
    }

    func testBogusEquipmentMealIsRejected() {
        let response = AIInterpretMealResponse(
            interpretedMeals: [
                AIInterpretedMeal(
                    label: "Gym cable machine / exercise equipment",
                    timing: "other",
                    eatenAtGuessISO8601: nil,
                    items: [],
                    calories: 0,
                    proteinGrams: 0,
                    carbsGrams: 0,
                    fatGrams: 0,
                    confidence: 0.99,
                    alternatives: []
                ),
            ],
            uiNotes: nil,
            contentType: .meal,
            classificationConfidence: 0.99,
            classificationReason: "Equipment visible.",
            containsFood: false,
            containsGymEquipment: true
        )

        let result = ImageInterpretationValidator.validateMealResponse(response, requiresImageClassification: true)
        guard case .failure = result else {
            return XCTFail("Expected meal validation failure")
        }
    }

    func testMealCorrectionSupersedesGymPhotoReview() async throws {
        let gymAI = ConfigurableGymPhotoAIService(
            response: AIInterpretGymPhotoResponse(
                schemaVersion: 1,
                exerciseCandidates: [
                    AIInterpretGymExerciseCandidate(
                        exerciseID: GymExerciseID.seatedShoulderPress.rawValue,
                        confidence: 0.9,
                        reason: "Machine label"
                    ),
                ],
                detectedWeight: nil,
                limitations: [],
                requiresConfirmation: true,
                contentType: .gymEquipment,
                classificationConfidence: 0.9,
                classificationReason: "Shoulder press machine.",
                containsFood: false,
                containsGymEquipment: true
            )
        )
        let store = ConversationSessionStore()
        let (vm, _) = ConversationTestSupport.makeViewModel(
            store: store,
            workoutRepository: MockWorkoutRepository(),
            aiService: gymAI,
            ownerID: ownerID
        )
        await vm.beginConversationalStrengthWorkout(
            target: GymPlanWorkoutTarget(reference: .starter(.upperBody), sectionIndex: 0)
        )
        vm.appendPendingPhotos([Data("salad-photo".utf8)])
        await vm.sendComposer()

        guard let gymCard = store.active.messages.last(where: {
            $0.card?.typeID == StrengthConversationCapabilityID.photoReviewCardType
        })?.card else {
            return XCTFail("Missing gym review card")
        }
        XCTAssertTrue(gymCard.isInteractive)

        store.updateComposer { $0.text = "That's my lunch" }
        await vm.sendComposer()

        let interactiveGymCards = store.active.messages.filter {
            $0.card?.typeID == StrengthConversationCapabilityID.photoReviewCardType && $0.card?.isInteractive == true
        }
        XCTAssertTrue(interactiveGymCards.isEmpty)

        let interactiveMealCards = store.active.messages.filter {
            $0.card?.typeID == MealCapabilityID.estimateCardType && $0.card?.isInteractive == true
        }
        XCTAssertEqual(interactiveMealCards.count, 1)
    }

    func testMissingContentTypeFailsValidation() {
        let response = AIInterpretGymPhotoResponse(
            schemaVersion: 1,
            exerciseCandidates: [],
            detectedWeight: nil,
            limitations: [],
            requiresConfirmation: true
        )
        let result = ImageInterpretationValidator.validateGymResponse(response)
        guard case .failure(.missingClassification) = result else {
            return XCTFail("Expected missing classification")
        }
    }

    func testCorrectionClassifierDetectsLunchPhrase() {
        XCTAssertEqual(
            ImageDomainCorrectionClassifier.detect(in: "That's my lunch"),
            .reclassifyAsMeal
        )
        XCTAssertEqual(
            ImageDomainCorrectionClassifier.detect(in: "That's the machine"),
            .reclassifyAsGym
        )
    }

    func testGymImageSubmittedThroughMealRouteDoesNotCreateMealEstimate() async throws {
        let mealAI = ConfigurableMealPhotoAIService(
            response: AIInterpretMealResponse(
                interpretedMeals: [],
                uiNotes: nil,
                contentType: .gymEquipment,
                classificationConfidence: 0.94,
                classificationReason: "Seated shoulder press machine and weight stack visible.",
                containsFood: false,
                containsGymEquipment: true
            )
        )
        let store = ConversationSessionStore()
        let (vm, _) = ConversationTestSupport.makeViewModel(
            store: store,
            interpreter: AIServiceCheckInInterpreter(aiService: mealAI, ownerID: ownerID),
            aiService: mealAI,
            ownerID: ownerID
        )
        vm.startIfNeeded()
        vm.appendPendingPhotos([Data("gym-machine-photo".utf8)])
        await vm.sendComposer()

        XCTAssertFalse(
            store.active.messages.contains {
                $0.card?.typeID == MealCapabilityID.estimateCardType
                    && ($0.card?.isInteractive == true)
            }
        )
        XCTAssertFalse(
            store.active.messages.contains {
                $0.card?.typeID == StrengthConversationCapabilityID.photoReviewCardType
                    && ($0.card?.isInteractive == true)
            }
        )
    }

    func testMealInterpretationRejectsExplicitGymClassification() {
        let response = AIInterpretMealResponse(
            interpretedMeals: [],
            uiNotes: nil,
            contentType: .gymEquipment,
            classificationConfidence: 0.94,
            classificationReason: "Leg press machine visible.",
            containsFood: false,
            containsGymEquipment: true
        )

        let result = ImageInterpretationValidator.validateMealResponse(
            response,
            requiresImageClassification: true
        )
        guard case .failure(.wrongDomain(_, let actual, _)) = result, actual == .gymEquipment else {
            return XCTFail("Expected gym equipment wrong-domain failure, got \(result)")
        }
    }

    func testGymCorrectionSupersedesMealEstimate() async throws {
        let mealMisroute = AIInterpretGymPhotoResponse(
            schemaVersion: 1,
            exerciseCandidates: [],
            detectedWeight: nil,
            limitations: ["Food visible on table."],
            requiresConfirmation: true,
            contentType: .meal,
            classificationConfidence: 0.9,
            classificationReason: "Salad bowl visible.",
            containsFood: true,
            containsGymEquipment: false
        )
        let gymMatch = AIInterpretGymPhotoResponse(
            schemaVersion: 1,
            exerciseCandidates: [
                AIInterpretGymExerciseCandidate(
                    exerciseID: GymExerciseID.legPress.rawValue,
                    confidence: 0.9,
                    reason: "Leg press stack visible"
                ),
            ],
            detectedWeight: nil,
            limitations: [],
            requiresConfirmation: true,
            contentType: .gymEquipment,
            classificationConfidence: 0.94,
            classificationReason: "Leg press machine visible.",
            containsFood: false,
            containsGymEquipment: true
        )
        let gymAI = ConfigurableGymPhotoAIService(response: mealMisroute)
        let store = ConversationSessionStore()
        let (vm, _) = ConversationTestSupport.makeViewModel(
            store: store,
            workoutRepository: MockWorkoutRepository(),
            aiService: gymAI,
            ownerID: ownerID
        )
        await vm.beginConversationalStrengthWorkout(
            target: GymPlanWorkoutTarget(reference: .starter(.lowerBody), sectionIndex: 0)
        )
        vm.appendPendingPhotos([Data("gym-machine-photo".utf8)])
        await vm.sendComposer()

        XCTAssertTrue(
            store.active.messages.contains {
                $0.card?.typeID == MealCapabilityID.estimateCardType && $0.card?.isInteractive == true
            }
        )

        gymAI.response = gymMatch
        store.updateComposer { $0.text = "That's the machine" }
        await vm.sendComposer()

        let interactiveMealCards = store.active.messages.filter {
            $0.card?.typeID == MealCapabilityID.estimateCardType && $0.card?.isInteractive == true
        }
        XCTAssertTrue(interactiveMealCards.isEmpty)

        let interactiveGymCards = store.active.messages.filter {
            $0.card?.typeID == StrengthConversationCapabilityID.photoReviewCardType && $0.card?.isInteractive == true
        }
        XCTAssertEqual(interactiveGymCards.count, 1)
    }

    func testAmbiguousGymPhotoDoesNotCreateActionableCards() async throws {
        let ai = ConfigurableGymPhotoAIService(
            response: AIInterpretGymPhotoResponse(
                schemaVersion: 1,
                exerciseCandidates: [],
                detectedWeight: nil,
                limitations: ["Image is too blurry to classify."],
                requiresConfirmation: true,
                contentType: .ambiguous,
                classificationConfidence: 0.35,
                classificationReason: "Could not tell whether this is food or gym equipment.",
                containsFood: false,
                containsGymEquipment: false
            )
        )
        let store = ConversationSessionStore()
        let (vm, _) = ConversationTestSupport.makeViewModel(
            store: store,
            workoutRepository: MockWorkoutRepository(),
            aiService: ai,
            ownerID: ownerID
        )
        await vm.beginConversationalStrengthWorkout(
            target: GymPlanWorkoutTarget(reference: .starter(.lowerBody), sectionIndex: 0)
        )
        vm.appendPendingPhotos([Data("blurry-photo".utf8)])
        await vm.sendComposer()

        XCTAssertFalse(
            store.active.messages.contains {
                ($0.card?.typeID == StrengthConversationCapabilityID.photoReviewCardType
                    || $0.card?.typeID == MealCapabilityID.estimateCardType)
                    && ($0.card?.isInteractive == true)
            }
        )
        XCTAssertTrue(
            store.active.messages.contains {
                $0.actor == .assistant
                    && ($0.text?.contains("meal") == true || $0.text?.contains("gym") == true)
            }
        )
    }

    func testUnsupportedGymPhotoDoesNotCreateActionableCards() async throws {
        let ai = ConfigurableGymPhotoAIService(
            response: AIInterpretGymPhotoResponse(
                schemaVersion: 1,
                exerciseCandidates: [],
                detectedWeight: nil,
                limitations: ["Blank or unreadable image."],
                requiresConfirmation: true,
                contentType: .unsupported,
                classificationConfidence: 0.1,
                classificationReason: "No usable visual content.",
                containsFood: false,
                containsGymEquipment: false
            )
        )
        let store = ConversationSessionStore()
        let (vm, _) = ConversationTestSupport.makeViewModel(
            store: store,
            workoutRepository: MockWorkoutRepository(),
            aiService: ai,
            ownerID: ownerID
        )
        await vm.beginConversationalStrengthWorkout(
            target: GymPlanWorkoutTarget(reference: .starter(.lowerBody), sectionIndex: 0)
        )
        vm.appendPendingPhotos([Data("blank-photo".utf8)])
        await vm.sendComposer()

        XCTAssertFalse(
            store.active.messages.contains {
                ($0.card?.typeID == StrengthConversationCapabilityID.photoReviewCardType
                    || $0.card?.typeID == MealCapabilityID.estimateCardType)
                    && ($0.card?.isInteractive == true)
            }
        )
    }

    func testCorrectionSupersessionSurvivesPersist() async throws {
        let container = AppModelContainerFactory.makeContainer(inMemory: true)
        let repo = LocalSwiftDataActiveConversationRepository(container: container)
        let store = ConversationSessionStore()
        store.onPersist = { try? repo.saveActive($0, ownerID: self.ownerID) }

        let gymAI = ConfigurableGymPhotoAIService(
            response: AIInterpretGymPhotoResponse(
                schemaVersion: 1,
                exerciseCandidates: [
                    AIInterpretGymExerciseCandidate(
                        exerciseID: GymExerciseID.seatedShoulderPress.rawValue,
                        confidence: 0.9,
                        reason: "Machine label"
                    ),
                ],
                detectedWeight: nil,
                limitations: [],
                requiresConfirmation: true,
                contentType: .gymEquipment,
                classificationConfidence: 0.9,
                classificationReason: "Shoulder press machine.",
                containsFood: false,
                containsGymEquipment: true
            )
        )
        let (vm, _) = ConversationTestSupport.makeViewModel(
            store: store,
            workoutRepository: MockWorkoutRepository(),
            aiService: gymAI,
            ownerID: ownerID
        )
        await vm.beginConversationalStrengthWorkout(
            target: GymPlanWorkoutTarget(reference: .starter(.upperBody), sectionIndex: 0)
        )
        vm.appendPendingPhotos([Data("salad-photo".utf8)])
        await vm.sendComposer()

        store.updateComposer { $0.text = "That's my lunch" }
        await vm.sendComposer()

        let liveInteractiveMeal = store.active.messages.filter {
            $0.card?.typeID == MealCapabilityID.estimateCardType && $0.card?.isInteractive == true
        }
        XCTAssertEqual(liveInteractiveMeal.count, 1)

        try repo.saveActive(store.snapshotIncludingComposer, ownerID: ownerID)
        let loaded = try repo.loadOrCreateActive(ownerID: ownerID)
        let interactiveGym = loaded.messages.filter {
            $0.card?.typeID == StrengthConversationCapabilityID.photoReviewCardType && $0.card?.isInteractive == true
        }
        let interactiveMeal = loaded.messages.filter {
            $0.card?.typeID == MealCapabilityID.estimateCardType && $0.card?.isInteractive == true
        }
        XCTAssertTrue(interactiveGym.isEmpty)
        XCTAssertEqual(interactiveMeal.count, 1)
        XCTAssertTrue(
            loaded.messages.contains {
                $0.card?.typeID == StrengthConversationCapabilityID.photoReviewCardType && $0.card?.isInteractive == false
            }
        )
    }

    func testMealClassificationRestoresAsActionableMealOnly() throws {
        let snapshot = MealEstimateSnapshot(
            draft: CheckInMealDraft(
                id: UUID(),
                label: "Garden salad bowl",
                timing: .lunch,
                eatenAt: .now,
                calories: 220,
                proteinGrams: 8,
                carbsGrams: 18,
                fatGrams: 12,
                confidence: 0.88,
                alternatives: [],
                items: []
            )
        )
        let payload = MealEstimateCardPayload(
            draft: snapshot,
            refinementAccepted: false,
            isLogged: false,
            imageClassification: PersistedImageClassification(contentType: .meal, containsFood: true)
        )
        let repo = makePersistenceRepo()
        try repo.saveActive(
            ActiveConversation(
                messages: [
                    ConversationMessage(
                        actor: .assistant,
                        card: MealCardCodec.makeCard(payload: payload, interactive: true)
                    ),
                ],
                activity: .awaitingUser
            ),
            ownerID: ownerID
        )

        let loaded = try repo.loadOrCreateActive(ownerID: ownerID)
        XCTAssertTrue(loaded.messages.first?.card?.isInteractive == true)
        XCTAssertEqual(
            MealCardCodec.decode(loaded.messages.first?.card?.payload ?? Data())?.imageClassification?.contentType,
            .meal
        )
    }

    func testGymClassificationRestoresAsActionableGymReviewOnly() throws {
        let payload = sampleGymReviewPayload(
            classification: PersistedImageClassification(contentType: .gymEquipment, containsGymEquipment: true)
        )
        let repo = makePersistenceRepo()
        try repo.saveActive(
            ActiveConversation(
                messages: [
                    ConversationMessage(
                        actor: .assistant,
                        card: StrengthPhotoReviewCardCodec.makeCard(payload: payload, interactive: true)
                    ),
                ],
                activity: .awaitingUser
            ),
            ownerID: ownerID
        )

        let loaded = try repo.loadOrCreateActive(ownerID: ownerID)
        XCTAssertTrue(
            loaded.messages.contains {
                $0.card?.typeID == StrengthConversationCapabilityID.photoReviewCardType
                    && $0.card?.isInteractive == true
            }
        )
        let decoded = StrengthPhotoReviewCardCodec.decode(
            loaded.messages.first?.card?.payload ?? Data()
        )
        XCTAssertEqual(decoded?.imageClassification?.contentType, .gymEquipment)
        XCTAssertNil(decoded?.suggestedWeight)
    }

    func testLegacyPhotoReviewWithoutClassificationIsNonActionableAfterRestore() throws {
        let legacyPayload = StrengthPhotoReviewCardPayload(
            reviewID: UUID(),
            sessionID: UUID(),
            detectedExerciseID: GymExerciseID.legPress.rawValue,
            detectedExerciseName: "Leg Press",
            suggestedWeight: nil,
            weightUnit: "kg",
            suggestedReps: 10,
            interpretation: .empty,
            photoCount: 1,
            isApplied: false,
            imageClassification: nil
        )
        let repo = makePersistenceRepo()
        try repo.saveActive(
            ActiveConversation(
                messages: [
                    ConversationMessage(
                        actor: .assistant,
                        card: StrengthPhotoReviewCardCodec.makeCard(payload: legacyPayload, interactive: true)
                    ),
                ],
                activity: .awaitingUser
            ),
            ownerID: ownerID
        )

        let loaded = try repo.loadOrCreateActive(ownerID: ownerID)
        XCTAssertFalse(loaded.messages.first?.card?.isInteractive ?? true)
    }

    func testWrongDomainMealClassificationOnGymReviewIsNonActionableAfterRestore() throws {
        let payload = sampleGymReviewPayload(
            classification: PersistedImageClassification(contentType: .meal, containsFood: true)
        )
        let repo = makePersistenceRepo()
        try repo.saveActive(
            ActiveConversation(
                messages: [
                    ConversationMessage(
                        actor: .assistant,
                        card: StrengthPhotoReviewCardCodec.makeCard(payload: payload, interactive: true)
                    ),
                ],
                activity: .awaitingUser
            ),
            ownerID: ownerID
        )

        let loaded = try repo.loadOrCreateActive(ownerID: ownerID)
        XCTAssertFalse(loaded.messages.first?.card?.isInteractive ?? true)
    }

    func testStructuralContradictionRejectsDespiteBenignLimitationsWording() {
        let response = AIInterpretGymPhotoResponse(
            schemaVersion: 1,
            exerciseCandidates: [
                AIInterpretGymExerciseCandidate(
                    exerciseID: GymExerciseID.legPress.rawValue,
                    confidence: 0.9,
                    reason: "Selector pin obscured but machine label readable"
                ),
            ],
            detectedWeight: nil,
            limitations: ["Weight not visible", "Selector pin obscured", "Label unreadable"],
            requiresConfirmation: true,
            contentType: .gymEquipment,
            classificationConfidence: 0.9,
            classificationReason: "Leg press machine visible.",
            containsFood: false,
            containsGymEquipment: true
        )

        let result = ImageInterpretationValidator.validateGymResponse(response)
        guard case .success = result else {
            return XCTFail("Expected valid gym classification with partial weight evidence, got \(result)")
        }
    }

    private func makePersistenceRepo() -> LocalSwiftDataActiveConversationRepository {
        LocalSwiftDataActiveConversationRepository(
            container: AppModelContainerFactory.makeContainer(inMemory: true)
        )
    }

    private func sampleGymReviewPayload(
        classification: PersistedImageClassification
    ) -> StrengthPhotoReviewCardPayload {
        StrengthPhotoReviewCardPayload(
            reviewID: UUID(),
            sessionID: UUID(),
            detectedExerciseID: GymExerciseID.legPress.rawValue,
            detectedExerciseName: GymExerciseID.legPress.displayName,
            suggestedWeight: nil,
            weightUnit: "kg",
            suggestedReps: 10,
            interpretation: GymPhotoInterpretationSnapshot(
                exerciseCandidates: [
                    GymExerciseCandidateSnapshot(
                        exerciseID: GymExerciseID.legPress.rawValue,
                        displayName: GymExerciseID.legPress.displayName,
                        confidence: 0.9,
                        reason: "Leg press visible"
                    ),
                ],
                detectedWeight: nil,
                limitations: ["Weight label not visible"],
                requiresConfirmation: true
            ),
            photoCount: 1,
            isApplied: false,
            imageClassification: classification
        )
    }
}

private final class ConfigurableGymPhotoAIService: AIService {
    var response: AIInterpretGymPhotoResponse
    var scheduledResponses: [AIInterpretGymPhotoResponse] = []
    private let base = MockAIService()

    init(response: AIInterpretGymPhotoResponse) {
        self.response = response
    }

    func interpretGymPhoto(request: AIInterpretGymPhotoRequest) async throws -> AIInterpretGymPhotoResponse {
        if !scheduledResponses.isEmpty {
            return scheduledResponses.removeFirst()
        }
        return response
    }

    func send(message: String, context: [String: String]) async throws -> String {
        try await base.send(message: message, context: context)
    }

    func interpretMeal(request: AIInterpretMealRequest) async throws -> AIInterpretMealResponse {
        try await base.interpretMeal(request: request)
    }

    func coach(request: AICoachRequest) async throws -> AICoachResponse {
        try await base.coach(request: request)
    }

    func interpretGoal(request: AIInterpretGoalRequest) async throws -> AIInterpretGoalResponse {
        try await base.interpretGoal(request: request)
    }

    func interpretWorkoutPlan(request: AIInterpretWorkoutPlanRequest) async throws -> AIInterpretWorkoutPlanResponse {
        try await base.interpretWorkoutPlan(request: request)
    }
}

private final class ConfigurableMealPhotoAIService: AIService {
    var response: AIInterpretMealResponse
    private let base = MockAIService()

    init(response: AIInterpretMealResponse) {
        self.response = response
    }

    func interpretMeal(request: AIInterpretMealRequest) async throws -> AIInterpretMealResponse {
        response
    }

    func interpretGymPhoto(request: AIInterpretGymPhotoRequest) async throws -> AIInterpretGymPhotoResponse {
        try await base.interpretGymPhoto(request: request)
    }

    func send(message: String, context: [String: String]) async throws -> String {
        try await base.send(message: message, context: context)
    }

    func coach(request: AICoachRequest) async throws -> AICoachResponse {
        try await base.coach(request: request)
    }

    func interpretGoal(request: AIInterpretGoalRequest) async throws -> AIInterpretGoalResponse {
        try await base.interpretGoal(request: request)
    }

    func interpretWorkoutPlan(request: AIInterpretWorkoutPlanRequest) async throws -> AIInterpretWorkoutPlanResponse {
        try await base.interpretWorkoutPlan(request: request)
    }
}

private final class DualRouteAIService: AIService {
    let mealService: ConfigurableMealPhotoAIService
    let gymService: ConfigurableGymPhotoAIService
    private let base = MockAIService()

    init(mealService: ConfigurableMealPhotoAIService, gymService: ConfigurableGymPhotoAIService) {
        self.mealService = mealService
        self.gymService = gymService
    }

    func interpretMeal(request: AIInterpretMealRequest) async throws -> AIInterpretMealResponse {
        try await mealService.interpretMeal(request: request)
    }

    func interpretGymPhoto(request: AIInterpretGymPhotoRequest) async throws -> AIInterpretGymPhotoResponse {
        try await gymService.interpretGymPhoto(request: request)
    }

    func send(message: String, context: [String: String]) async throws -> String {
        try await base.send(message: message, context: context)
    }

    func coach(request: AICoachRequest) async throws -> AICoachResponse {
        try await base.coach(request: request)
    }

    func interpretGoal(request: AIInterpretGoalRequest) async throws -> AIInterpretGoalResponse {
        try await base.interpretGoal(request: request)
    }

    func interpretWorkoutPlan(request: AIInterpretWorkoutPlanRequest) async throws -> AIInterpretWorkoutPlanResponse {
        try await base.interpretWorkoutPlan(request: request)
    }
}
