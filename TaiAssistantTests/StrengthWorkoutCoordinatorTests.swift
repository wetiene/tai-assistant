import XCTest
@testable import TaiAssistant

@MainActor
final class StrengthWorkoutCoordinatorTests: XCTestCase {
    private let ownerID = "strength.coordinator.test"

    func testDetectsActiveStrengthSession() async throws {
        let repository = MockWorkoutRepository()
        let coordinator = StrengthWorkoutCoordinator(
            workoutRepository: repository,
            gymPlanRepository: MockGymPlanRepository(),
            ownerID: ownerID
        )

        let session = StrengthSessionBuilder.makeSession(
            plan: GymProgramTemplateLibrary.resolvableStarter(.upperBody),
            proposals: [],
            acceptedProposals: [:],
            historySessions: [],
            origin: .home,
            preFlightCompleted: true
        )
        try await repository.createSession(
            WorkoutSessionLog(
                id: session.sessionID,
                ownerID: ownerID,
                templateID: session.planReference.storageKey,
                title: session.title,
                statusRaw: GymWorkoutSessionStatus.inProgress.rawValue,
                activeSessionJSON: try StrengthSessionPersistence.encode(session)
            )
        )

        let active = try await coordinator.fetchActiveWorkout()
        XCTAssertEqual(active?.sessionID, session.sessionID)
        XCTAssertTrue(active?.isStrengthSession == true)
    }

    func testDetectStartConflictForDifferentPlan() async throws {
        let repository = MockWorkoutRepository()
        let coordinator = StrengthWorkoutCoordinator(
            workoutRepository: repository,
            gymPlanRepository: MockGymPlanRepository(),
            ownerID: ownerID
        )

        let session = StrengthSessionBuilder.makeSession(
            plan: GymProgramTemplateLibrary.resolvableStarter(.upperBody),
            proposals: [],
            acceptedProposals: [:],
            historySessions: []
        )
        try await repository.createSession(
            WorkoutSessionLog(
                id: session.sessionID,
                ownerID: ownerID,
                templateID: session.planReference.storageKey,
                title: session.title,
                statusRaw: GymWorkoutSessionStatus.inProgress.rawValue,
                activeSessionJSON: try StrengthSessionPersistence.encode(session)
            )
        )

        let conflict = try await coordinator.detectStartConflict(
            requestedTarget: GymPlanWorkoutTarget(reference: .starter(.lowerBody), sectionIndex: 0),
            requestedTitle: "Lower Body",
            entrySource: .home
        )
        XCTAssertNotNil(conflict)
        XCTAssertEqual(conflict?.activePlanReference, .starter(.upperBody))
    }

    func testAbandonRemovesActiveSession() async throws {
        let repository = MockWorkoutRepository()
        let coordinator = StrengthWorkoutCoordinator(
            workoutRepository: repository,
            gymPlanRepository: MockGymPlanRepository(),
            ownerID: ownerID
        )

        let session = StrengthSessionBuilder.makeSession(
            plan: GymProgramTemplateLibrary.resolvableStarter(.upperBody),
            proposals: [],
            acceptedProposals: [:],
            historySessions: []
        )
        try await repository.createSession(
            WorkoutSessionLog(
                id: session.sessionID,
                ownerID: ownerID,
                templateID: session.planReference.storageKey,
                title: session.title,
                statusRaw: GymWorkoutSessionStatus.inProgress.rawValue,
                activeSessionJSON: try StrengthSessionPersistence.encode(session)
            )
        )

        try await coordinator.abandonActiveWorkout()
        let activeAfterAbandon = try await coordinator.fetchActiveWorkout()
        XCTAssertNil(activeAfterAbandon)
    }

    func testMalformedEnvelopeDecodesSafely() {
        let malformed = Data("not-json".utf8)
        XCTAssertEqual(StrengthSessionPersistence.decode(from: malformed), .malformed)
        XCTAssertNil(StrengthSessionPersistence.decodeStrength(from: malformed))
    }
}
