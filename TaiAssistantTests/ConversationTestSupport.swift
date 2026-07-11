import Foundation
@testable import TaiAssistant

@MainActor
enum ConversationTestSupport {
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
        let liveTai = makeLiveTai(
            mealRepository: mealRepository,
            goalRepository: goalRepository,
            aiService: aiService,
            ownerID: ownerID
        )
        let vm = ConversationViewModel(
            store: store,
            meal: meal,
            liveTai: liveTai,
            assistantName: assistantName
        )
        return (vm, meal)
    }

    static func makeSession(
        conversationRepository: ActiveConversationRepository,
        mealRepository: MealRepository = MockMealRepository(),
        goalRepository: GoalRepository = MockGoalRepository(),
        aiService: AIService = MockAIService(),
        ownerID: String = "test.session",
        assistantName: String = "Tai"
    ) -> ActiveConversationSessionController {
        ActiveConversationSessionController(
            conversationRepository: conversationRepository,
            mealRepository: mealRepository,
            goalRepository: goalRepository,
            aiService: aiService,
            ownerID: ownerID,
            assistantName: assistantName
        )
    }
}
