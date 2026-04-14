import Foundation
import SwiftData

enum PreviewSeedData {
    static func seedIfNeeded(in container: ModelContainer, ownerID: String = "preview.user") throws {
        let context = ModelContext(container)
        let existing = try context.fetch(FetchDescriptor<GoalProfile>())
        guard existing.isEmpty else { return }

        let targets = DailyTargets(
            calories: 2100,
            proteinGrams: 150,
            carbsGrams: 210,
            fatGrams: 70,
            fiberGrams: 32,
            waterMilliliters: 2600
        )
        let goalProfile = GoalProfile(
            ownerID: ownerID,
            title: "Lean maintenance",
            notes: "Default preview profile for dashboard and goal flows."
        )
        goalProfile.dailyTargets = targets

        let mealLog = MealLog(
            ownerID: ownerID,
            eatenAt: .now,
            timing: .lunch,
            notes: "Structured logging only, no photos.",
            alcoholStandardDrinks: 1
        )
        mealLog.items = [
            MealItem(
                name: "Grilled salmon",
                amount: 150,
                unit: "g",
                calories: 310,
                proteinGrams: 34,
                carbsGrams: 0,
                fatGrams: 20,
                fiberGrams: 0
            ),
            MealItem(
                name: "Quinoa",
                amount: 160,
                unit: "g",
                calories: 200,
                proteinGrams: 8,
                carbsGrams: 36,
                fatGrams: 3,
                fiberGrams: 5
            ),
            MealItem(
                name: "Red wine",
                amount: 150,
                unit: "ml",
                calories: 125,
                proteinGrams: 0,
                carbsGrams: 4,
                fatGrams: 0,
                fiberGrams: 0,
                alcoholGrams: 14
            )
        ]

        let recurringMeal = RecurringMeal(
            ownerID: ownerID,
            visibility: .private,
            name: "Weekday breakfast",
            cadenceDays: 1,
            preferredTiming: .breakfast
        )
        recurringMeal.items = [
            MealItem(
                name: "Greek yogurt",
                amount: 200,
                unit: "g",
                calories: 190,
                proteinGrams: 20,
                carbsGrams: 9,
                fatGrams: 9,
                fiberGrams: 0
            ),
            MealItem(
                name: "Blueberries",
                amount: 80,
                unit: "g",
                calories: 45,
                proteinGrams: 1,
                carbsGrams: 11,
                fatGrams: 0,
                fiberGrams: 2
            )
        ]

        let alcoholPlan = AlcoholPlan(
            ownerID: ownerID,
            maxStandardDrinksPerDay: 2,
            maxStandardDrinksPerWeek: 8,
            alcoholFreeDaysTarget: 3
        )

        let weightLog = WeightLog(
            ownerID: ownerID,
            loggedAt: .now.addingTimeInterval(-86_400),
            weightKilograms: 74.2,
            bodyFatPercent: 18.4
        )

        let correction = FineTuneCorrection(
            ownerID: ownerID,
            mealLogID: mealLog.id,
            fieldName: "alcoholStandardDrinks",
            previousValue: "0",
            correctedValue: "1",
            source: .user,
            reason: "User added wine to lunch."
        )

        let appConfig = AppConfig(
            ownerID: ownerID,
            measurementSystem: .metric,
            timeZoneIdentifier: TimeZone.current.identifier,
            healthSyncEnabled: false
        )

        context.insert(goalProfile)
        context.insert(targets)
        context.insert(mealLog)
        context.insert(recurringMeal)
        context.insert(alcoholPlan)
        context.insert(weightLog)
        context.insert(correction)
        context.insert(appConfig)
        try context.save()
    }
}
