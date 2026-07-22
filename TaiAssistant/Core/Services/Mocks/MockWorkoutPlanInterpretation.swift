import Foundation

enum MockWorkoutPlanInterpretation {
    static func trainerFixtureResponse(for request: AIInterpretWorkoutPlanRequest) -> AIInterpretWorkoutPlanResponse {
        _ = request
        return AIInterpretWorkoutPlanResponse(
            schemaVersion: 1,
            suggestedPlan: AIWorkoutPlanSuggestion(
                name: "Trainer Program – July 2026",
                sections: [
                    upperBodySection(),
                    lowerBodySection()
                ],
                generalInstructions: [
                    "Complete 3 sets per exercise",
                    "Aim for 8–12 repetitions",
                    "Work close to fatigue while maintaining good form"
                ],
                suggestedDurationWeeks: 4
            ),
            unresolvedItems: [
                AIWorkoutPlanUnresolvedItem(
                    sourceText: "Glute Trainer",
                    reason: "Catalog terminology differs from trainer wording",
                    suggestedMatches: [
                        AIWorkoutPlanMatchSuggestion(exerciseID: GymExerciseID.gluteTrainer.rawValue, confidence: 0.91)
                    ]
                )
            ],
            warnings: [],
            confidence: "high",
            requiresUserConfirmation: true
        )
    }

    private static func upperBodySection() -> AIWorkoutPlanSectionProposal {
        AIWorkoutPlanSectionProposal(
            name: "Upper Body",
            orderIndex: 0,
            exercises: [
                exercise("Supine Chest Press", id: .supineChestPress, order: 0),
                exercise("Seated Shoulder Press", id: .seatedShoulderPress, order: 1),
                exercise("Reverse Grip Lat Pulldown", id: .reverseGripLatPulldown, order: 2),
                exercise("Seated Row", id: .seatedRow, order: 3),
                exercise("Bicep Curl", id: .bicepCurl, order: 4, optional: true),
                exercise("Tricep Pushdown", id: .tricepPushdown, order: 5, optional: true),
            ]
        )
    }

    private static func lowerBodySection() -> AIWorkoutPlanSectionProposal {
        AIWorkoutPlanSectionProposal(
            name: "Lower Body",
            orderIndex: 1,
            exercises: [
                exercise("Leg Press", id: .legPress, order: 0),
                exercise("Kettlebell Squats", id: .kettlebellSquats, order: 1),
                exercise("Stationary Lunges", id: .stationaryLunges, order: 2),
                exercise("Glute Trainer", id: .gluteTrainer, order: 3, confidence: 0.78),
                exercise("Leg Extension", id: .legExtension, order: 4, optional: true),
                exercise("Leg Curl", id: .legCurl, order: 5, optional: true),
            ]
        )
    }

    private static func exercise(
        _ sourceName: String,
        id: GymExerciseID?,
        order: Int,
        optional: Bool = false,
        confidence: Double = 0.98
    ) -> AIWorkoutPlanExerciseProposal {
        AIWorkoutPlanExerciseProposal(
            sourceName: sourceName,
            matchedExerciseID: id?.rawValue,
            displayName: id?.displayName ?? sourceName,
            orderIndex: order,
            targetSets: 3,
            minimumRepetitions: 8,
            maximumRepetitions: 12,
            isOptional: optional,
            notes: optional ? nil : "Work close to fatigue with good form",
            matchConfidence: confidence
        )
    }
}
