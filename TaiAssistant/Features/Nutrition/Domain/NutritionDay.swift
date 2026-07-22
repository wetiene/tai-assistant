import Foundation

/// A single nutrition day in the device-local calendar.
///
/// Day membership for meals is derived from `MealLog.eatenAt` compared against
/// `[start, end)` where `start` is `calendar.startOfDay` and `end` is the next midnight.
struct NutritionDay: Equatable, Sendable, Hashable {
    /// Normalized start instant for this nutrition day (`calendar.startOfDay`).
    let start: Date

    init(containing date: Date, calendar: Calendar = .current) {
        self.start = calendar.startOfDay(for: date)
    }

    static func today(calendar: Calendar = .current, now: Date = .now) -> NutritionDay {
        NutritionDay(containing: now, calendar: calendar)
    }

    /// Half-open query range `[start, end)` for repository fetches on `MealLog.eatenAt`.
    func queryBounds(calendar: Calendar = .current) -> (start: Date, end: Date) {
        let normalizedStart = calendar.startOfDay(for: start)
        let end = calendar.date(byAdding: .day, value: 1, to: normalizedStart)
            ?? normalizedStart.addingTimeInterval(86_400)
        return (normalizedStart, end)
    }

    func contains(_ date: Date, calendar: Calendar = .current) -> Bool {
        let bounds = queryBounds(calendar: calendar)
        return date >= bounds.start && date < bounds.end
    }

    func isToday(calendar: Calendar = .current, now: Date = .now) -> Bool {
        self == NutritionDay(containing: now, calendar: calendar)
    }

    /// True when this day is strictly after the calendar day containing `now`.
    func isAfterToday(calendar: Calendar = .current, now: Date = .now) -> Bool {
        start > calendar.startOfDay(for: now)
    }

    /// Default `MealLog.eatenAt` when logging against this day (used by later historical-logging slices).
    func defaultOccurrenceTimestamp(
        timing: MealTiming = .other,
        calendar: Calendar = .current,
        now: Date = .now
    ) -> Date {
        if isToday(calendar: calendar, now: now) {
            return now
        }

        var components = calendar.dateComponents([.year, .month, .day], from: start)
        switch timing {
        case .breakfast:
            components.hour = 8
            components.minute = 0
        case .lunch:
            components.hour = 12
            components.minute = 30
        case .dinner:
            components.hour = 19
            components.minute = 0
        case .snack:
            components.hour = 15
            components.minute = 0
        case .other:
            components.hour = 12
            components.minute = 0
        }
        return calendar.date(from: components) ?? start
    }

    func addingDays(_ value: Int, calendar: Calendar = .current) -> NutritionDay {
        let shifted = calendar.date(byAdding: .day, value: value, to: start) ?? start
        return NutritionDay(containing: shifted, calendar: calendar)
    }
}
