import XCTest
@testable import TaiAssistant

@MainActor
final class HomeOptimisticDeleteTests: XCTestCase {
    func testLocalBriefingRecomputeReflectsRemovedMealCalories() {
        let ownerID = "home.opt.delete"
        let goal = GoalProfile(ownerID: ownerID, title: "Recomp")
        let targets = DailyTargets(
            calories: 2000,
            proteinGrams: 150,
            carbsGrams: 200,
            fatGrams: 60,
            fiberGrams: 25,
            waterMilliliters: 2500
        )

        let mealA = MealLog(ownerID: ownerID, eatenAt: .now, notes: "Oats")
        mealA.items = [
            MealItem(name: "Oats", amount: 1, unit: "bowl", calories: 400, proteinGrams: 15, carbsGrams: 60, fatGrams: 8, fiberGrams: 5)
        ]
        let mealB = MealLog(ownerID: ownerID, eatenAt: .now.addingTimeInterval(-3600), notes: "Eggs")
        mealB.items = [
            MealItem(name: "Eggs", amount: 2, unit: "each", calories: 200, proteinGrams: 18, carbsGrams: 2, fatGrams: 14, fiberGrams: 0)
        ]

        let beforeInput = CoachBriefingInputFactory.make(
            goal: goal,
            targets: targets,
            todaysMeals: [mealA, mealB],
            assistantName: "Tai"
        )
        let before = DailyCoachBriefingBuilder.build(beforeInput)
        XCTAssertEqual(before.progress.caloriesConsumed, 600)
        XCTAssertEqual(before.progress.mealCountToday, 2)

        let afterInput = CoachBriefingInputFactory.make(
            goal: goal,
            targets: targets,
            todaysMeals: [mealB],
            assistantName: "Tai"
        )
        let after = DailyCoachBriefingBuilder.build(afterInput)
        XCTAssertEqual(after.progress.caloriesConsumed, 200)
        XCTAssertEqual(after.progress.mealCountToday, 1)
    }
}
