import SwiftData

protocol PersistenceService {
    var container: ModelContainer { get }
    func makeGoalRepository() -> GoalRepository
    func makeMealRepository() -> MealRepository
    func makeFineTuneCorrectionRepository() -> FineTuneCorrectionRepository
    func makeRecurringMealRepository() -> RecurringMealRepository
    func makeAlcoholPlanRepository() -> AlcoholPlanRepository
    func makeWeightLogRepository() -> WeightLogRepository
    func makeAppConfigRepository() -> AppConfigRepository
}

struct LocalPersistenceService: PersistenceService {
    let container: ModelContainer

    init(container: ModelContainer) {
        self.container = container
    }

    func makeGoalRepository() -> GoalRepository {
        LocalSwiftDataGoalRepository(container: container)
    }

    func makeMealRepository() -> MealRepository {
        LocalSwiftDataMealRepository(container: container)
    }

    func makeFineTuneCorrectionRepository() -> FineTuneCorrectionRepository {
        LocalSwiftDataFineTuneCorrectionRepository(container: container)
    }

    func makeRecurringMealRepository() -> RecurringMealRepository {
        LocalSwiftDataRecurringMealRepository(container: container)
    }

    func makeAlcoholPlanRepository() -> AlcoholPlanRepository {
        LocalSwiftDataAlcoholPlanRepository(container: container)
    }

    func makeWeightLogRepository() -> WeightLogRepository {
        LocalSwiftDataWeightLogRepository(container: container)
    }

    func makeAppConfigRepository() -> AppConfigRepository {
        LocalSwiftDataAppConfigRepository(container: container)
    }
}
