import Foundation
import SwiftData

struct AppDependencies {
    let aiService: AIService
    let askTaiGuidance: any AskTaiGuidanceService
    let healthService: HealthService
    let mealRepository: MealRepository
    let goalRepository: GoalRepository
    let fineTuneCorrectionRepository: FineTuneCorrectionRepository
    let recurringMealRepository: RecurringMealRepository
    let alcoholPlanRepository: AlcoholPlanRepository
    let weightLogRepository: WeightLogRepository
    let appConfigRepository: AppConfigRepository

    /// Production wiring: all repositories read/write the same `ModelContainer` injected into the SwiftUI tree.
    static func live(modelContainer: ModelContainer) -> AppDependencies {
        let persistence = LocalPersistenceService(container: modelContainer)
        return AppDependencies(
            aiService: MockAIService(),
            askTaiGuidance: MockAskTaiGuidanceService(),
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

    /// Fully in-memory repositories for UI experiments without SwiftData (no disk container required).
    static func mocksOnly() -> AppDependencies {
        AppDependencies(
            aiService: MockAIService(),
            askTaiGuidance: MockAskTaiGuidanceService(),
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
