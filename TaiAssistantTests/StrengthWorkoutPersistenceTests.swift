import XCTest
import SwiftData
@testable import TaiAssistant

@MainActor
final class StrengthWorkoutPersistenceTests: XCTestCase {
    private let ownerID = "strength.persistence.user"

    func testRestoresActiveWorkoutAfterRelaunch() async throws {
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

        let relaunched = StrengthWorkoutController(workoutRepository: repository, ownerID: ownerID)
        let restored = try await relaunched.restoreInProgressSession()

        XCTAssertNotNil(restored)
        XCTAssertEqual(restored?.sessionID, prepared.sessionID)
        XCTAssertEqual(restored?.exercises.count, plan.exercises.count)
    }

    func testCompletedWorkoutsDoNotRestoreAsActive() async throws {
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
        _ = try await controller.finishWorkout()

        let restored = try await controller.restoreInProgressSession()
        XCTAssertNil(restored)
    }

    func testOnlyOneActiveWorkoutExists() async throws {
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
            plan: plan,
            proposals: [],
            acceptedProposals: [:],
            historySessions: []
        )

        do {
            try await second.startSession(secondPrepared)
            XCTFail("Expected active session conflict")
        } catch StrengthWorkoutStartError.activeSessionInProgress {
            XCTAssertTrue(true)
        }
    }

    func testSectionIndexRoundTripsThroughSnapshot() throws {
        var plan = GymProgramTemplateLibrary.resolvableStarter(.upperBody)
        plan.sectionIndex = 2
        let session = StrengthSessionBuilder.makeSession(
            plan: plan,
            proposals: [],
            acceptedProposals: [:],
            historySessions: []
        )
        XCTAssertEqual(session.sectionIndex, 2)

        let data = try XCTUnwrap(StrengthSessionPersistence.encode(session))
        let decoded = StrengthSessionPersistence.decodeStrength(from: data)
        XCTAssertEqual(decoded?.sectionIndex, 2)
    }

    func testMigratesLegacyActiveSessionJSON() throws {
        let legacy = GymActiveSession(
            sessionID: UUID(),
            planReference: .starter(.upperBody),
            title: "Upper Body",
            exercises: GymProgramTemplateLibrary.upperBody.exercises,
            prescription: .default,
            currentExerciseIndex: 1,
            currentSetNumber: 2,
            startedAt: .now,
            status: .inProgress
        )
        let data = try XCTUnwrap(StrengthSessionPersistence.encodeLegacy(legacy))
        let migrated = StrengthSessionPersistence.decodeStrength(from: data)
        XCTAssertEqual(migrated?.sessionID, legacy.sessionID)
        XCTAssertEqual(migrated?.exercises.count, legacy.exercises.count)
    }
}
