import XCTest
@testable import TaiAssistant

@MainActor
final class GymCapabilityConfirmationTests: XCTestCase {
    override func setUp() {
        super.setUp()
        AIDataProcessingConsentStore.resetForTests()
        AIDataProcessingConsentStore.accept(version: AIDataProcessingConsentStore.gymPhotoVersion)
    }

    override func tearDown() {
        AIDataProcessingConsentStore.resetForTests()
        super.tearDown()
    }

    func testStartWorkoutCreatesPersistedSession() async throws {
        let repo = MockWorkoutRepository()
        let gym = GymCapabilityController(
            workoutRepository: repo,
            aiService: MockAIService(),
            ownerID: "test.user"
        )

        let session = try await gym.startWorkout(templateID: .upperBody)
        XCTAssertEqual(session.title, "Upper Body")
        XCTAssertEqual(session.exercises.count, 6)
        XCTAssertEqual(gym.phase, .active)

        let inProgress = try await repo.fetchInProgressSession(ownerID: "test.user")
        XCTAssertEqual(inProgress?.id, session.sessionID)
    }

    func testInterpretAndSaveSetPersistsWorkoutSet() async throws {
        let repo = MockWorkoutRepository()
        let gym = GymCapabilityController(
            workoutRepository: repo,
            aiService: MockAIService(),
            ownerID: "test.user"
        )
        _ = try await gym.startWorkout(templateID: .lowerBody)

        let photo = Data("fake-jpeg".utf8)
        let outcome = await gym.interpretCurrentSet(
            photoJPEG: photo,
            localeIdentifier: "en_AU",
            weightUnitPreference: "kg"
        )
        guard case .success(let success) = outcome else {
            return XCTFail("Expected gym interpretation success")
        }

        guard let session = gym.session else {
            return XCTFail("Expected active gym session")
        }

        var payload = GymCapabilityController.setCardPayload(from: success.draft, session: session)
        payload.repetitions = 10
        XCTAssertTrue(payload.canSaveSet, "Mock AI should populate exercise and weight for save")

        let result = await gym.confirmAndSaveSet(payload: payload)
        guard case .success(let setLog) = result else {
            return XCTFail("Expected set save success")
        }
        XCTAssertEqual(setLog.repetitions, 10)
        XCTAssertGreaterThan(setLog.weightValue, 0)

        let bounds = NutritionDay.today().queryBounds()
        let sessions = try await repo.fetchSessions(
            ownerID: "test.user",
            from: bounds.start,
            to: bounds.end
        )
        XCTAssertEqual(sessions.first?.sets.count, 1)
    }

    func testUpperBodyIntentStartsWorkoutInConversation() async {
        let store = ConversationSessionStore()
        let (vm, _) = ConversationTestSupport.makeViewModel(store: store)
        vm.startIfNeeded()
        await vm.sendComposerWithTestHooks(text: "start upper body workout", photo: nil)

        XCTAssertTrue(
            store.active.messages.contains { $0.card?.typeID == GymCapabilityID.workoutPlanCardType }
        )
        XCTAssertTrue(gymHasActiveSession(from: store))
    }

    private func gymHasActiveSession(from store: ConversationSessionStore) -> Bool {
        if case let .capability(capabilityID, _, _) = store.active.activity {
            return capabilityID == GymCapabilityID.capability
        }
        return false
    }
}

@MainActor
private extension ConversationViewModel {
    func sendComposerWithTestHooks(text: String, photo: Data?) async {
        store.updateComposer {
            $0.text = text
            $0.pendingPhotoJPEG = photo
        }
        await sendComposer()
    }
}
