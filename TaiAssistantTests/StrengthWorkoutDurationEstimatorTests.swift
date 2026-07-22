import XCTest
@testable import TaiAssistant

final class StrengthWorkoutDurationEstimatorTests: XCTestCase {
    func testSixExerciseStarterPlanProducesReasonableEstimate() {
        let plan = GymProgramTemplateLibrary.resolvableStarter(.lowerBody)
        let minutes = StrengthWorkoutDurationEstimator.estimatedDurationMinutes(for: plan)
        XCTAssertGreaterThanOrEqual(minutes, 30)
        XCTAssertLessThanOrEqual(minutes, 60)
    }

    func testEstimateUsesExplicitComponents() {
        let plan = GymProgramTemplateLibrary.resolvableStarter(.upperBody)
        let expectedSeconds = plan.exercises.reduce(TimeInterval(0)) { partial, exercise in
            partial + StrengthWorkoutDurationEstimator.exerciseDurationSeconds(
                for: exercise,
                prescription: plan.prescription
            )
        } + TimeInterval(max(0, plan.exercises.count - 1)) * StrengthWorkoutDurationEstimator.exerciseTransitionSeconds
        let expectedMinutes = max(
            StrengthWorkoutDurationEstimator.minimumDurationMinutes,
            Int(ceil(expectedSeconds / 60))
        )
        XCTAssertEqual(
            StrengthWorkoutDurationEstimator.estimatedDurationMinutes(for: plan),
            expectedMinutes
        )
    }

    func testEmptyPlanUsesMinimumDuration() {
        let plan = GymResolvablePlan(
            reference: .starter(.upperBody),
            title: "Empty",
            sectionName: nil,
            sectionIndex: 0,
            exercises: [],
            prescription: .default,
            generalInstructions: []
        )
        XCTAssertEqual(
            StrengthWorkoutDurationEstimator.estimatedDurationMinutes(for: plan),
            StrengthWorkoutDurationEstimator.minimumDurationMinutes
        )
    }
}
