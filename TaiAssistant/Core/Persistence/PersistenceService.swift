import SwiftData

protocol PersistenceService {
    var container: ModelContainer { get }
    func makeGoalRepository() -> GoalRepository
    func makeMealRepository() -> MealRepository
    func makeWorkoutRepository() -> WorkoutRepository
    func makeGymPlanRepository() -> GymPlanRepository
    func makeActiveConversationRepository() -> ActiveConversationRepository
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

    func makeWorkoutRepository() -> WorkoutRepository {
        LocalSwiftDataWorkoutRepository(container: container)
    }

    func makeGymPlanRepository() -> GymPlanRepository {
        LocalSwiftDataGymPlanRepository(container: container)
    }

    func makeActiveConversationRepository() -> ActiveConversationRepository {
        LocalSwiftDataActiveConversationRepository(
            container: container,
            attachmentStore: ConversationAttachmentStore.shared
        )
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
