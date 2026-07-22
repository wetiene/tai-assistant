import XCTest
@testable import TaiAssistant

@MainActor
final class StrengthWorkoutConcurrencyTests: XCTestCase {
    private let ownerID = "strength.concurrency.test"

    func testRepositoryRejectsSecondInProgressSession() async throws {
        let container = try AppModelContainerFactory.makeContainer(inMemory: true)
        let repository = LocalSwiftDataWorkoutRepository(container: container)
        let controller = StrengthWorkoutController(workoutRepository: repository, ownerID: ownerID)
        let plan = GymProgramTemplateLibrary.resolvableStarter(.upperBody)
        let prepared = controller.prepareSession(
            plan: plan,
            proposals: [],
            acceptedProposals: [:],
            historySessions: []
        )
        try await controller.startSession(prepared)

        let second = StrengthWorkoutController(workoutRepository: repository, ownerID: ownerID)
        let secondPrepared = second.prepareSession(
            plan: GymProgramTemplateLibrary.resolvableStarter(.lowerBody),
            proposals: [],
            acceptedProposals: [:],
            historySessions: []
        )

        do {
            try await second.startSession(secondPrepared)
            XCTFail("Expected active session guard")
        } catch StrengthWorkoutStartError.activeSessionInProgress {
            XCTAssertTrue(true)
        }
    }

    func testConcurrentStartsCannotCreateDuplicateSessions() async throws {
        let repository = MockWorkoutRepository()
        let controller = StrengthWorkoutController(workoutRepository: repository, ownerID: ownerID)
        let upper = controller.prepareSession(
            plan: GymProgramTemplateLibrary.resolvableStarter(.upperBody),
            proposals: [],
            acceptedProposals: [:],
            historySessions: []
        )
        try await controller.startSession(upper)

        let secondController = StrengthWorkoutController(workoutRepository: repository, ownerID: ownerID)
        let lower = secondController.prepareSession(
            plan: GymProgramTemplateLibrary.resolvableStarter(.lowerBody),
            proposals: [],
            acceptedProposals: [:],
            historySessions: []
        )

        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<4 {
                group.addTask { @MainActor in
                    try? await secondController.startSession(lower)
                }
            }
        }

        let activeCount = try await repository.fetchSessions(
            ownerID: ownerID,
            from: .distantPast,
            to: .distantFuture
        ).filter { $0.status == .inProgress }.count
        XCTAssertEqual(activeCount, 1)
    }
}
