import XCTest
@testable import TaiAssistant

@MainActor
final class ConversationMealIntentRoutingTests: XCTestCase {
    override func setUp() {
        super.setUp()
        ConversationAttachmentStore.shared = .makeEphemeralForTests()
        AIDataProcessingConsentStore.resetForTests()
        AIDataProcessingConsentStore.accept(version: AIDataProcessingConsentStore.liveTaiVersion)
    }

    override func tearDown() {
        AIDataProcessingConsentStore.resetForTests()
        super.tearDown()
    }

    // MARK: - Classifier

    func testMealStatementsClassifyAsMealLog() {
        let samples = [
            "Had half Australian pizza from Pepper Pizza Shop in North Lakes",
            "Ate chicken and rice",
            "Breakfast was oats",
            "Two coffees",
            "Protein shake",
            "Dinner: salmon and vegetables",
            "Just ate a burger and chips",
            "Had chicken and rice",
            "Lunch was sushi",
        ]
        for sample in samples {
            XCTAssertEqual(
                ConversationMealIntentClassifier.classify(sample),
                .mealLogStatement,
                sample
            )
            XCTAssertEqual(
                ConversationRouter.route(text: sample, hasPhoto: false, targetedMealDraftID: nil),
                .mealInterpret,
                sample
            )
        }
    }

    func testFoodQuestionsClassifyAsCoaching() {
        let samples = [
            "Can I have pizza tonight?",
            "What should I eat for dinner?",
            "How much protein do I have left?",
            "Was my lunch too heavy?",
            "What did I eat today?",
            "Can I have dessert tonight?",
        ]
        for sample in samples {
            XCTAssertEqual(
                ConversationMealIntentClassifier.classify(sample),
                .coachingQuestion,
                sample
            )
            XCTAssertEqual(
                ConversationRouter.route(text: sample, hasPhoto: false, targetedMealDraftID: nil),
                .liveTai,
                sample
            )
        }
    }

    func testAmbiguousSingleFoodToken() {
        for sample in ["Pizza", "Coffee", "Chicken wrap".components(separatedBy: " ").first!] {
            // "Pizza" / "Coffee" only
            _ = sample
        }
        XCTAssertEqual(ConversationMealIntentClassifier.classify("Pizza"), .ambiguousFoodFragment)
        XCTAssertEqual(ConversationMealIntentClassifier.classify("Coffee"), .ambiguousFoodFragment)
        XCTAssertEqual(
            ConversationRouter.route(text: "Pizza", hasPhoto: false, targetedMealDraftID: nil),
            .clarifyMealOrAsk
        )
        // Multi-token food is a meal statement, not clarify.
        XCTAssertEqual(ConversationMealIntentClassifier.classify("Chicken wrap"), .mealLogStatement)
    }

    // MARK: - Integration

    func testPizzaStatementProducesMealCardNotLiveTai() async {
        let spy = SpyAIService()
        let mealRepo = RecordingMealRepository()
        let store = ConversationSessionStore()
        let (vm, _) = ConversationTestSupport.makeViewModel(
            store: store,
            mealRepository: mealRepo,
            interpreter: AIServiceCheckInInterpreter(aiService: spy, ownerID: "test.user"),
            aiService: spy
        )
        vm.startIfNeeded()
        vm.updateComposerText("Had half Australian pizza from Pepper Pizza Shop in North Lakes")
        await vm.sendComposer()

        XCTAssertEqual(spy.interpretMealCallCount, 1)
        XCTAssertEqual(spy.coachCallCount, 0)
        XCTAssertEqual(mealRepo.createCallCount, 0)
        XCTAssertTrue(store.active.messages.contains {
            $0.card?.typeID == MealCapabilityID.estimateCardType
        })
    }

    func testFoodQuestionCallsCoachNotMeal() async {
        let spy = SpyAIService()
        let store = ConversationSessionStore()
        let (vm, _) = ConversationTestSupport.makeViewModel(
            store: store,
            interpreter: AIServiceCheckInInterpreter(aiService: spy, ownerID: "test.user"),
            aiService: spy
        )
        vm.updateComposerText("Can I have pizza tonight?")
        await vm.sendComposer()

        XCTAssertEqual(spy.coachCallCount, 1)
        XCTAssertEqual(spy.interpretMealCallCount, 0)
        XCTAssertFalse(store.active.messages.contains {
            $0.card?.typeID == MealCapabilityID.estimateCardType
        })
    }

    func testPendingCardsDoNotHijackDessertQuestion() async {
        let spy = SpyAIService()
        let store = ConversationSessionStore()
        let (vm, _) = ConversationTestSupport.makeViewModel(
            store: store,
            interpreter: AIServiceCheckInInterpreter(aiService: spy, ownerID: "test.user"),
            aiService: spy
        )
        for label in ["A", "B"] {
            store.append(
                ConversationMessage(
                    actor: .assistant,
                    card: MealCardCodec.makeCard(
                        payload: MealEstimateCardPayload(
                            draft: MealEstimateSnapshot(draft: sampleDraft(label: label)),
                            refinementAccepted: false,
                            isLogged: false
                        ),
                        interactive: true
                    )
                )
            )
        }
        store.setActivity(MealCapabilityActivityCodec.makeActivity(phase: .reviewing))
        XCTAssertNil(vm.targetedMealDraftID)

        vm.updateComposerText("Can I have dessert tonight?")
        await vm.sendComposer()

        XCTAssertEqual(spy.coachCallCount, 1)
        XCTAssertEqual(spy.interpretMealCallCount, 0)
        let mealCards = store.active.messages.filter { $0.card?.typeID == MealCapabilityID.estimateCardType }
        XCTAssertEqual(mealCards.count, 2)
    }

    func testTargetedRefinePriorityOverMealStatement() async {
        let draftA = sampleDraft(label: "A")
        let draftB = sampleDraft(label: "B")
        let spy = SpyAIService()
        let store = ConversationSessionStore()
        let (vm, meal) = ConversationTestSupport.makeViewModel(
            store: store,
            interpreter: AIServiceCheckInInterpreter(aiService: spy, ownerID: "test.user"),
            aiService: spy
        )
        meal.restoreFromConversation(
            ActiveConversation(
                messages: [
                    ConversationMessage(
                        actor: .assistant,
                        card: MealCardCodec.makeCard(
                            payload: MealEstimateCardPayload(
                                draft: MealEstimateSnapshot(draft: draftA),
                                refinementAccepted: false,
                                isLogged: false
                            ),
                            interactive: true
                        )
                    ),
                    ConversationMessage(
                        actor: .assistant,
                        card: MealCardCodec.makeCard(
                            payload: MealEstimateCardPayload(
                                draft: MealEstimateSnapshot(draft: draftB),
                                refinementAccepted: false,
                                isLogged: false
                            ),
                            interactive: true
                        )
                    ),
                ],
                activity: MealCapabilityActivityCodec.makeActivity(
                    phase: .reviewing,
                    targetedDraftID: draftA.id
                )
            )
        )
        store.mutate {
            $0.messages = [
                ConversationMessage(
                    actor: .assistant,
                    card: MealCardCodec.makeCard(
                        payload: MealEstimateCardPayload(
                            draft: MealEstimateSnapshot(draft: draftA),
                            refinementAccepted: false,
                            isLogged: false
                        ),
                        interactive: true
                    )
                ),
                ConversationMessage(
                    actor: .assistant,
                    card: MealCardCodec.makeCard(
                        payload: MealEstimateCardPayload(
                            draft: MealEstimateSnapshot(draft: draftB),
                            refinementAccepted: false,
                            isLogged: false
                        ),
                        interactive: true
                    )
                ),
            ]
            $0.activity = MealCapabilityActivityCodec.makeActivity(
                phase: .reviewing,
                targetedDraftID: draftA.id
            )
        }

        XCTAssertEqual(vm.targetedMealDraftID, draftA.id)
        vm.updateComposerText("It was a small pizza")
        await vm.sendComposer()

        XCTAssertEqual(spy.interpretMealCallCount, 1)
        XCTAssertEqual(spy.coachCallCount, 0)
        // Target cleared after successful refine.
        XCTAssertNil(vm.targetedMealDraftID)
        let payloads = store.active.messages.compactMap { msg -> MealEstimateCardPayload? in
            guard let card = msg.card, card.typeID == MealCapabilityID.estimateCardType else { return nil }
            return MealCardCodec.decode(card.payload)
        }
        XCTAssertEqual(payloads.count, 2)
        XCTAssertTrue(payloads.contains { $0.draft.id == draftB.id })
    }

    func testAmbiguousPizzaClarificationThenLog() async {
        let spy = SpyAIService()
        let mealRepo = RecordingMealRepository()
        let store = ConversationSessionStore()
        let (vm, _) = ConversationTestSupport.makeViewModel(
            store: store,
            mealRepository: mealRepo,
            interpreter: AIServiceCheckInInterpreter(aiService: spy, ownerID: "test.user"),
            aiService: spy
        )
        vm.updateComposerText("Pizza")
        await vm.sendComposer()

        XCTAssertEqual(spy.coachCallCount, 0)
        XCTAssertEqual(spy.interpretMealCallCount, 0)
        XCTAssertEqual(vm.pendingClarificationText, "Pizza")
        XCTAssertTrue(store.active.messages.contains {
            $0.text?.contains("log that as a meal") == true
        })
        XCTAssertEqual(store.active.messages.filter { $0.actor == .user && $0.text == "Pizza" }.count, 1)

        await vm.resolveClarificationLogMealForTests()

        XCTAssertEqual(spy.interpretMealCallCount, 1)
        XCTAssertEqual(spy.coachCallCount, 0)
        XCTAssertEqual(mealRepo.createCallCount, 0)
        XCTAssertEqual(store.active.messages.filter { $0.actor == .user && $0.text == "Pizza" }.count, 1)
        XCTAssertTrue(store.active.messages.contains {
            $0.card?.typeID == MealCapabilityID.estimateCardType
        })
    }

    func testAmbiguousPizzaClarificationAskAboutIt() async {
        let spy = SpyAIService()
        let store = ConversationSessionStore()
        let (vm, _) = ConversationTestSupport.makeViewModel(store: store, aiService: spy)
        vm.updateComposerText("Pizza")
        await vm.sendComposer()
        await vm.resolveClarificationAskAboutItForTests()
        XCTAssertEqual(spy.coachCallCount, 1)
        XCTAssertEqual(spy.interpretMealCallCount, 0)
        XCTAssertEqual(store.active.messages.filter { $0.actor == .user && $0.text == "Pizza" }.count, 1)
    }

    private func sampleDraft(label: String) -> CheckInMealDraft {
        CheckInMealDraft(
            id: UUID(),
            label: label,
            timing: .lunch,
            eatenAt: .now,
            calories: 400,
            proteinGrams: 30,
            carbsGrams: 40,
            fatGrams: 10,
            confidence: 0.8,
            alternatives: [],
            items: [
                CheckInMealItemDraft(
                    id: UUID(),
                    name: "Item",
                    amount: 1,
                    unit: "serving",
                    calories: 400,
                    proteinGrams: 30,
                    carbsGrams: 40,
                    fatGrams: 10,
                    fiberGrams: 2
                ),
            ]
        )
    }
}

/// Counts meal vs coach calls; forwards to MockAIService.
private final class SpyAIService: AIService, @unchecked Sendable {
    private let base = MockAIService()
    private(set) var interpretMealCallCount = 0
    private(set) var coachCallCount = 0

    func send(message: String, context: [String: String]) async throws -> String {
        try await base.send(message: message, context: context)
    }

    func interpretMeal(request: AIInterpretMealRequest) async throws -> AIInterpretMealResponse {
        interpretMealCallCount += 1
        return try await base.interpretMeal(request: request)
    }

    func interpretGoal(request: AIInterpretGoalRequest) async throws -> AIInterpretGoalResponse {
        try await base.interpretGoal(request: request)
    }

    func coach(request: AICoachRequest) async throws -> AICoachResponse {
        coachCallCount += 1
        return try await base.coach(request: request)
    }
}
