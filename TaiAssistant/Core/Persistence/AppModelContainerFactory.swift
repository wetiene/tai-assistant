import SwiftData

enum AppModelContainerFactory {
    static func makeContainer(inMemory: Bool) -> ModelContainer {
        let schema = Schema([
            MealRecord.self,
            GoalRecord.self
        ])

        // Architecture decision: one shared container for the scaffold keeps
        // storage boundaries explicit while staying simple for V1.
        let configuration = ModelConfiguration(
            isStoredInMemoryOnly: inMemory
        )

        do {
            return try ModelContainer(
                for: schema,
                configurations: [configuration]
            )
        } catch {
            fatalError("Failed to build SwiftData container: \(error)")
        }
    }
}
