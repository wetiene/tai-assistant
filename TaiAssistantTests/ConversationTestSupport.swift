import Foundation
@testable import TaiAssistant

@MainActor
enum ConversationTestSupport {
    static func makeGymPlanRepository() -> GymPlanRepository {
        MockGymPlanRepository()
    }

    static func makeGym(
        workoutRepository: WorkoutRepository = MockWorkoutRepository(),
        aiService: AIService = MockAIService(),
        ownerID: String = "test.user"
    ) -> GymCapabilityController {
        GymCapabilityController(
            workoutRepository: workoutRepository,
            aiService: aiService,
            ownerID: ownerID
        )
    }

    static func makeLiveTai(
        mealRepository: MealRepository = MockMealRepository(),
        goalRepository: GoalRepository = MockGoalRepository(),
        aiService: AIService = MockAIService(),
        ownerID: String = "test.user"
    ) -> LiveTaiCapabilityController {
        LiveTaiCapabilityController(
            mealRepository: mealRepository,
            goalRepository: goalRepository,
            aiService: aiService,
            ownerID: ownerID
        )
    }

    static func makeViewModel(
        store: ConversationSessionStore,
        mealRepository: MealRepository = MockMealRepository(),
        workoutRepository: WorkoutRepository = MockWorkoutRepository(),
        gymPlanRepository: GymPlanRepository = MockGymPlanRepository(),
        goalRepository: GoalRepository = MockGoalRepository(),
        interpreter: any CheckInInterpreting = MockCheckInInterpreter(),
        aiService: AIService = MockAIService(),
        ownerID: String = "test.user",
        assistantName: String = "Tai"
    ) -> (ConversationViewModel, MealCapabilityController) {
        let meal = MealCapabilityController(
            mealRepository: mealRepository,
            ownerID: ownerID,
            interpreter: interpreter
        )
        let gym = GymCapabilityController(
            workoutRepository: workoutRepository,
            aiService: aiService,
            ownerID: ownerID
        )
        let liveTai = makeLiveTai(
            mealRepository: mealRepository,
            goalRepository: goalRepository,
            aiService: aiService,
            ownerID: ownerID
        )
        let vm = ConversationViewModel(
            store: store,
            meal: meal,
            gym: gym,
            liveTai: liveTai,
            gymPlanRepository: gymPlanRepository,
            ownerID: ownerID,
            assistantName: assistantName
        )
        return (vm, meal)
    }

    static func makeSession(
        conversationRepository: ActiveConversationRepository,
        mealRepository: MealRepository = MockMealRepository(),
        workoutRepository: WorkoutRepository = MockWorkoutRepository(),
        gymPlanRepository: GymPlanRepository = MockGymPlanRepository(),
        goalRepository: GoalRepository = MockGoalRepository(),
        aiService: AIService = MockAIService(),
        ownerID: String = "test.session",
        assistantName: String = "Tai"
    ) -> ActiveConversationSessionController {
        ActiveConversationSessionController(
            conversationRepository: conversationRepository,
            mealRepository: mealRepository,
            workoutRepository: workoutRepository,
            gymPlanRepository: gymPlanRepository,
            goalRepository: goalRepository,
            aiService: aiService,
            ownerID: ownerID,
            assistantName: assistantName
        )
    }
}
