import Foundation

/// Builds a deterministic `DailyCoachBriefing` from confirmed local data only.
enum DailyCoachBriefingBuilder {
    /// Protein remaining above this fraction of target is treated as a meaningful gap.
    static let proteinGapSignificanceFraction: Double = 0.25
    /// Absolute protein remaining (grams) that still counts as a gap when targets are small.
    static let proteinGapMinimumGrams: Int = 25
    /// Calories within this absolute delta of target are “near target.”
    static let calorieNearTargetWindow: Int = 150

    static func build(_ input: CoachBriefingInput) -> DailyCoachBriefing {
        let greeting = makeGreeting(now: input.now, calendar: input.calendar, displayName: input.displayName)
        let progress = makeProgress(from: input)

        if !input.hasActiveGoal {
            return makeNoGoalBriefing(greeting: greeting, progress: progress, assistantName: input.assistantName)
        }

        guard let targets = input.targets, targets.hasUsableValues else {
            return makeMissingTargetsBriefing(greeting: greeting, progress: progress)
        }

        if input.todayMealCount == 0 {
            return makeNoMealsBriefing(greeting: greeting, progress: progress, targets: targets)
        }

        let proteinRemaining = max(Int((targets.proteinGrams - input.proteinGramsConsumed).rounded()), 0)
        let calorieDelta = input.caloriesConsumed - targets.calories
        let proteinGapSignificant = isProteinGapSignificant(
            proteinRemaining: proteinRemaining,
            proteinTarget: Int(targets.proteinGrams.rounded())
        )

        if proteinGapSignificant {
            return makeProteinGapBriefing(
                greeting: greeting,
                progress: progress,
                proteinConsumed: progress.proteinConsumed,
                proteinTarget: progress.proteinTarget,
                proteinRemaining: proteinRemaining,
                mealCount: input.todayMealCount
            )
        }

        if targets.calories > 0, abs(calorieDelta) <= calorieNearTargetWindow || calorieDelta > 0 {
            return makeCaloriesNearTargetBriefing(
                greeting: greeting,
                progress: progress,
                calorieDelta: calorieDelta
            )
        }

        return makeOnTrackBriefing(greeting: greeting, progress: progress)
    }

    // MARK: - Scenarios

    private static func makeNoGoalBriefing(
        greeting: String,
        progress: NutritionProgressSnapshot,
        assistantName: String
    ) -> DailyCoachBriefing {
        DailyCoachBriefing(
            greeting: greeting,
            headline: "Set a goal so I can guide today",
            body: "Set a goal so I can tailor today’s guidance.",
            recommendation: CoachRecommendation(
                focusTitle: "Review your goal",
                actionTitle: "Set your goal",
                destination: .reviewGoal,
                reason: RecommendationReason(
                    summary: "Without a goal, \(assistantName) cannot tailor today’s focus.",
                    evidencePoints: [
                        "No active goal is saved on this device.",
                        mealEvidence(mealCount: progress.mealCountToday, calories: progress.caloriesConsumed)
                    ],
                    unknowns: [
                        "Macro targets are not available until a goal is set.",
                        "Training, sleep and recovery are not part of today’s guidance."
                    ]
                )
            ),
            progress: progress,
            dataSufficiencyNote: "Guidance is limited until a goal is set."
        )
    }

    private static func makeMissingTargetsBriefing(
        greeting: String,
        progress: NutritionProgressSnapshot
    ) -> DailyCoachBriefing {
        DailyCoachBriefing(
            greeting: greeting,
            headline: "Your goal needs clear targets",
            body: "A goal is saved, but calorie or macro targets are missing or zero. Review your goal so I can coach against real numbers.",
            recommendation: CoachRecommendation(
                focusTitle: "Review your goal",
                actionTitle: "Review goal",
                destination: .reviewGoal,
                reason: RecommendationReason(
                    summary: "Targets are missing or set to zero, so nutrition guidance would be unreliable.",
                    evidencePoints: [
                        "An active goal exists.",
                        "Calorie and macro targets are missing or zero.",
                        mealEvidence(mealCount: progress.mealCountToday, calories: progress.caloriesConsumed)
                    ],
                    unknowns: [
                        "Without targets, remaining protein, carbs and fat cannot be judged."
                    ]
                )
            ),
            progress: progress,
            dataSufficiencyNote: "Targets are incomplete."
        )
    }

    private static func makeNoMealsBriefing(
        greeting: String,
        progress: NutritionProgressSnapshot,
        targets: CoachMacroTargets
    ) -> DailyCoachBriefing {
        DailyCoachBriefing(
            greeting: greeting,
            headline: "Start with your first check-in",
            body: "Check in your first meal so I can guide the rest of your day.",
            recommendation: CoachRecommendation(
                focusTitle: "Check in your first meal",
                actionTitle: "Log your first meal",
                destination: .checkInMeal,
                reason: RecommendationReason(
                    summary: "No meals are logged for today yet.",
                    evidencePoints: [
                        "Active goal is set.",
                        "Today’s calorie target is \(targets.calories) kcal.",
                        "Today’s protein target is \(Int(targets.proteinGrams.rounded()))g.",
                        "No meals logged today."
                    ],
                    unknowns: [
                        "Until a meal is confirmed, remaining macros are estimates from your targets only."
                    ]
                )
            ),
            progress: progress,
            dataSufficiencyNote: nil
        )
    }

    private static func makeProteinGapBriefing(
        greeting: String,
        progress: NutritionProgressSnapshot,
        proteinConsumed: Int,
        proteinTarget: Int,
        proteinRemaining: Int,
        mealCount: Int
    ) -> DailyCoachBriefing {
        DailyCoachBriefing(
            greeting: greeting,
            headline: "Protein is the main gap today",
            body: "Protein is the main gap today. Your next meal is a good opportunity to close it.",
            recommendation: CoachRecommendation(
                focusTitle: "Add protein next",
                actionTitle: "Check In",
                destination: .checkInMeal,
                reason: RecommendationReason(
                    summary: "Protein is the largest remaining macro gap based on today’s confirmed meals.",
                    evidencePoints: [
                        "Today you have logged \(proteinConsumed)g of protein against a \(proteinTarget)g target.",
                        "About \(proteinRemaining)g protein remains.",
                        "\(mealCount) meal\(mealCount == 1 ? "" : "s") logged today.",
                        "Calories so far: \(progress.caloriesConsumed) of \(progress.calorieTarget)."
                    ],
                    unknowns: [
                        "Upcoming meals are not known until you check them in.",
                        "Estimates depend on confirmed meal entries only."
                    ]
                )
            ),
            progress: progress,
            dataSufficiencyNote: nil
        )
    }

    private static func makeCaloriesNearTargetBriefing(
        greeting: String,
        progress: NutritionProgressSnapshot,
        calorieDelta: Int
    ) -> DailyCoachBriefing {
        let body: String
        let focus: String
        let summary: String
        if calorieDelta > 0 {
            body = "You’re a little over today’s calorie target. Keep your next meal lighter and balanced."
            focus = "Keep the next meal lighter"
            summary = "Calories are above today’s target based on confirmed meals."
        } else {
            body = "You’re close to today’s calorie target. Keep dinner balanced and consistent."
            focus = "Keep dinner balanced"
            summary = "Calories are near today’s target based on confirmed meals."
        }

        return DailyCoachBriefing(
            greeting: greeting,
            headline: calorieDelta > 0 ? "Ease into the rest of today" : "You’re close to today’s target",
            body: body,
            recommendation: CoachRecommendation(
                focusTitle: focus,
                actionTitle: "Check In",
                destination: .checkInMeal,
                reason: RecommendationReason(
                    summary: summary,
                    evidencePoints: [
                        "Calories so far: \(progress.caloriesConsumed) of \(progress.calorieTarget).",
                        "Protein so far: \(progress.proteinConsumed)g of \(progress.proteinTarget)g.",
                        "\(progress.mealCountToday) meal\(progress.mealCountToday == 1 ? "" : "s") logged today."
                    ],
                    unknowns: [
                        "Future meals and activity are not included until logged."
                    ]
                )
            ),
            progress: progress,
            dataSufficiencyNote: nil
        )
    }

    private static func makeOnTrackBriefing(
        greeting: String,
        progress: NutritionProgressSnapshot
    ) -> DailyCoachBriefing {
        DailyCoachBriefing(
            greeting: greeting,
            headline: "You’re on track today",
            body: "You’re on track today. Keep your next meal balanced and consistent.",
            recommendation: CoachRecommendation(
                focusTitle: "Keep your next meal balanced",
                actionTitle: "Check In",
                destination: .checkInMeal,
                reason: RecommendationReason(
                    summary: "Today’s confirmed meals sit broadly within your calorie and protein targets.",
                    evidencePoints: [
                        "Calories so far: \(progress.caloriesConsumed) of \(progress.calorieTarget).",
                        "Protein so far: \(progress.proteinConsumed)g of \(progress.proteinTarget)g.",
                        "Carbs so far: \(progress.carbsConsumed)g of \(progress.carbsTarget)g.",
                        "Fat so far: \(progress.fatConsumed)g of \(progress.fatTarget)g.",
                        "\(progress.mealCountToday) meal\(progress.mealCountToday == 1 ? "" : "s") logged today."
                    ],
                    unknowns: [
                        "This guidance uses today’s confirmed meals only."
                    ]
                )
            ),
            progress: progress,
            dataSufficiencyNote: nil
        )
    }

    // MARK: - Helpers

    static func progressSnapshot(from input: CoachBriefingInput) -> NutritionProgressSnapshot {
        makeProgress(from: input)
    }

    static func makeGreeting(now: Date, calendar: Calendar, displayName: String?) -> String {
        let hour = calendar.component(.hour, from: now)
        let timeGreeting: String
        switch hour {
        case 5..<12:
            timeGreeting = "Good morning"
        case 12..<17:
            timeGreeting = "Good afternoon"
        default:
            timeGreeting = "Good evening"
        }

        let trimmed = displayName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if trimmed.isEmpty {
            return timeGreeting
        }
        return "\(timeGreeting), \(trimmed)"
    }

    static func isProteinGapSignificant(proteinRemaining: Int, proteinTarget: Int) -> Bool {
        guard proteinRemaining > 0 else { return false }
        if proteinTarget <= 0 {
            return proteinRemaining >= proteinGapMinimumGrams
        }
        let fractionThreshold = Int((Double(proteinTarget) * proteinGapSignificanceFraction).rounded())
        let threshold = max(fractionThreshold, proteinGapMinimumGrams)
        return proteinRemaining >= threshold
    }

    private static func makeProgress(from input: CoachBriefingInput) -> NutritionProgressSnapshot {
        let calorieTarget = input.targets?.calories ?? 0
        let proteinTarget = Int((input.targets?.proteinGrams ?? 0).rounded())
        let carbsTarget = Int((input.targets?.carbsGrams ?? 0).rounded())
        let fatTarget = Int((input.targets?.fatGrams ?? 0).rounded())
        return NutritionProgressSnapshot(
            caloriesConsumed: input.caloriesConsumed,
            calorieTarget: calorieTarget,
            proteinConsumed: Int(input.proteinGramsConsumed.rounded()),
            proteinTarget: proteinTarget,
            carbsConsumed: Int(input.carbsGramsConsumed.rounded()),
            carbsTarget: carbsTarget,
            fatConsumed: Int(input.fatGramsConsumed.rounded()),
            fatTarget: fatTarget,
            mealCountToday: input.todayMealCount
        )
    }

    private static func mealEvidence(mealCount: Int, calories: Int) -> String {
        if mealCount == 0 {
            return "No meals logged today."
        }
        return "\(mealCount) meal\(mealCount == 1 ? "" : "s") logged today (\(calories) kcal)."
    }
}
