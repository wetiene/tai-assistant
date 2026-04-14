import Foundation

struct AppDependencies {
    let aiService: AIService
    let healthService: HealthService
    let mealRepository: MealRepository
    let goalRepository: GoalRepository
    let fineTuneCorrectionRepository: FineTuneCorrectionRepository
    let recurringMealRepository: RecurringMealRepository
    let alcoholPlanRepository: AlcoholPlanRepository
    let weightLogRepository: WeightLogRepository
    let appConfigRepository: AppConfigRepository

    static func makeDefault(useLocalPersistence: Bool = false, inMemoryStore: Bool = false) -> AppDependencies {
        // Architecture decision: ship the app shell with mocks by default so
        // feature teams can build UI/flows before backend and HealthKit wiring exists.
        if useLocalPersistence {
            let container = AppModelContainerFactory.makeContainer(
                inMemory: inMemoryStore,
                includePreviewSeedData: inMemoryStore
            )
            let persistence = LocalPersistenceService(container: container)
            return AppDependencies(
                aiService: MockAIService(),
                healthService: MockHealthService(),
                mealRepository: persistence.makeMealRepository(),
                goalRepository: persistence.makeGoalRepository(),
                fineTuneCorrectionRepository: persistence.makeFineTuneCorrectionRepository(),
                recurringMealRepository: persistence.makeRecurringMealRepository(),
                alcoholPlanRepository: persistence.makeAlcoholPlanRepository(),
                weightLogRepository: persistence.makeWeightLogRepository(),
                appConfigRepository: persistence.makeAppConfigRepository()
            )
        }

        return AppDependencies(
            aiService: MockAIService(),
            healthService: MockHealthService(),
            mealRepository: MockMealRepository(),
            goalRepository: MockGoalRepository(),
            fineTuneCorrectionRepository: MockFineTuneCorrectionRepository(),
            recurringMealRepository: MockRecurringMealRepository(),
            alcoholPlanRepository: MockAlcoholPlanRepository(),
            weightLogRepository: MockWeightLogRepository(),
            appConfigRepository: MockAppConfigRepository()
        )
    }
}
