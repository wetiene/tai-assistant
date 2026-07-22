import XCTest
@testable import TaiAssistant

@MainActor
final class StrengthWorkoutEntryRoutingTests: XCTestCase {
    private let ownerID = "strength.routing.test"

    override func setUp() {
        super.setUp()
        AIDataProcessingConsentStore.resetForTests()
        AIDataProcessingConsentStore.accept(version: AIDataProcessingConsentStore.gymPhotoVersion)
    }

    override func tearDown() {
        AIDataProcessingConsentStore.resetForTests()
        super.tearDown()
    }

    func testConversationStartUsesStrengthPresentation() async {
        let repository = MockWorkoutRepository()
        let coordinator = StrengthWorkoutCoordinator(
            workoutRepository: repository,
            gymPlanRepository: MockGymPlanRepository(),
            ownerID: ownerID
        )
        var presented: StrengthWorkoutPresentation?
        let store = ConversationSessionStore()
        let (vm, _) = ConversationTestSupport.makeViewModel(
            store: store,
            workoutRepository: repository,
            ownerID: ownerID
        )
        vm.strengthWorkoutCoordinator = coordinator
        vm.onPresentStrengthWorkout = { presented = $0 }

        await vm.requestStartGymWorkout(
            target: GymPlanWorkoutTarget(reference: .starter(.upperBody), sectionIndex: 0)
        )

        XCTAssertNotNil(presented)
        XCTAssertEqual(presented?.source, .conversation)
        XCTAssertNil(presented?.resumeSession)
    }

    func testConversationResumeUsesStrengthPresentation() async {
        let repository = MockWorkoutRepository()
        let coordinator = StrengthWorkoutCoordinator(
            workoutRepository: repository,
            gymPlanRepository: MockGymPlanRepository(),
            ownerID: ownerID
        )
        var presented: StrengthWorkoutPresentation?
        let session = StrengthSessionBuilder.makeSession(
            plan: GymProgramTemplateLibrary.resolvableStarter(.upperBody),
            proposals: [],
            acceptedProposals: [:],
            historySessions: [],
            origin: .conversation,
            preFlightCompleted: true
        )
        try? await repository.createSession(
            WorkoutSessionLog(
                id: session.sessionID,
                ownerID: ownerID,
                templateID: session.planReference.storageKey,
                title: session.title,
                statusRaw: GymWorkoutSessionStatus.inProgress.rawValue,
                activeSessionJSON: try StrengthSessionPersistence.encode(session)
            )
        )

        let store = ConversationSessionStore()
        let (vm, _) = ConversationTestSupport.makeViewModel(
            store: store,
            workoutRepository: repository,
            ownerID: ownerID
        )
        vm.strengthWorkoutCoordinator = coordinator
        vm.onPresentStrengthWorkout = { presented = $0 }

        vm.applyGymIntent(resume: true)
        try? await Task.sleep(nanoseconds: 200_000_000)

        XCTAssertNotNil(presented)
        XCTAssertEqual(presented?.resumeSession?.sessionID, session.sessionID)
    }

    func testCannotCreateSecondActiveWorkout() async throws {
        let repository = MockWorkoutRepository()
        let controller = StrengthWorkoutController(workoutRepository: repository, ownerID: ownerID)
        let plan = GymProgramTemplateLibrary.resolvableStarter(.upperBody)
        let prepared = controller.prepareSession(
            plan: plan,
            proposals: [],
            acceptedProposals: [:],
            historySessions: []
        )
        try await controller.startSession(prepared)

        let second = controller.prepareSession(
            plan: GymProgramTemplateLibrary.resolvableStarter(.lowerBody),
            proposals: [],
            acceptedProposals: [:],
            historySessions: []
        )
        do {
            try await controller.startSession(second)
            XCTFail("Expected active session error")
        } catch StrengthWorkoutStartError.activeSessionInProgress {
            XCTAssertTrue(true)
        }
    }

    func testRestoredSessionPreservesAcceptedProposal() throws {
        let exerciseID = GymExerciseID.supineChestPress.rawValue
        let proposal = StrengthProgressionProposal(
            exerciseID: exerciseID,
            exerciseName: "Chest Press",
            currentWeight: 40,
            proposedWeight: 42.5,
            decision: .increase,
            repRangeLower: 8,
            repRangeUpper: 10,
            reasoning: StrengthProgressionReasoning(
                observation: "obs",
                rule: "rule",
                recommendation: "rec",
                targetRepsLabel: "8–10",
                fallback: "fb"
            ),
            confidence: .high,
            weightUnit: "kg"
        )
        var session = StrengthSessionBuilder.makeSession(
            plan: GymProgramTemplateLibrary.resolvableStarter(.upperBody),
            proposals: [proposal],
            acceptedProposals: [
                exerciseID: StrengthAcceptedProposal(
                    exerciseID: exerciseID,
                    decision: .accepted,
                    weight: 42.5,
                    weightUnit: "kg",
                    originalProposal: proposal
                ),
            ],
            historySessions: [],
            preFlightCompleted: true
        )
        session.exercises[0].sets[0].confirmedWeight = 42.5
        session.exercises[0].sets[0].confirmedReps = 10
        session.exercises[0].sets[0].status = .confirmed

        let data = try StrengthSessionPersistence.encode(session)
        let restored = StrengthSessionPersistence.decodeStrength(from: data)
        XCTAssertEqual(restored?.acceptedProposals[exerciseID]?.weight, 42.5)
        XCTAssertEqual(restored?.exercises[0].sets[0].confirmedWeight, 42.5)
    }
}
