import Foundation

enum CoachBriefingInputFactory {
    static func make(
        now: Date = .now,
        calendar: Calendar = .current,
        displayName: String? = nil,
        goal: GoalProfile?,
        targets: DailyTargets?,
        todaysMeals: [MealLog],
        assistantName: String
    ) -> CoachBriefingInput {
        let items = todaysMeals.flatMap(\.items)
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
            todayMealCount: todaysMeals.count,
            caloriesConsumed: items.reduce(0) { $0 + $1.calories },
            proteinGramsConsumed: items.reduce(0) { $0 + $1.proteinGrams },
            carbsGramsConsumed: items.reduce(0) { $0 + $1.carbsGrams },
            fatGramsConsumed: items.reduce(0) { $0 + $1.fatGrams },
            assistantName: assistantName
        )
    }

    static func dayBounds(for date: Date, calendar: Calendar = .current) -> (start: Date, end: Date) {
        let start = calendar.startOfDay(for: date)
        let end = calendar.date(byAdding: .day, value: 1, to: start) ?? start.addingTimeInterval(86_400)
        return (start, end)
    }
}
