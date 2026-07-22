import Foundation

/// Factual Home content for a selected past nutrition day (no forward-looking coaching).
struct HomeHistoricalDaySummary: Equatable, Sendable {
    let navigationTitle: String
    let headline: String
    let body: String
    let progress: NutritionProgressSnapshot
}

enum HomeHistoricalDayPresenter {
    static func make(
        day: NutritionDay,
        input: CoachBriefingInput,
        calendar: Calendar = .current,
        now: Date = .now
    ) -> HomeHistoricalDaySummary {
        let progress = DailyCoachBriefingBuilder.progressSnapshot(from: input)
        let mealCount = input.todayMealCount
        let calories = input.caloriesConsumed
        let protein = progress.proteinConsumed

        let navigationTitle = HomeNutritionDayFormatting.navigationTitle(
            for: day,
            calendar: calendar,
            now: now
        )

        let headline: String
        let body: String
        if mealCount == 0 {
            headline = "No meals logged"
            body = "Nothing was confirmed for this day."
        } else {
            headline = "\(mealCount) meal\(mealCount == 1 ? "" : "s") logged"
            body = "\(calories) kcal · \(protein) g protein on this day."
        }

        return HomeHistoricalDaySummary(
            navigationTitle: navigationTitle,
            headline: headline,
            body: body,
            progress: progress
        )
    }
}

enum HomeNutritionDayFormatting {
    static func navigationTitle(
        for day: NutritionDay,
        calendar: Calendar = .current,
        now: Date = .now
    ) -> String {
        if day.isToday(calendar: calendar, now: now) {
            return "Today"
        }

        let yesterday = NutritionDay(containing: calendar.date(byAdding: .day, value: -1, to: now) ?? now, calendar: calendar)
        if day == yesterday {
            return "Yesterday"
        }

        return day.start.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
    }

    static func pickerLabel(
        for day: NutritionDay,
        calendar: Calendar = .current,
        now: Date = .now
    ) -> String {
        if day.isToday(calendar: calendar, now: now) {
            return "Today · \(day.start.formatted(.dateTime.month(.abbreviated).day()))"
        }
        return day.start.formatted(.dateTime.weekday(.wide).month(.abbreviated).day())
    }

    static func mealsSectionTitle(isToday: Bool) -> String {
        isToday ? "Recent check-ins" : "Meals that day"
    }

    static func progressSectionTitle(isToday: Bool) -> String {
        isToday ? "Today’s progress" : "Daily totals"
    }

    static func emptyMealsMessage(isToday: Bool) -> String {
        isToday ? "No meals logged today yet." : "No meals logged on this day."
    }

    static func loadingMessage(isToday: Bool) -> String {
        isToday ? "Preparing today’s briefing…" : "Loading that day…"
    }

    static func loadErrorMessage(isToday: Bool) -> String {
        isToday ? "Couldn’t load today’s briefing. Pull to refresh." : "Couldn’t load that day. Pull to refresh."
    }
}
