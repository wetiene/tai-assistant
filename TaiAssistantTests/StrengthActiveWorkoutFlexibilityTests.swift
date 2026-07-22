import XCTest
@testable import TaiAssistant

@MainActor
final class StrengthActiveWorkoutFlexibilityTests: XCTestCase {
    private let ownerID = "strength.flexibility"

    private func makeController(repository: MockWorkoutRepository = MockWorkoutRepository()) -> StrengthWorkoutController {
        StrengthWorkoutController(workoutRepository: repository, ownerID: ownerID)
    }

    private func preparedSession(controller: StrengthWorkoutController) -> StrengthWorkoutSession {
        controller.prepareSession(
            plan: GymProgramTemplateLibrary.resolvableStarter(.upperBody),
            proposals: [],
            acceptedProposals: [:],
            historySessions: []
        )
    }

    func testSelectExerciseDoesNotSkipEarlierExercises() async throws {
        let controller = makeController()
        try await controller.startSession(preparedSession(controller: controller))
        guard let session = controller.session else {
            return XCTFail("Missing session")
        }
        let secondExerciseID = session.exercises[1].id

        try await controller.selectExercise(exerciseInstanceID: secondExerciseID)

        XCTAssertEqual(controller.session?.currentExerciseInstanceID, secondExerciseID)
        XCTAssertEqual(controller.session?.exercises[0].status, .pending)
        XCTAssertEqual(controller.session?.exercises[1].status, .active)
    }

    func testEditConfirmedSetUpdatesPersistedValues() async throws {
        let repository = MockWorkoutRepository()
        let controller = makeController(repository: repository)
        try await controller.startSession(preparedSession(controller: controller))
        guard let session = controller.session,
              let exerciseID = session.currentExerciseInstanceID,
              let setID = session.currentSetID
        else {
            return XCTFail("Missing active set")
        }

        try await controller.confirmCurrentSet(weight: 40, reps: 10)
        try await controller.editConfirmedSet(
            exerciseInstanceID: exerciseID,
            setID: setID,
            weight: 42.5,
            reps: 9
        )

        let edited = controller.session?.exercises
            .first { $0.id == exerciseID }?
            .sets.first { $0.id == setID }
        XCTAssertEqual(edited?.confirmedWeight, 42.5)
        XCTAssertEqual(edited?.confirmedReps, 9)
        XCTAssertEqual(edited?.status, .confirmed)

        let persisted = try await repository.fetchInProgressSession(ownerID: ownerID)
        let restored = StrengthSessionPersistence.decodeStrength(from: persisted?.activeSessionJSON)
        let persistedSet = restored?.exercises
            .first { $0.id == exerciseID }?
            .sets.first { $0.id == setID }
        XCTAssertEqual(persistedSet?.confirmedWeight, 42.5)
        XCTAssertEqual(persistedSet?.confirmedReps, 9)
    }

    func testExerciseCompletionDerivedFromSetsNotPosition() async throws {
        let controller = makeController()
        try await controller.startSession(preparedSession(controller: controller))
        guard let first = controller.session?.exercises.first else {
            return XCTFail("Missing exercise")
        }

        for set in first.workingSets {
            try await controller.selectSet(exerciseInstanceID: first.id, setID: set.id)
            try await controller.confirmCurrentSet(weight: 30, reps: 8)
        }

        XCTAssertEqual(controller.session?.exercises.first?.status, .completed)
        XCTAssertEqual(controller.session?.exercises[1].status, .pending)
    }

    func testSkipRemainingSetsAndCompleteFinishesWorkout() async throws {
        let repository = MockWorkoutRepository()
        let controller = makeController(repository: repository)
        try await controller.startSession(preparedSession(controller: controller))
        try await controller.confirmCurrentSet(weight: 40, reps: 10)

        _ = try await controller.skipRemainingSetsAndComplete()

        XCTAssertNil(controller.session)
        XCTAssertNotNil(controller.debrief)
        let inProgress = try await repository.fetchInProgressSession(ownerID: ownerID)
        XCTAssertNil(inProgress)
    }

    func testSetFormattingAvoidsMisleadingZeroWeight() {
        let plan = GymProgramTemplateLibrary.resolvableStarter(.upperBody)
        let exercise = StrengthExerciseInstance(
            id: UUID(),
            plannedExercise: plan.exercises[0],
            status: .pending,
            sets: []
        )
        let set = StrengthSetRecord(
            id: UUID(),
            setNumber: 1,
            isWarmup: false,
            plannedReps: 10,
            suggestedWeight: nil,
            suggestedReps: 10,
            confirmedWeight: nil,
            confirmedReps: 12,
            weightUnit: "kg",
            status: .confirmed
        )

        XCTAssertEqual(
            StrengthSetFormatting.displayLine(for: set, exercise: exercise),
            "12 reps"
        )
    }

    func testDurationFormattingUsesHoursWhenNeeded() {
        XCTAssertEqual(StrengthSetFormatting.formatWorkoutDuration(265 * 60 + 51), "4:25:51")
        XCTAssertEqual(StrengthSetFormatting.formatWorkoutDuration(125), "2:05")
    }
}
