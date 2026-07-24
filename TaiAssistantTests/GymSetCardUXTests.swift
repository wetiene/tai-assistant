import XCTest
@testable import TaiAssistant

@MainActor
final class GymSetCardUXTests: XCTestCase {
    private func sampleOptions() -> [GymTemplateExerciseOption] {
        [
            GymTemplateExerciseOption(exerciseID: GymExerciseID.legPress.rawValue, displayName: "Leg Press", isOptional: false),
            GymTemplateExerciseOption(exerciseID: GymExerciseID.legExtension.rawValue, displayName: "Leg Extension", isOptional: false),
        ]
    }

    func testSaveDisabledUntilExerciseWeightAndRepsAreValid() {
        let options = sampleOptions()
        XCTAssertFalse(
            GymSetCardValidation.canSave(
                selectedExerciseID: "",
                templateExerciseOptions: options,
                weightValue: 40,
                repetitions: 10,
                isSaved: false
            )
        )
        XCTAssertFalse(
            GymSetCardValidation.canSave(
                selectedExerciseID: GymExerciseID.legPress.rawValue,
                templateExerciseOptions: options,
                weightValue: nil,
                repetitions: 10,
                isSaved: false
            )
        )
        XCTAssertFalse(
            GymSetCardValidation.canSave(
                selectedExerciseID: GymExerciseID.legPress.rawValue,
                templateExerciseOptions: options,
                weightValue: 40,
                repetitions: nil,
                isSaved: false
            )
        )
        XCTAssertTrue(
            GymSetCardValidation.canSave(
                selectedExerciseID: GymExerciseID.legPress.rawValue,
                templateExerciseOptions: options,
                weightValue: 40,
                repetitions: 10,
                isSaved: false
            )
        )
    }

    func testUnknownExerciseIDCannotSave() {
        let options = sampleOptions()
        XCTAssertFalse(
            GymSetCardValidation.canSave(
                selectedExerciseID: "unknownMachine",
                templateExerciseOptions: options,
                weightValue: 50,
                repetitions: 8,
                isSaved: false
            )
        )
    }

    func testInterpretationFiltersUnknownExerciseCandidates() async throws {
        let gym = GymCapabilityController(
            workoutRepository: MockWorkoutRepository(),
            aiService: FilteringGymAIService(),
            ownerID: "ux.test"
        )
        _ = try await gym.startWorkout(templateID: .lowerBody)

        let outcome = await gym.interpretCurrentSet(
            photoJPEG: Data("fake-jpeg".utf8),
            localeIdentifier: "en_AU",
            weightUnitPreference: "kg"
        )
        guard case .success(let success) = outcome else {
            return XCTFail("Expected interpretation success")
        }

        XCTAssertTrue(success.draft.selectedExerciseID.isEmpty)
        XCTAssertTrue(success.draft.interpretation.exerciseCandidates.isEmpty)
        XCTAssertNil(success.draft.weightValue)
    }

    func testDraftChangeUpdatesOnlyPendingSetDraft() async throws {
        let gym = GymCapabilityController(
            workoutRepository: MockWorkoutRepository(),
            aiService: MockAIService(),
            ownerID: "ux.test"
        )
        _ = try await gym.startWorkout(templateID: .lowerBody)
        let outcome = await gym.interpretCurrentSet(
            photoJPEG: Data("fake-jpeg".utf8),
            localeIdentifier: "en_AU",
            weightUnitPreference: "kg"
        )
        guard case .success(let success) = outcome else {
            return XCTFail("Expected interpretation success")
        }

        var draft = success.draft
        let originalExercise = draft.selectedExerciseID
        draft.selectedExerciseID = GymExerciseID.legExtension.rawValue
        draft.selectedExerciseName = GymExerciseID.legExtension.displayName
        draft.weightValue = 55
        draft.repetitions = 12
        gym.updatePendingDraft(draft)

        XCTAssertEqual(gym.pendingSetDraft?.selectedExerciseID, GymExerciseID.legExtension.rawValue)
        XCTAssertNotEqual(gym.pendingSetDraft?.selectedExerciseID, originalExercise)
        XCTAssertEqual(gym.pendingSetDraft?.weightValue, 55)
        XCTAssertEqual(gym.pendingSetDraft?.repetitions, 12)
    }

    func testViewModelDraftChangeSyncsPendingDraft() async throws {
        let store = ConversationSessionStore()
        let gym = GymCapabilityController(
            workoutRepository: MockWorkoutRepository(),
            aiService: MockAIService(),
            ownerID: "ux.test"
        )
        let vm = ConversationViewModel(
            store: store,
            meal: MealCapabilityController(
                mealRepository: MockMealRepository(),
                ownerID: "ux.test",
                interpreter: MockCheckInInterpreter()
            ),
            gym: gym,
            strengthConversation: ConversationTestSupport.makeStrengthConversation(ownerID: "ux.test"),
            liveTai: ConversationTestSupport.makeLiveTai(ownerID: "ux.test"),
            gymPlanRepository: MockGymPlanRepository(),
            ownerID: "ux.test",
            assistantName: "Tai"
        )

        _ = try await gym.startWorkout(templateID: .lowerBody)
        let outcome = await gym.interpretCurrentSet(
            photoJPEG: Data("fake-jpeg".utf8),
            localeIdentifier: "en_AU",
            weightUnitPreference: "kg"
        )
        guard case .success(let success) = outcome, let session = gym.session else {
            return XCTFail("Expected interpretation success with active session")
        }

        var payload = GymCapabilityController.setCardPayload(from: success.draft, session: session)
        let card = GymSetConfirmationCardCodec.makeCard(payload: payload, interactive: true)
        store.append(ConversationMessage(actor: .assistant, card: card))

        payload.weightValue = 62
        payload.repetitions = 9
        vm.handleGymSetDraftChange(cardID: card.id, payload: payload)

        XCTAssertEqual(gym.pendingSetDraft?.weightValue, 62)
        XCTAssertEqual(gym.pendingSetDraft?.repetitions, 9)
    }
}

private struct FilteringGymAIService: AIService {
    func send(message: String, context: [String: String]) async throws -> String {
        try await MockAIService().send(message: message, context: context)
    }

    func interpretMeal(request: AIInterpretMealRequest) async throws -> AIInterpretMealResponse {
        try await MockAIService().interpretMeal(request: request)
    }

    func interpretGoal(request: AIInterpretGoalRequest) async throws -> AIInterpretGoalResponse {
        try await MockAIService().interpretGoal(request: request)
    }

    func interpretGymPhoto(request: AIInterpretGymPhotoRequest) async throws -> AIInterpretGymPhotoResponse {
        AIInterpretGymPhotoResponse(
            schemaVersion: 1,
            exerciseCandidates: [
                AIInterpretGymExerciseCandidate(
                    exerciseID: "notInTemplate",
                    confidence: 0.91,
                    reason: "Unknown machine label"
                ),
            ],
            detectedWeight: nil,
            limitations: ["Weight plate not visible"],
            requiresConfirmation: true,
            contentType: .gymEquipment,
            classificationConfidence: 0.55,
            classificationReason: "Possible gym equipment, but it does not match the planned workout.",
            containsFood: false,
            containsGymEquipment: true
        )
    }

    func interpretWorkoutPlan(request: AIInterpretWorkoutPlanRequest) async throws -> AIInterpretWorkoutPlanResponse {
        try await MockAIService().interpretWorkoutPlan(request: request)
    }

    func coach(request: AICoachRequest) async throws -> AICoachResponse {
        try await MockAIService().coach(request: request)
    }
}
