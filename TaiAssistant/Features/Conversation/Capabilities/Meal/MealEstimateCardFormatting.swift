import Foundation

/// Display labels for meal estimate cards. Delegates day naming to `HomeNutritionDayFormatting`.
enum MealEstimateCardFormatting {
    static func loggingDateLabel(
        for day: NutritionDay,
        calendar: Calendar = .current,
        now: Date = .now
    ) -> String {
        if day.isToday(calendar: calendar, now: now) {
            return HomeNutritionDayFormatting.pickerLabel(for: day, calendar: calendar, now: now)
        }

        let title = HomeNutritionDayFormatting.navigationTitle(for: day, calendar: calendar, now: now)
        let shortDate = day.start.formatted(.dateTime.day().month(.abbreviated))
        return "Logging for \(title) · \(shortDate)"
    }
}
