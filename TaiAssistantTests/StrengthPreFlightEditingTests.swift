import XCTest
@testable import TaiAssistant

final class StrengthPreFlightEditingTests: XCTestCase {
    func testSessionOnlyEditPreservesBaseProgramExercises() {
        let basePlan = GymProgramTemplateLibrary.resolvableStarter(.upperBody)
        var sessionPlan = basePlan
        sessionPlan.exercises = Array(basePlan.exercises.prefix(2))

        XCTAssertEqual(sessionPlan.exercises.count, 2)
        XCTAssertGreaterThan(basePlan.exercises.count, 2)
    }

    func testProposalsRecalculateAfterExerciseEdit() {
        let basePlan = GymProgramTemplateLibrary.resolvableStarter(.upperBody)
        var sessionPlan = basePlan
        sessionPlan.exercises = Array(basePlan.exercises.prefix(2))
        let history: [WorkoutSessionLog] = []

        let refreshed = StrengthSessionBuilder.proposals(for: sessionPlan, historySessions: history)
        XCTAssertEqual(refreshed.count, 2)
    }

    func testRemovedExercisesLoseAcceptedProposals() {
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
        var accepted: [String: StrengthAcceptedProposal] = [
            exerciseID: StrengthAcceptedProposal(
                exerciseID: exerciseID,
                decision: .accepted,
                weight: 42.5,
                weightUnit: "kg",
                originalProposal: proposal
            ),
        ]

        let remainingIDs: Set<String> = [GymExerciseID.legPress.rawValue]
        accepted = StrengthSessionInvariants.pruneAcceptedProposals(accepted, for: remainingIDs)
        XCTAssertTrue(accepted.isEmpty)
    }

    func testValidAcceptedProposalRemainsAfterMatchingRecalculation() {
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
        let accepted: [String: StrengthAcceptedProposal] = [
            exerciseID: StrengthAcceptedProposal(
                exerciseID: exerciseID,
                decision: .accepted,
                weight: 42.5,
                weightUnit: "kg",
                originalProposal: proposal
            ),
        ]

        let reconciled = StrengthSessionInvariants.reconcileAcceptedProposals(
            accepted,
            refreshedProposals: [proposal]
        )
        XCTAssertEqual(reconciled[exerciseID]?.weight, 42.5)
    }

    func testInvalidAcceptedProposalDroppedAfterRecalculation() {
        let exerciseID = GymExerciseID.supineChestPress.rawValue
        let original = StrengthProgressionProposal(
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
        let refreshed = StrengthProgressionProposal(
            exerciseID: exerciseID,
            exerciseName: "Chest Press",
            currentWeight: 40,
            proposedWeight: 45,
            decision: .increase,
            repRangeLower: 8,
            repRangeUpper: 10,
            reasoning: original.reasoning,
            confidence: .medium,
            weightUnit: "kg"
        )
        let accepted: [String: StrengthAcceptedProposal] = [
            exerciseID: StrengthAcceptedProposal(
                exerciseID: exerciseID,
                decision: .accepted,
                weight: 42.5,
                weightUnit: "kg",
                originalProposal: original
            ),
        ]

        let reconciled = StrengthSessionInvariants.reconcileAcceptedProposals(
            accepted,
            refreshedProposals: [refreshed]
        )
        XCTAssertNil(reconciled[exerciseID])
    }
}
