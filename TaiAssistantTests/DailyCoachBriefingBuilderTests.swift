import Foundation
import XCTest
@testable import TaiAssistant

final class DailyCoachBriefingBuilderTests: XCTestCase {
    private var calendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        return cal
    }

    private var afternoon: Date {
        calendar.date(from: DateComponents(year: 2026, month: 7, day: 11, hour: 14))!
    }

    private var morning: Date {
        calendar.date(from: DateComponents(year: 2026, month: 7, day: 11, hour: 8))!
    }

    private let defaultTargets = CoachMacroTargets(
        calories: 2100,
        proteinGrams: 170,
        carbsGrams: 210,
        fatGrams: 70
    )

    func testNoGoal() {
        let briefing = DailyCoachBriefingBuilder.build(
            baseInput(hasActiveGoal: false, targets: nil, mealCount: 0)
        )
        XCTAssertEqual(briefing.recommendation.destination, .reviewGoal)
        XCTAssertTrue(briefing.body.lowercased().contains("goal"))
        XCTAssertEqual(briefing.recommendation.actionTitle, "Set your goal")
        assertEvidenceMatchesRecommendation(briefing)
    }

    func testGoalExistsButNoMealsLogged() {
        let briefing = DailyCoachBriefingBuilder.build(
            baseInput(hasActiveGoal: true, targets: defaultTargets, mealCount: 0)
        )
        XCTAssertEqual(briefing.recommendation.destination, .checkInMeal)
        XCTAssertEqual(briefing.recommendation.focusTitle, "Check in your first meal")
        XCTAssertTrue(briefing.recommendation.reason.evidencePoints.contains { $0.contains("No meals") })
        assertEvidenceMatchesRecommendation(briefing)
    }

    func testProteinSignificantlyBehind() {
        let briefing = DailyCoachBriefingBuilder.build(
            baseInput(
                hasActiveGoal: true,
                targets: defaultTargets,
                mealCount: 2,
                calories: 900,
                protein: 62,
                carbs: 80,
                fat: 30
            )
        )
        XCTAssertEqual(briefing.recommendation.focusTitle, "Add protein next")
        XCTAssertTrue(briefing.body.lowercased().contains("protein"))
        XCTAssertTrue(briefing.recommendation.reason.evidencePoints.contains { $0.contains("62g") })
        XCTAssertTrue(briefing.recommendation.reason.evidencePoints.contains { $0.contains("170g") })
        assertEvidenceMatchesRecommendation(briefing)
    }

    func testCaloriesNearTarget() {
        let briefing = DailyCoachBriefingBuilder.build(
            baseInput(
                hasActiveGoal: true,
                targets: defaultTargets,
                mealCount: 3,
                calories: 2000,
                protein: 160,
                carbs: 200,
                fat: 65
            )
        )
        XCTAssertEqual(briefing.recommendation.destination, .checkInMeal)
        XCTAssertTrue(
            briefing.recommendation.focusTitle.lowercased().contains("balanced")
                || briefing.recommendation.focusTitle.lowercased().contains("lighter")
        )
        assertEvidenceMatchesRecommendation(briefing)
    }

    func testTargetsBroadlyOnTrack() {
        let briefing = DailyCoachBriefingBuilder.build(
            baseInput(
                hasActiveGoal: true,
                targets: defaultTargets,
                mealCount: 2,
                calories: 1100,
                protein: 140,
                carbs: 120,
                fat: 40
            )
        )
        XCTAssertTrue(briefing.headline.lowercased().contains("on track"))
        XCTAssertEqual(briefing.recommendation.focusTitle, "Keep your next meal balanced")
        assertEvidenceMatchesRecommendation(briefing)
    }

    func testMissingOrZeroTargets() {
        let zeroTargets = CoachMacroTargets(calories: 0, proteinGrams: 0, carbsGrams: 0, fatGrams: 0)
        let briefing = DailyCoachBriefingBuilder.build(
            baseInput(hasActiveGoal: true, targets: zeroTargets, mealCount: 1, calories: 400, protein: 20)
        )
        XCTAssertEqual(briefing.recommendation.destination, .reviewGoal)
        XCTAssertTrue(briefing.body.lowercased().contains("target"))
        assertEvidenceMatchesRecommendation(briefing)
    }

    func testDataFromAnotherDayDoesNotAffectToday() {
        // Builder only receives today's aggregates; yesterday must not be passed in.
        let todayOnly = DailyCoachBriefingBuilder.build(
            baseInput(
                hasActiveGoal: true,
                targets: defaultTargets,
                mealCount: 0,
                calories: 0,
                protein: 0
            )
        )
        XCTAssertEqual(todayOnly.recommendation.focusTitle, "Check in your first meal")
        XCTAssertEqual(todayOnly.progress.mealCountToday, 0)
        XCTAssertEqual(todayOnly.progress.caloriesConsumed, 0)
    }

    func testExplanationEvidenceMatchesRecommendation() {
        let briefing = DailyCoachBriefingBuilder.build(
            baseInput(
                hasActiveGoal: true,
                targets: defaultTargets,
                mealCount: 1,
                calories: 500,
                protein: 40,
                carbs: 50,
                fat: 15
            )
        )
        assertEvidenceMatchesRecommendation(briefing)
        XCTAssertFalse(briefing.recommendation.reason.evidencePoints.isEmpty)
        XCTAssertFalse(briefing.recommendation.reason.summary.isEmpty)
    }

    func testGreetingUsesDisplayNameAndTimeOfDay() {
        let morningGreeting = DailyCoachBriefingBuilder.makeGreeting(
            now: morning,
            calendar: calendar,
            displayName: "Alex"
        )
        XCTAssertEqual(morningGreeting, "Good morning, Alex")

        let afternoonGreeting = DailyCoachBriefingBuilder.makeGreeting(
            now: afternoon,
            calendar: calendar,
            displayName: nil
        )
        XCTAssertEqual(afternoonGreeting, "Good afternoon")
    }

    func testGreetingDoesNotHardcodeWilliam() {
        let greeting = DailyCoachBriefingBuilder.makeGreeting(
            now: afternoon,
            calendar: calendar,
            displayName: nil
        )
        XCTAssertFalse(greeting.lowercased().contains("william"))
    }

    // MARK: - Helpers

    private func baseInput(
        hasActiveGoal: Bool,
        targets: CoachMacroTargets?,
        mealCount: Int,
        calories: Int = 0,
        protein: Double = 0,
        carbs: Double = 0,
        fat: Double = 0,
        displayName: String? = nil
    ) -> CoachBriefingInput {
        CoachBriefingInput(
            now: afternoon,
            calendar: calendar,
            displayName: displayName,
            hasActiveGoal: hasActiveGoal,
            targets: targets,
            todayMealCount: mealCount,
            caloriesConsumed: calories,
            proteinGramsConsumed: protein,
            carbsGramsConsumed: carbs,
            fatGramsConsumed: fat,
            assistantName: "Tai"
        )
    }

    private func assertEvidenceMatchesRecommendation(_ briefing: DailyCoachBriefing) {
        let reason = briefing.recommendation.reason
        switch briefing.recommendation.destination {
        case .reviewGoal:
            XCTAssertTrue(
                reason.evidencePoints.contains { $0.lowercased().contains("goal") || $0.lowercased().contains("target") }
            )
        case .checkInMeal:
            XCTAssertTrue(
                reason.evidencePoints.contains { $0.lowercased().contains("meal") || $0.lowercased().contains("protein") || $0.lowercased().contains("calorie") }
            )
        }

        if briefing.recommendation.focusTitle.lowercased().contains("protein") {
            XCTAssertTrue(reason.summary.lowercased().contains("protein"))
            XCTAssertTrue(reason.evidencePoints.contains { $0.lowercased().contains("protein") })
        }
    }
}
