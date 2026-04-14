import Foundation

struct AppDependencies {
    let aiService: AIService
    let healthService: HealthService
    let mealRepository: MealRepository
    let goalRepository: GoalRepository

    static func makeDefault() -> AppDependencies {
        // Architecture decision: ship the app shell with mocks by default so
        // feature teams can build UI/flows before backend and HealthKit wiring exists.
        AppDependencies(
            aiService: MockAIService(),
            healthService: MockHealthService(),
            mealRepository: MockMealRepository(),
            goalRepository: MockGoalRepository()
        )
    }
}
