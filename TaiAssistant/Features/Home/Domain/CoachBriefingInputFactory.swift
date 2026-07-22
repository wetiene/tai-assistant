import Foundation

enum CoachBriefingInputFactory {
    static func make(
        now: Date = .now,
        calendar: Calendar = .current,
        displayName: String? = nil,
        goal: GoalProfile?,
        targets: DailyTargets?,
        meals: [MealLog],
        assistantName: String
    ) -> CoachBriefingInput {
        let totals = NutritionDayAggregation.macroTotals(from: meals)
        let macroTargets: CoachMacroTargets? = targets.map {
            CoachMacroTargets(
                calories: $0.calories,
                proteinGrams: $0.proteinGrams,
                carbsGrams: $0.carbsGrams,
                fatGrams: $0.fatGrams
            )
        }

        return CoachBriefingInput(
            now: now,
            calendar: calendar,
            displayName: displayName,
            hasActiveGoal: goal != nil,
            targets: macroTargets,
            todayMealCount: totals.mealCount,
            caloriesConsumed: totals.calories,
            proteinGramsConsumed: totals.proteinGrams,
            carbsGramsConsumed: totals.carbsGrams,
            fatGramsConsumed: totals.fatGrams,
            assistantName: assistantName
        )
    }

    static func make(
        now: Date = .now,
        calendar: Calendar = .current,
        displayName: String? = nil,
        goal: GoalProfile?,
        targets: DailyTargets?,
        todaysMeals: [MealLog],
        assistantName: String
    ) -> CoachBriefingInput {
        make(
            now: now,
            calendar: calendar,
            displayName: displayName,
            goal: goal,
            targets: targets,
            meals: todaysMeals,
            assistantName: assistantName
        )
    }

    static func dayBounds(for date: Date, calendar: Calendar = .current) -> (start: Date, end: Date) {
        NutritionDay(containing: date, calendar: calendar).queryBounds(calendar: calendar)
    }
}
