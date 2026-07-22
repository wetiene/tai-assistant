import XCTest
@testable import TaiAssistant

final class StrengthDebriefBuilderTests: XCTestCase {
    func testIdentifiesProgressionWin() {
        let session = makeSession { exercise in
            exercise.sets = exercise.sets.map { set in
                var updated = set
                updated.suggestedWeight = 39
                updated.confirmedWeight = 41
                updated.confirmedReps = 10
                updated.status = .confirmed
                return updated
            }
            exercise.status = .completed
        }
        let debrief = StrengthDebriefBuilder.build(session: session)
        XCTAssertFalse(debrief.wins.isEmpty)
        XCTAssertTrue(debrief.wins[0].detail.contains("41"))
    }

    func testIdentifiesMissedTarget() {
        let session = makeSession { exercise in
            exercise.sets = exercise.sets.enumerated().map { index, set in
                var updated = set
                updated.confirmedWeight = 30
                updated.confirmedReps = index == 2 ? 6 : 10
                updated.status = .confirmed
                return updated
            }
            exercise.status = .completed
        }
        let debrief = StrengthDebriefBuilder.build(session: session)
        XCTAssertFalse(debrief.watchItems.isEmpty)
        XCTAssertFalse(debrief.nextTimeRecommendations.isEmpty)
    }

    func testLinksToSessionID() {
        let session = makeSession { _ in }
        let debrief = StrengthDebriefBuilder.build(session: session)
        XCTAssertEqual(debrief.sessionID, session.sessionID)
    }

    private func makeSession(
        mutate: (inout StrengthExerciseInstance) -> Void
    ) -> StrengthWorkoutSession {
        var session = StrengthSessionBuilder.makeSession(
            plan: GymProgramTemplateLibrary.resolvableStarter(.upperBody),
            proposals: [],
            acceptedProposals: [:],
            historySessions: []
        )
        if !session.exercises.isEmpty {
            mutate(&session.exercises[0])
        }
        return session
    }
}
