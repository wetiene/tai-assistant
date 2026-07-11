import SwiftData

enum AppModelContainerFactory {
    static func makeContainer(inMemory: Bool, includePreviewSeedData: Bool = false, ownerID: String = "preview.user") -> ModelContainer {
        let schema = Schema([
            GoalProfile.self,
            DailyTargets.self,
            MealLog.self,
            MealItem.self,
            FineTuneCorrection.self,
            RecurringMeal.self,
            AlcoholPlan.self,
            WeightLog.self,
            AppConfig.self,
            PersistedConversation.self
        ])

        // Architecture decision: one shared container for the scaffold keeps
        // storage boundaries explicit while staying simple for V1.
        let configuration = ModelConfiguration(
            isStoredInMemoryOnly: inMemory
        )

        do {
            let container = try ModelContainer(
                for: schema,
                configurations: [configuration]
            )
            if includePreviewSeedData {
                try PreviewSeedData.seedIfNeeded(in: container, ownerID: ownerID)
            }
            return container
        } catch {
            fatalError("Failed to build SwiftData container: \(error)")
        }
    }
}
