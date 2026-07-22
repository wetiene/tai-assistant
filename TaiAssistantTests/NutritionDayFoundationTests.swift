import Foundation
import XCTest
@testable import TaiAssistant

@MainActor
final class NutritionDayFoundationTests: XCTestCase {
    private var calendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        return cal
    }

    private var july11Afternoon: Date {
        calendar.date(from: DateComponents(year: 2026, month: 7, day: 11, hour: 14, minute: 30))!
    }

    private var july10Morning: Date {
        calendar.date(from: DateComponents(year: 2026, month: 7, day: 10, hour: 9))!
    }

    private var july12Morning: Date {
        calendar.date(from: DateComponents(year: 2026, month: 7, day: 12, hour: 9))!
    }

    func testNutritionDayNormalizesToStartOfDay() {
        let day = NutritionDay(containing: july11Afternoon, calendar: calendar)
        let expectedStart = calendar.startOfDay(for: july11Afternoon)
        XCTAssertEqual(day.start, expectedStart)
    }

    func testQueryBoundsAreHalfOpenDayWindow() {
        let day = NutritionDay(containing: july11Afternoon, calendar: calendar)
        let bounds = day.queryBounds(calendar: calendar)

        XCTAssertEqual(bounds.start, calendar.startOfDay(for: july11Afternoon))
        XCTAssertEqual(bounds.end, calendar.date(byAdding: .day, value: 1, to: bounds.start))

        XCTAssertTrue(day.contains(july11Afternoon, calendar: calendar))
        XCTAssertFalse(day.contains(bounds.end, calendar: calendar))
        XCTAssertFalse(day.contains(july10Morning, calendar: calendar))
    }

    func testCoachBriefingInputFactoryDelegatesDayBoundsToNutritionDay() {
        let factoryBounds = CoachBriefingInputFactory.dayBounds(for: july11Afternoon, calendar: calendar)
        let dayBounds = NutritionDay(containing: july11Afternoon, calendar: calendar).queryBounds(calendar: calendar)
        XCTAssertEqual(factoryBounds.start, dayBounds.start)
        XCTAssertEqual(factoryBounds.end, dayBounds.end)
    }

    func testNutritionDayAggregationSumsMealsForExplicitDay() {
        let ownerID = "nutrition.day.test"
        let onDay = MealLog(ownerID: ownerID, eatenAt: july11Afternoon, notes: "Lunch")
        onDay.items = [
            MealItem(name: "Chicken", amount: 1, unit: "serving", calories: 400, proteinGrams: 40, carbsGrams: 10, fatGrams: 12, fiberGrams: 0)
        ]
        let otherDay = MealLog(ownerID: ownerID, eatenAt: july10Morning, notes: "Yesterday")
        otherDay.items = [
            MealItem(name: "Oats", amount: 1, unit: "bowl", calories: 300, proteinGrams: 12, carbsGrams: 45, fatGrams: 6, fiberGrams: 4)
        ]

        let totals = NutritionDayAggregation.macroTotals(from: [onDay])
        XCTAssertEqual(totals.mealCount, 1)
        XCTAssertEqual(totals.calories, 400)
        XCTAssertEqual(totals.proteinGrams, 40)

        let input = CoachBriefingInputFactory.make(
            now: july11Afternoon,
            calendar: calendar,
            goal: nil,
            targets: nil,
            meals: [onDay],
            assistantName: "Tai"
        )
        XCTAssertEqual(input.todayMealCount, 1)
        XCTAssertEqual(input.caloriesConsumed, 400)
        XCTAssertNotEqual(input.caloriesConsumed, 700)
        XCTAssertEqual(NutritionDayAggregation.macroTotals(from: [onDay, otherDay]).calories, 700)
    }

    func testMealRepositoryFetchesByNutritionDay() async throws {
        let repo = MockMealRepository()
        let ownerID = "preview.user"
        let day = NutritionDay.today()
        let meals = try await repo.fetchMealLogs(ownerID: ownerID, on: day)
        XCTAssertFalse(meals.isEmpty)
        XCTAssertTrue(meals.allSatisfy { day.contains($0.eatenAt) })
    }

    func testHomeNutritionDayLoaderLoadsExplicitDay() async throws {
        let mealRepository = MockMealRepository()
        let goalRepository = MockGoalRepository()
        let day = NutritionDay(containing: july11Afternoon, calendar: calendar)

        let result = try await HomeNutritionDayLoader.load(
            day: day,
            ownerID: "preview.user",
            mealRepository: mealRepository,
            goalRepository: goalRepository,
            displayName: nil,
            assistantName: "Tai",
            now: july11Afternoon,
            calendar: calendar
        )

        XCTAssertEqual(result.day, day)
        XCTAssertEqual(result.briefingInput.todayMealCount, result.meals.count)
    }

    func testNutritionDaySelectionDefaultsToTodayAndRejectsFutureDays() {
        let selection = NutritionDaySelection(calendar: calendar, now: july11Afternoon)
        XCTAssertEqual(selection.selectedDay, NutritionDay(containing: july11Afternoon, calendar: calendar))

        XCTAssertFalse(selection.select(NutritionDay(containing: july12Morning, calendar: calendar), now: july11Afternoon))
        XCTAssertEqual(selection.selectedDay, NutritionDay(containing: july11Afternoon, calendar: calendar))

        XCTAssertTrue(selection.select(NutritionDay(containing: july10Morning, calendar: calendar), now: july11Afternoon))
        XCTAssertEqual(selection.selectedDay, NutritionDay(containing: july10Morning, calendar: calendar))

        selection.selectToday(now: july11Afternoon)
        XCTAssertEqual(selection.selectedDay, NutritionDay(containing: july11Afternoon, calendar: calendar))
    }

    func testMealLogAuditSemanticsAndLateEntryDetection() {
        let occurrence = july10Morning
        var components = calendar.dateComponents([.year, .month, .day], from: july11Afternoon)
        components.hour = 8
        let recorded = calendar.date(from: components)!

        let meal = MealLog(
            ownerID: "audit.test",
            eatenAt: occurrence,
            notes: "Late entry",
            createdAt: recorded,
            updatedAt: recorded
        )

        XCTAssertEqual(meal.nutritionDay(calendar: calendar), NutritionDay(containing: july10Morning, calendar: calendar))
        XCTAssertTrue(meal.wasRecordedAfterOccurrenceDay(calendar: calendar))
    }

    func testTaiLaunchIntentCarriesOptionalDayContextWithoutChangingDefaults() {
        let dayContext = NutritionDayContext(day: NutritionDay(containing: july10Morning, calendar: calendar))
        let intent = TaiLaunchIntent.fromHomeDestination(.checkInMeal, dayContext: dayContext)

        XCTAssertEqual(intent.kind, .startMealCapture)
        XCTAssertEqual(intent.dayContext, dayContext)
        XCTAssertNil(TaiLaunchIntent.startMealCapture.dayContext)
    }

    func testDefaultOccurrenceTimestampUsesNowOnTodayAndTimingDefaultsOnPastDays() {
        let today = NutritionDay(containing: july11Afternoon, calendar: calendar)
        XCTAssertEqual(
            today.defaultOccurrenceTimestamp(timing: .lunch, calendar: calendar, now: july11Afternoon),
            july11Afternoon
        )

        let pastDay = NutritionDay(containing: july10Morning, calendar: calendar)
        let dinnerDefault = pastDay.defaultOccurrenceTimestamp(timing: .dinner, calendar: calendar, now: july11Afternoon)
        XCTAssertTrue(pastDay.contains(dinnerDefault, calendar: calendar))
        let dinnerHour = calendar.component(.hour, from: dinnerDefault)
        XCTAssertEqual(dinnerHour, 19)
    }

    func testResolveOccurrenceTimestampPrefersOnDayAIGuessForHistoricalDay() {
        let pastDay = NutritionDay(containing: july10Morning, calendar: calendar)
        let onDayGuess = calendar.date(from: DateComponents(year: 2026, month: 7, day: 10, hour: 13, minute: 15))!

        let resolved = pastDay.resolveOccurrenceTimestamp(
            aiGuess: onDayGuess,
            timing: .lunch,
            calendar: calendar,
            now: july11Afternoon
        )

        XCTAssertEqual(resolved, onDayGuess)
    }

    func testResolveOccurrenceTimestampFallsBackToTimingDefaultWhenAIGuessIsToday() {
        let pastDay = NutritionDay(containing: july10Morning, calendar: calendar)

        let resolved = pastDay.resolveOccurrenceTimestamp(
            aiGuess: july11Afternoon,
            timing: .dinner,
            calendar: calendar,
            now: july11Afternoon
        )

        XCTAssertTrue(pastDay.contains(resolved, calendar: calendar))
        XCTAssertEqual(calendar.component(.hour, from: resolved), 19)
    }
}
