import XCTest
@testable import TaiAssistant

final class StrengthSessionBuilderTests: XCTestCase {
    private var plan: GymResolvablePlan!

    override func setUp() {
        super.setUp()
        plan = GymProgramTemplateLibrary.resolvableStarter(.upperBody)
    }

    func testCreatesCorrectNumberOfPlannedSets() {
        let session = StrengthSessionBuilder.makeSession(
            plan: plan,
            proposals: [],
            acceptedProposals: [:],
            historySessions: []
        )
        let firstExercise = session.exercises[0]
        XCTAssertEqual(firstExercise.sets.count, plan.prescription.workingSetsPerExercise)
    }

    func testPrefillsWeightAcrossAllSets() {
        let history = makeHistory(exerciseID: plan.exercises[0].id, weight: 40, reps: [10, 10, 10])
        let session = StrengthSessionBuilder.makeSession(
            plan: plan,
            proposals: [],
            acceptedProposals: [:],
            historySessions: history
        )
        let weights = session.exercises[0].sets.compactMap(\.suggestedWeight)
        XCTAssertEqual(weights, [40, 40, 40])
    }

    func testPrefillsPlannedReps() {
        let session = StrengthSessionBuilder.makeSession(
            plan: plan,
            proposals: [],
            acceptedProposals: [:],
            historySessions: []
        )
        XCTAssertEqual(session.exercises[0].sets[0].plannedReps, plan.prescription.repRangeUpper)
    }

    func testAcceptedProposalOverridesHistory() {
        let exercise = plan.exercises[0]
        let proposal = StrengthProgressionProposal(
            exerciseID: exercise.id,
            exerciseName: exercise.displayName,
            currentWeight: 39,
            proposedWeight: 41,
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
        let accepted: [String: StrengthAcceptedProposal] = [
            exercise.id: StrengthAcceptedProposal(
                exerciseID: exercise.id,
                decision: .accepted,
                weight: 41,
                weightUnit: "kg",
                originalProposal: proposal
            )
        ]
        let session = StrengthSessionBuilder.makeSession(
            plan: plan,
            proposals: [proposal],
            acceptedProposals: accepted,
            historySessions: makeHistory(exerciseID: exercise.id, weight: 39, reps: [10, 10, 10])
        )
        XCTAssertEqual(session.exercises[0].sets.compactMap(\.suggestedWeight), [41, 41, 41])
    }

    func testGroupsSetsUnderExercise() {
        let session = StrengthSessionBuilder.makeSession(
            plan: plan,
            proposals: [],
            acceptedProposals: [:],
            historySessions: []
        )
        XCTAssertEqual(session.exercises.count, plan.exercises.count)
        XCTAssertEqual(Set(session.exercises.map(\.id)).count, session.exercises.count)
    }

    private func makeHistory(exerciseID: String, weight: Double, reps: [Int]) -> [WorkoutSessionLog] {
        let log = WorkoutSessionLog(
            ownerID: "test",
            templateID: "starter:upperBody",
            title: "Upper",
            startedAt: .now,
            completedAt: .now,
            statusRaw: GymWorkoutSessionStatus.completed.rawValue
        )
        log.sets = reps.enumerated().map { index, rep in
            WorkoutSetLog(
                exerciseID: exerciseID,
                exerciseName: "Exercise",
                setNumber: index + 1,
                weightValue: weight,
                weightUnit: "kg",
                repetitions: rep
            )
        }
        return [log]
    }
}
