import Foundation

enum StrengthSessionBuilder {
    static func buildMission(
        plan: GymResolvablePlan,
        primaryProposal: StrengthProgressionProposal?
    ) -> String {
        if let primary = primaryProposal {
            switch primary.decision {
            case .increase:
                return "Progress \(primary.exerciseName) while keeping the remaining exercises controlled."
            case .hold:
                return "Stabilise \(primary.exerciseName) and execute the rest of the session cleanly."
            case .decrease:
                return "Rebuild \(primary.exerciseName) conservatively and keep the session controlled."
            }
        }
        return "Execute today's plan with consistent effort across all exercises."
    }

    static func estimatedDurationMinutes(for plan: GymResolvablePlan) -> Int {
        StrengthWorkoutDurationEstimator.estimatedDurationMinutes(for: plan)
    }

    static func makeExerciseInstances(
        from plan: GymResolvablePlan,
        acceptedProposals: [String: StrengthAcceptedProposal],
        historySessions: [WorkoutSessionLog],
        weightUnit: String
    ) -> [StrengthExerciseInstance] {
        plan.exercises.sorted { $0.orderIndex < $1.orderIndex }.map { planned in
            let setCount = planned.effectiveSets(planPrescription: plan.prescription)
            let repRange = planned.effectiveRepRange(planPrescription: plan.prescription)
            let targetReps = repRange.upper

            let suggestedWeight = resolveSuggestedWeight(
                exercise: planned,
                acceptedProposals: acceptedProposals,
                historySessions: historySessions,
                weightUnit: weightUnit
            )

            let sets = (1...setCount).map { setNumber in
                StrengthSetRecord(
                    id: UUID(),
                    setNumber: setNumber,
                    isWarmup: false,
                    plannedReps: targetReps,
                    suggestedWeight: suggestedWeight,
                    suggestedReps: targetReps,
                    confirmedWeight: nil,
                    confirmedReps: nil,
                    weightUnit: weightUnit,
                    status: .pending
                )
            }

            return StrengthExerciseInstance(
                id: UUID(),
                plannedExercise: planned,
                status: .pending,
                sets: sets
            )
        }
    }

    static func resolveSuggestedWeight(
        exercise: GymPlannedExercise,
        acceptedProposals: [String: StrengthAcceptedProposal],
        historySessions: [WorkoutSessionLog],
        weightUnit: String
    ) -> Double? {
        if let accepted = acceptedProposals[exercise.id] {
            return accepted.weight
        }
        if let latest = StrengthExerciseHistoryLoader.latestWeight(exerciseID: exercise.id, from: historySessions) {
            return latest.weight
        }
        return nil
    }

    static func makeSession(
        plan: GymResolvablePlan,
        proposals: [StrengthProgressionProposal],
        acceptedProposals: [String: StrengthAcceptedProposal],
        historySessions: [WorkoutSessionLog],
        weightUnit: String = "kg",
        origin: StrengthWorkoutEntrySource = .home,
        preFlightCompleted: Bool = false
    ) -> StrengthWorkoutSession {
        let exercises = makeExerciseInstances(
            from: plan,
            acceptedProposals: acceptedProposals,
            historySessions: historySessions,
            weightUnit: weightUnit
        )
        let primary = proposals.first
        let mission = buildMission(plan: plan, primaryProposal: primary)

        return StrengthWorkoutSession(
            sessionID: UUID(),
            planReference: plan.reference,
            title: plan.title,
            sectionName: plan.sectionName,
            sectionIndex: plan.sectionIndex,
            prescription: plan.prescription,
            exercises: exercises,
            currentExerciseInstanceID: nil,
            currentSetID: nil,
            startedAt: .now,
            pausedAt: nil,
            accumulatedPauseSeconds: 0,
            status: .inProgress,
            mission: mission,
            acceptedProposals: acceptedProposals,
            preFlightProposals: proposals,
            preFlightCompleted: preFlightCompleted,
            origin: origin,
            weightUnit: weightUnit,
            lastCoachingMessage: nil
        )
    }

    static func proposals(
        for plan: GymResolvablePlan,
        historySessions: [WorkoutSessionLog],
        weightUnit: String = "kg",
        painExerciseIDs: Set<String> = []
    ) -> [StrengthProgressionProposal] {
        plan.exercises.sorted { $0.orderIndex < $1.orderIndex }.map { exercise in
            let repRange = exercise.effectiveRepRange(planPrescription: plan.prescription)
            let recent = StrengthExerciseHistoryLoader.loadRecentSessions(
                exerciseID: exercise.id,
                from: historySessions
            )
            let gap = StrengthExerciseHistoryLoader.daysSinceLastSession(
                exerciseID: exercise.id,
                from: historySessions
            )
            return StrengthProgressionEngine.evaluate(
                StrengthProgressionInput(
                    exerciseID: exercise.id,
                    exerciseName: exercise.displayName,
                    repRangeLower: repRange.lower,
                    repRangeUpper: repRange.upper,
                    recentSessions: recent,
                    daysSinceLastSession: gap,
                    hasActivePainFlag: painExerciseIDs.contains(exercise.id),
                    weightUnit: weightUnit
                )
            )
        }
    }
}
