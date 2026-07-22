import Foundation

struct HomeNutritionDayLoadResult {
    let day: NutritionDay
    let meals: [MealLog]
    let goal: GoalProfile?
    let targets: DailyTargets?
    let briefingInput: CoachBriefingInput
    let isToday: Bool
    let todayBriefing: DailyCoachBriefing?
    let historicalSummary: HomeHistoricalDaySummary?
    let mealSummaries: [HomeMealSummary]
}

enum HomeNutritionDayLoader {
    static func load(
        day: NutritionDay,
        ownerID: String,
        mealRepository: MealRepository,
        goalRepository: GoalRepository,
        displayName: String?,
        assistantName: String,
        now: Date = .now,
        calendar: Calendar = .current
    ) async throws -> HomeNutritionDayLoadResult {
        let meals = try await mealRepository.fetchMealLogs(ownerID: ownerID, on: day, calendar: calendar)
        let goals = try await goalRepository.fetchGoalProfiles(ownerID: ownerID)
        let goal = goals.sorted { $0.updatedAt > $1.updatedAt }.first
        var targets: DailyTargets?
        if let goal {
            targets = try await goalRepository.fetchDailyTargets(goalProfileID: goal.id)
        }

        let isToday = day.isToday(calendar: calendar, now: now)
        let referenceNow = isToday ? now : day.defaultOccurrenceTimestamp(calendar: calendar, now: now)
        let input = CoachBriefingInputFactory.make(
            now: referenceNow,
            calendar: calendar,
            displayName: displayName,
            goal: goal,
            targets: targets,
            meals: meals,
            assistantName: assistantName
        )

        let todayBriefing = isToday ? DailyCoachBriefingBuilder.build(input) : nil
        let historicalSummary = isToday ? nil : HomeHistoricalDayPresenter.make(
            day: day,
            input: input,
            calendar: calendar,
            now: now
        )
        let mealSummaries = meals
            .sorted { $0.eatenAt > $1.eatenAt }
            .map { HomeMealSummary(meal: $0) }

        return HomeNutritionDayLoadResult(
            day: day,
            meals: meals,
            goal: goal,
            targets: targets,
            briefingInput: input,
            isToday: isToday,
            todayBriefing: todayBriefing,
            historicalSummary: historicalSummary,
            mealSummaries: mealSummaries
        )
    }
}
