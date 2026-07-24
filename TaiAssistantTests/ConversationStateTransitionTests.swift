import XCTest
@testable import TaiAssistant

@MainActor
final class ConversationStateTransitionTests: XCTestCase {
    func testFreshConversationStartsIdleThenGreetingSeedsAwaitingUser() {
        let store = ConversationSessionStore()
        XCTAssertEqual(store.active.activity, .idle)
        XCTAssertTrue(store.active.messages.isEmpty)

        let meal = MealCapabilityController(
            mealRepository: MockMealRepository(),
            ownerID: "test.user",
            interpreter: MockCheckInInterpreter()
        )
        let vm = ConversationViewModel(store: store, meal: meal, gym: ConversationTestSupport.makeGym(), strengthConversation: ConversationTestSupport.makeStrengthConversation(), liveTai: ConversationTestSupport.makeLiveTai(), gymPlanRepository: ConversationTestSupport.makeGymPlanRepository(), ownerID: "test.user", assistantName: "Tai")
        vm.startIfNeeded()

        XCTAssertEqual(store.active.activity, .awaitingUser)
        XCTAssertFalse(store.active.messages.isEmpty)
        XCTAssertEqual(store.active.activeQuickActions.count, 3)
        XCTAssertEqual(store.active.messages.first?.actor, .assistant)
    }

    func testStartIfNeededIsIdempotent() {
        let store = ConversationSessionStore()
        let meal = MealCapabilityController(
            mealRepository: MockMealRepository(),
            ownerID: "test.user",
            interpreter: MockCheckInInterpreter()
        )
        let vm = ConversationViewModel(store: store, meal: meal, gym: ConversationTestSupport.makeGym(), strengthConversation: ConversationTestSupport.makeStrengthConversation(), liveTai: ConversationTestSupport.makeLiveTai(), gymPlanRepository: ConversationTestSupport.makeGymPlanRepository(), ownerID: "test.user", assistantName: "Tai")
        vm.startIfNeeded()
        let count = store.active.messages.count
        vm.startIfNeeded()
        XCTAssertEqual(store.active.messages.count, count)
    }

    func testDescribeMealQuickActionMovesToCollectingPhase() {
        let store = ConversationSessionStore()
        let meal = MealCapabilityController(
            mealRepository: MockMealRepository(),
            ownerID: "test.user",
            interpreter: MockCheckInInterpreter()
        )
        let vm = ConversationViewModel(store: store, meal: meal, gym: ConversationTestSupport.makeGym(), strengthConversation: ConversationTestSupport.makeStrengthConversation(), liveTai: ConversationTestSupport.makeLiveTai(), gymPlanRepository: ConversationTestSupport.makeGymPlanRepository(), ownerID: "test.user", assistantName: "Tai")
        vm.startIfNeeded()

        let action = ConversationViewModel.defaultQuickActions.first {
            $0.id == MealCapabilityID.QuickAction.describeMeal
        }!
        vm.handleQuickAction(action)

        if case let .capability(capabilityID, phaseID, _) = store.active.activity {
            XCTAssertEqual(capabilityID, MealCapabilityID.capability)
            XCTAssertEqual(phaseID, MealCapabilityID.Phase.collecting.rawValue)
        } else {
            XCTFail("Expected capability collecting activity")
        }
        XCTAssertEqual(meal.phase, .collecting)
        XCTAssertTrue(store.active.activeQuickActions.isEmpty)
    }

    func testFreezeInteractiveCardsPreservesHistoryWithoutMutation() {
        let store = ConversationSessionStore()
        let draft = CheckInMealDraft(
            id: UUID(),
            label: "Oats",
            timing: .breakfast,
            eatenAt: .now,
            calories: 400,
            proteinGrams: 20,
            carbsGrams: 50,
            fatGrams: 10,
            confidence: 0.8,
            alternatives: [],
            items: []
        )
        let payload = MealEstimateCardPayload(
            draft: MealEstimateSnapshot(draft: draft),
            refinementAccepted: false,
            isLogged: false
        )
        let card = MealCardCodec.makeCard(payload: payload, interactive: true)
        store.append(ConversationMessage(actor: .assistant, card: card))

        store.freezeInteractiveCards(typeID: MealCapabilityID.estimateCardType)

        XCTAssertEqual(store.active.messages.count, 1)
        XCTAssertEqual(store.active.messages[0].card?.isInteractive, false)
        XCTAssertEqual(store.active.messages[0].card?.id, card.id)
        let decoded = MealCardCodec.decode(store.active.messages[0].card!.payload)
        XCTAssertEqual(decoded?.draft.label, "Oats")
    }
}
