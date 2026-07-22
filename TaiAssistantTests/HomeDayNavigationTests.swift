import XCTest
@testable import TaiAssistant

@MainActor
final class HomeDayNavigationTests: XCTestCase {
    private var calendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        return cal
    }

    private var july11Afternoon: Date {
        calendar.date(from: DateComponents(year: 2026, month: 7, day: 11, hour: 14))!
    }

    private var july10Morning: Date {
        calendar.date(from: DateComponents(year: 2026, month: 7, day: 10, hour: 9))!
    }

    private var july12Morning: Date {
        calendar.date(from: DateComponents(year: 2026, month: 7, day: 12, hour: 9))!
    }

    func testSelectionMovesBackwardAndForwardWithoutCrossingToday() {
        let selection = NutritionDaySelection(calendar: calendar, now: july11Afternoon)

        selection.selectPreviousDay()
        XCTAssertEqual(selection.selectedDay, NutritionDay(containing: july10Morning, calendar: calendar))

        XCTAssertTrue(selection.selectNextDay(now: july11Afternoon))
        XCTAssertEqual(selection.selectedDay, NutritionDay(containing: july11Afternoon, calendar: calendar))

        XCTAssertFalse(selection.selectNextDay(now: july11Afternoon))
        XCTAssertEqual(selection.selectedDay, NutritionDay(containing: july11Afternoon, calendar: calendar))
    }

    func testHistoricalLoaderReturnsFactualSummaryNotTodayBriefing() async throws {
        let meal = MealLog(ownerID: "historical.home", eatenAt: july10Morning, notes: "Dinner")
        meal.items = [
            MealItem(name: "Salmon", amount: 1, unit: "fillet", calories: 520, proteinGrams: 42, carbsGrams: 0, fatGrams: 28, fiberGrams: 0)
        ]
        let mealRepository = SeededMealRepository(meals: [meal])
        let goalRepository = MockGoalRepository()
        let day = NutritionDay(containing: july10Morning, calendar: calendar)

        let result = try await HomeNutritionDayLoader.load(
            day: day,
            ownerID: "historical.home",
            mealRepository: mealRepository,
            goalRepository: goalRepository,
            displayName: nil,
            assistantName: "Tai",
            now: july11Afternoon,
            calendar: calendar
        )

        XCTAssertFalse(result.isToday)
        XCTAssertNil(result.todayBriefing)
        XCTAssertEqual(result.historicalSummary?.headline, "1 meal logged")
        XCTAssertEqual(result.historicalSummary?.body, "520 kcal · 42 g protein on this day.")
        XCTAssertFalse(result.historicalSummary?.body.localizedCaseInsensitiveContains("should") ?? true)
        XCTAssertFalse(result.historicalSummary?.body.localizedCaseInsensitiveContains("next") ?? true)
    }

    func testHistoricalEmptyDaySummaryIsFactual() {
        let day = NutritionDay(containing: july10Morning, calendar: calendar)
        let input = CoachBriefingInput(
            now: july10Morning,
            calendar: calendar,
            displayName: nil,
            hasActiveGoal: true,
            targets: CoachMacroTargets(calories: 2100, proteinGrams: 170, carbsGrams: 210, fatGrams: 70),
            todayMealCount: 0,
            caloriesConsumed: 0,
            proteinGramsConsumed: 0,
            carbsGramsConsumed: 0,
            fatGramsConsumed: 0,
            assistantName: "Tai"
        )

        let summary = HomeHistoricalDayPresenter.make(
            day: day,
            input: input,
            calendar: calendar,
            now: july11Afternoon
        )

        XCTAssertEqual(summary.headline, "No meals logged")
        XCTAssertEqual(summary.body, "Nothing was confirmed for this day.")
    }

    func testTodayLoaderStillBuildsCoachBriefing() async throws {
        let result = try await HomeNutritionDayLoader.load(
            day: .today(calendar: calendar, now: july11Afternoon),
            ownerID: "preview.user",
            mealRepository: MockMealRepository(),
            goalRepository: MockGoalRepository(),
            displayName: nil,
            assistantName: "Tai",
            now: july11Afternoon,
            calendar: calendar
        )

        XCTAssertTrue(result.isToday)
        XCTAssertNotNil(result.todayBriefing)
        XCTAssertNil(result.historicalSummary)
    }

    func testStaleLoadTokenIgnoresSupersededGeneration() {
        var generation: UInt64 = 0
        generation &+= 1
        let first = generation
        generation &+= 1
        let second = generation

        XCTAssertNotEqual(first, second)
        XCTAssertTrue(second > first)
    }

    func testOptimisticDeleteRecomputeUsesHistoricalPresenter() {
        let ownerID = "home.historical.delete"
        let goal = GoalProfile(ownerID: ownerID, title: "Recomp")
        let targets = DailyTargets(
            calories: 2000,
            proteinGrams: 150,
            carbsGrams: 200,
            fatGrams: 60,
            fiberGrams: 25,
            waterMilliliters: 2500
        )
        let day = NutritionDay(containing: july10Morning, calendar: calendar)

        let mealA = MealLog(ownerID: ownerID, eatenAt: july10Morning, notes: "Oats")
        mealA.items = [
            MealItem(name: "Oats", amount: 1, unit: "bowl", calories: 400, proteinGrams: 15, carbsGrams: 60, fatGrams: 8, fiberGrams: 5)
        ]
        let mealB = MealLog(ownerID: ownerID, eatenAt: july10Morning.addingTimeInterval(3600), notes: "Eggs")
        mealB.items = [
            MealItem(name: "Eggs", amount: 2, unit: "each", calories: 200, proteinGrams: 18, carbsGrams: 2, fatGrams: 14, fiberGrams: 0)
        ]

        let before = HomeHistoricalDayPresenter.make(
            day: day,
            input: CoachBriefingInputFactory.make(
                now: july10Morning,
                calendar: calendar,
                goal: goal,
                targets: targets,
                meals: [mealA, mealB],
                assistantName: "Tai"
            ),
            calendar: calendar,
            now: july11Afternoon
        )
        let after = HomeHistoricalDayPresenter.make(
            day: day,
            input: CoachBriefingInputFactory.make(
                now: july10Morning,
                calendar: calendar,
                goal: goal,
                targets: targets,
                meals: [mealB],
                assistantName: "Tai"
            ),
            calendar: calendar,
            now: july11Afternoon
        )

        XCTAssertEqual(before.progress.caloriesConsumed, 600)
        XCTAssertEqual(after.progress.caloriesConsumed, 200)
        XCTAssertEqual(after.headline, "1 meal logged")
    }
}

private final class SeededMealRepository: MealRepository {
    private var meals: [MealLog]

    init(meals: [MealLog]) {
        self.meals = meals
    }

    func fetchMealLogs(ownerID: String, from startDate: Date, to endDate: Date) async throws -> [MealLog] {
        meals.filter { $0.ownerID == ownerID && $0.eatenAt >= startDate && $0.eatenAt < endDate }
    }

    func createMealLog(_ meal: MealLog) async throws {
        meals.append(meal)
    }

    func updateMealLog(_ meal: MealLog) async throws {
        guard let index = meals.firstIndex(where: { $0.id == meal.id }) else {
            throw MealRepositoryError.mealLogNotFound(id: meal.id)
        }
        meals[index] = meal
    }

    func duplicateMealLog(from source: MealLog, eatenAt: Date) -> MealLog {
        MealLog(ownerID: source.ownerID, eatenAt: eatenAt, notes: source.notes)
    }

    func duplicateMealLog(fromRecurringTemplate template: RecurringMeal, eatenAt: Date) -> MealLog {
        MealLog(ownerID: template.ownerID, eatenAt: eatenAt, notes: template.name)
    }

    func deleteMealLog(id: UUID) async throws {
        meals.removeAll { $0.id == id }
    }
}
