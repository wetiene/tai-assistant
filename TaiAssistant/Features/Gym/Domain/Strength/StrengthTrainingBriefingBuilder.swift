import Foundation

enum StrengthTrainingBriefingBuilder {
    static func buildCardState(
        inProgressSession: StrengthWorkoutSession?,
        plannedWorkout: GymResolvablePlan?,
        historySessions: [WorkoutSessionLog],
        weightUnit: String = "kg"
    ) -> StrengthTrainingCardState? {
        if let active = inProgressSession, active.status == .inProgress {
            return .active(activeCardModel(for: active))
        }
        guard let plan = plannedWorkout else { return nil }
        return .planned(plannedCardModel(for: plan, historySessions: historySessions, weightUnit: weightUnit))
    }

    static func activeCardModel(for session: StrengthWorkoutSession) -> StrengthActiveWorkoutCardModel {
        let current = session.currentExerciseInstance
        let currentIndex = session.exercises.firstIndex { $0.id == session.currentExerciseInstanceID }
        let nextName: String?
        if let currentIndex, session.exercises.indices.contains(currentIndex + 1) {
            nextName = session.exercises[currentIndex + 1].displayName
        } else {
            nextName = nil
        }

        return StrengthActiveWorkoutCardModel(
            sessionID: session.sessionID,
            title: session.title,
            elapsedSeconds: session.elapsedActiveSeconds,
            completedSets: session.completedWorkingSetCount,
            totalSets: session.totalPlannedWorkingSets,
            currentExerciseName: current?.displayName,
            nextExerciseName: nextName
        )
    }

    static func plannedCardModel(
        for plan: GymResolvablePlan,
        historySessions: [WorkoutSessionLog],
        weightUnit: String
    ) -> StrengthPlannedWorkoutCardModel {
        let proposals = StrengthSessionBuilder.proposals(
            for: plan,
            historySessions: historySessions,
            weightUnit: weightUnit
        )
        let primary = proposals.first { $0.decision == .increase } ?? proposals.first
        let mission = StrengthSessionBuilder.buildMission(plan: plan, primaryProposal: primary)

        return StrengthPlannedWorkoutCardModel(
            planReference: plan.reference,
            sectionIndex: plan.sectionIndex,
            title: plan.title,
            estimatedDurationMinutes: StrengthSessionBuilder.estimatedDurationMinutes(for: plan),
            exerciseCount: plan.exercises.count,
            mission: mission,
            primaryProgression: primary
        )
    }

    static func resolvePlannedWorkout(
        library: GymPlanLibrarySnapshot,
        gymPlanRepository: GymPlanRepository,
        ownerID: String,
        calendar: Calendar = .current,
        now: Date = .now
    ) async throws -> GymResolvablePlan? {
        if StrengthConversationUITestSupport.forcesLowerBodyPlan {
            return GymProgramTemplateLibrary.resolvableStarter(.lowerBody)
        }

        if let active = library.activePlan {
            let sectionIndex = sectionIndexForToday(
                sectionCount: max(1, active.sectionCount),
                calendar: calendar,
                now: now
            )
            return try await gymPlanRepository.resolvePlan(
                reference: active.reference,
                sectionIndex: sectionIndex,
                ownerID: ownerID
            )
        }

        let weekday = calendar.component(.weekday, from: now)
        let template: GymProgramTemplateID = weekday.isMultiple(of: 2) ? .lowerBody : .upperBody
        return GymProgramTemplateLibrary.resolvableStarter(template)
    }

    private static func sectionIndexForToday(sectionCount: Int, calendar: Calendar, now: Date) -> Int {
        let weekday = calendar.component(.weekday, from: now)
        return (weekday - 1) % sectionCount
    }
}
