import Foundation

/// Display labels for meal estimate cards. Delegates day naming to `HomeNutritionDayFormatting`.
enum MealEstimateCardFormatting {
    static func loggingDateLabel(
        for day: NutritionDay,
        calendar: Calendar = .current,
        now: Date = .now,
        locale: Locale = .current
    ) -> String {
        if day.isToday(calendar: calendar, now: now) {
            return HomeNutritionDayFormatting.pickerLabel(
                for: day,
                calendar: calendar,
                now: now,
                locale: locale
            )
        }

        let title = HomeNutritionDayFormatting.navigationTitle(
            for: day,
            calendar: calendar,
            now: now,
            locale: locale
        )
        let shortDate = day.start.formatted(
            .dateTime.day().month(.abbreviated).locale(locale)
        )
        return "Logging for \(title) · \(shortDate)"
    }
}
