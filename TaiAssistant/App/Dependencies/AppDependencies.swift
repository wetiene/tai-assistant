import Foundation
import SwiftData

struct AppDependencies {
    let aiService: AIService
    let askTaiGuidance: any AskTaiGuidanceService
    let healthService: HealthService
    let mealRepository: MealRepository
    let goalRepository: GoalRepository
    let conversationRepository: ActiveConversationRepository
    let conversationSession: ActiveConversationSessionController
    let fineTuneCorrectionRepository: FineTuneCorrectionRepository
    let recurringMealRepository: RecurringMealRepository
    let alcoholPlanRepository: AlcoholPlanRepository
    let weightLogRepository: WeightLogRepository
    let appConfigRepository: AppConfigRepository
    let analytics: any AnalyticsClient

    /// True while Ask Tai uses local mock guidance instead of live AI.
    var isAskTaiPreview: Bool {
        askTaiGuidance is MockAskTaiGuidanceService
    }

    /// Production wiring: all repositories read/write the same `ModelContainer` injected into the SwiftUI tree.
    @MainActor
    static func live(modelContainer: ModelContainer, config: RuntimeAppConfig = .default) -> AppDependencies {
        ConversationAttachmentStore.shared = .makeDefault()
        let persistence = LocalPersistenceService(container: modelContainer)
        let aiService = makeAIService(config: config)
        let mealRepository = persistence.makeMealRepository()
        let goalRepository = persistence.makeGoalRepository()
        let conversationRepository = persistence.makeActiveConversationRepository()
        let conversationSession = ActiveConversationSessionController(
            conversationRepository: conversationRepository,
            mealRepository: mealRepository,
            goalRepository: goalRepository,
            aiService: aiService,
            ownerID: config.localOwnerID,
            assistantName: config.assistantName
        )
        return AppDependencies(
            aiService: aiService,
            askTaiGuidance: MockAskTaiGuidanceService(),
            healthService: MockHealthService(),
            mealRepository: mealRepository,
            goalRepository: goalRepository,
            conversationRepository: conversationRepository,
            conversationSession: conversationSession,
            fineTuneCorrectionRepository: persistence.makeFineTuneCorrectionRepository(),
            recurringMealRepository: persistence.makeRecurringMealRepository(),
            alcoholPlanRepository: persistence.makeAlcoholPlanRepository(),
            weightLogRepository: persistence.makeWeightLogRepository(),
            appConfigRepository: persistence.makeAppConfigRepository(),
            analytics: makeAnalyticsClient()
        )
    }

    /// Fully in-memory repositories for UI experiments without SwiftData (no disk container required).
    @MainActor
    static func mocksOnly(config: RuntimeAppConfig = .default) -> AppDependencies {
        ConversationAttachmentStore.shared = .makeEphemeralForTests()
        let mealRepository = MockMealRepository()
        let goalRepository = MockGoalRepository()
        let conversationRepository = InMemoryActiveConversationRepository(
            attachmentStore: ConversationAttachmentStore.shared
        )
        let aiService = makeAIService(config: config)
        let conversationSession = ActiveConversationSessionController(
            conversationRepository: conversationRepository,
            mealRepository: mealRepository,
            goalRepository: goalRepository,
            aiService: aiService,
            ownerID: config.localOwnerID,
            assistantName: config.assistantName
        )
        return AppDependencies(
            aiService: aiService,
            askTaiGuidance: MockAskTaiGuidanceService(),
            healthService: MockHealthService(),
            mealRepository: mealRepository,
            goalRepository: goalRepository,
            conversationRepository: conversationRepository,
            conversationSession: conversationSession,
            fineTuneCorrectionRepository: MockFineTuneCorrectionRepository(),
            recurringMealRepository: MockRecurringMealRepository(),
            alcoholPlanRepository: MockAlcoholPlanRepository(),
            weightLogRepository: MockWeightLogRepository(),
            appConfigRepository: MockAppConfigRepository(),
            analytics: NoOpAnalyticsClient()
        )
    }

    private static func makeAnalyticsClient() -> any AnalyticsClient {
        #if DEBUG
        LoggingAnalyticsClient()
        #else
        NoOpAnalyticsClient()
        #endif
    }

    private static func makeAIService(config: RuntimeAppConfig) -> AIService {
        switch config.mealInterpretationProvider {
        case .mock:
            return MockAIService()
        case .openAIProxy:
            guard let baseURL = config.aiProxyBaseURL else {
                assertionFailure("mealInterpretationProvider is openAIProxy but aiProxyBaseURL is not set; falling back to MockAIService.")
                return MockAIService()
            }
            return OpenAIProxyAIService(
                config: OpenAIProxyServiceConfig(
                    baseURL: baseURL,
                    interpretMealPath: config.aiInterpretMealPath,
                    interpretGoalPath: config.aiInterpretGoalPath,
                    coachPath: config.aiCoachPath,
                    proxyBearerToken: config.aiProxyBearerToken
                )
            )
        }
    }
}
