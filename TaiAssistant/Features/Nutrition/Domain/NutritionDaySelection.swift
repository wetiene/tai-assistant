import Foundation
import Observation

/// Ephemeral app-scoped selected nutrition day for Home and Tai launch context.
///
/// Defaults to today on construction and resets only through explicit selection APIs.
/// Not persisted across app launches in this slice.
@MainActor
@Observable
final class NutritionDaySelection {
    private(set) var selectedDay: NutritionDay
    private let calendar: Calendar

    init(calendar: Calendar = .current, now: Date = .now) {
        self.calendar = calendar
        self.selectedDay = .today(calendar: calendar, now: now)
    }

    var isSelectedDayToday: Bool {
        selectedDay.isToday(calendar: calendar)
    }

    var canSelectNextDay: Bool {
        !isSelectedDayToday
    }

    func selectPreviousDay() {
        select(selectedDay.addingDays(-1, calendar: calendar))
    }

    @discardableResult
    func selectNextDay(now: Date = .now) -> Bool {
        let candidate = selectedDay.addingDays(1, calendar: calendar)
        return select(candidate, now: now)
    }

    /// Selects a nutrition day. Future days are rejected.
    @discardableResult
    func select(_ day: NutritionDay, now: Date = .now) -> Bool {
        guard !day.isAfterToday(calendar: calendar, now: now) else { return false }
        selectedDay = day
        return true
    }

    /// Selects a calendar day containing `date`. Future days are rejected.
    @discardableResult
    func select(containing date: Date, now: Date = .now) -> Bool {
        select(NutritionDay(containing: date, calendar: calendar), now: now)
    }

    func selectToday(now: Date = .now) {
        selectedDay = .today(calendar: calendar, now: now)
    }

    func dayContext() -> NutritionDayContext {
        NutritionDayContext(day: selectedDay)
    }
}

/// Explicit selected-day payload for Tai launch and later capability context.
struct NutritionDayContext: Equatable, Sendable {
    let day: NutritionDay
}
