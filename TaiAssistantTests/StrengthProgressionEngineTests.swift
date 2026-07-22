import XCTest
@testable import TaiAssistant

final class StrengthProgressionEngineTests: XCTestCase {
    private let exerciseID = GymExerciseID.supineChestPress.rawValue
    private let exerciseName = "Supine Chest Press"

    func testProgressesAfterThreeConsistentSessionsAtTopOfRange() {
        let input = makeInput(
            sessions: [
                session(at: 0, weight: 39, reps: [10, 10, 10]),
                session(at: -3, weight: 39, reps: [10, 10, 10]),
                session(at: -6, weight: 39, reps: [10, 10, 10]),
            ]
        )

        let result = StrengthProgressionEngine.evaluate(input)

        XCTAssertEqual(result.decision, .increase)
        XCTAssertEqual(result.proposedWeight, 41.5)
        XCTAssertEqual(result.confidence, .high)
        XCTAssertTrue(result.reasoning.observation.contains("39"))
    }

    func testDoesNotProgressWithInsufficientHistory() {
        let input = makeInput(sessions: [session(at: 0, weight: 39, reps: [10, 10, 10])])
        let result = StrengthProgressionEngine.evaluate(input)
        XCTAssertEqual(result.decision, .hold)
        XCTAssertEqual(result.confidence, .medium)
    }

    func testHoldsWhenPerformanceIsMixed() {
        let input = makeInput(
            sessions: [
                session(at: 0, weight: 39, reps: [10, 9, 8]),
                session(at: -3, weight: 39, reps: [10, 10, 9]),
                session(at: -6, weight: 39, reps: [10, 10, 10]),
            ]
        )
        let result = StrengthProgressionEngine.evaluate(input)
        XCTAssertEqual(result.decision, .hold)
    }

    func testHoldsWhenLatestSessionBelowTarget() {
        let input = makeInput(
            sessions: [
                session(at: 0, weight: 39, reps: [7, 7, 7]),
                session(at: -3, weight: 39, reps: [7, 7, 7]),
                session(at: -6, weight: 39, reps: [7, 7, 7]),
            ]
        )
        let result = StrengthProgressionEngine.evaluate(input)
        XCTAssertEqual(result.decision, .decrease)
    }

    func testHandlesTrainingGap() {
        let input = makeInput(
            sessions: [session(at: -20, weight: 39, reps: [10, 10, 10])],
            daysSinceLastSession: 20
        )
        let result = StrengthProgressionEngine.evaluate(input)
        XCTAssertEqual(result.decision, .decrease)
    }

    func testRespectsPainFlag() {
        let input = makeInput(
            sessions: [
                session(at: 0, weight: 39, reps: [10, 10, 10]),
                session(at: -3, weight: 39, reps: [10, 10, 10]),
                session(at: -6, weight: 39, reps: [10, 10, 10]),
            ],
            hasActivePainFlag: true
        )
        let result = StrengthProgressionEngine.evaluate(input)
        XCTAssertEqual(result.decision, .hold)
        XCTAssertTrue(result.reasoning.observation.contains("pain"))
    }

    func testProducesReasoningFields() {
        let input = makeInput(
            sessions: [
                session(at: 0, weight: 39, reps: [10, 10, 10]),
                session(at: -3, weight: 39, reps: [10, 10, 10]),
                session(at: -6, weight: 39, reps: [10, 10, 10]),
            ]
        )
        let result = StrengthProgressionEngine.evaluate(input)
        XCTAssertFalse(result.reasoning.observation.isEmpty)
        XCTAssertFalse(result.reasoning.rule.isEmpty)
        XCTAssertFalse(result.reasoning.recommendation.isEmpty)
        XCTAssertFalse(result.reasoning.fallback.isEmpty)
    }

    private func makeInput(
        sessions: [StrengthExerciseHistorySession],
        daysSinceLastSession: Int? = 2,
        hasActivePainFlag: Bool = false
    ) -> StrengthProgressionInput {
        StrengthProgressionInput(
            exerciseID: exerciseID,
            exerciseName: exerciseName,
            repRangeLower: 8,
            repRangeUpper: 10,
            recentSessions: sessions,
            daysSinceLastSession: daysSinceLastSession,
            hasActivePainFlag: hasActivePainFlag,
            weightUnit: "kg"
        )
    }

    private func session(at dayOffset: Int, weight: Double, reps: [Int]) -> StrengthExerciseHistorySession {
        let date = Calendar.current.date(byAdding: .day, value: dayOffset, to: .now) ?? .now
        return StrengthExerciseHistorySession(
            completedAt: date,
            sets: reps.enumerated().map { index, rep in
                StrengthExerciseHistorySet(weight: weight, reps: rep, setNumber: index + 1)
            }
        )
    }
}
