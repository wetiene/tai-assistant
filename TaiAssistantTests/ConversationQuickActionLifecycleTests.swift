import XCTest
@testable import TaiAssistant

@MainActor
final class ConversationQuickActionLifecycleTests: XCTestCase {
    func testDefaultQuickActionsAreMealScopedOnly() {
        let ids = Set(ConversationViewModel.defaultQuickActions.map(\.id))
        XCTAssertEqual(ids, [
            MealCapabilityID.QuickAction.takePhoto,
            MealCapabilityID.QuickAction.describeMeal,
            MealCapabilityID.QuickAction.askTai,
        ])
        XCTAssertFalse(ids.contains { $0.contains("workout") })
        XCTAssertFalse(ids.contains { $0.contains("sleep") })
        XCTAssertFalse(ids.contains { $0.contains("weight") })
    }

    func testAskTaiQuickActionKeepsQuickActionsAvailable() {
        let store = ConversationSessionStore()
        let meal = MealCapabilityController(
            mealRepository: MockMealRepository(),
            ownerID: "test.user",
            interpreter: MockCheckInInterpreter()
        )
        let vm = ConversationViewModel(store: store, meal: meal, assistantName: "Tai")
        vm.startIfNeeded()

        let ask = ConversationViewModel.defaultQuickActions.first {
            $0.id == MealCapabilityID.QuickAction.askTai
        }!
        vm.handleQuickAction(ask)

        XCTAssertEqual(store.active.activeQuickActions.count, 3)
        XCTAssertTrue(store.active.messages.contains { $0.text?.contains("log meals") == true })
    }

    func testMealIntentDeepLinkNarrowsQuickActions() {
        let store = ConversationSessionStore()
        let meal = MealCapabilityController(
            mealRepository: MockMealRepository(),
            ownerID: "test.user",
            interpreter: MockCheckInInterpreter()
        )
        let vm = ConversationViewModel(store: store, meal: meal, assistantName: "Tai")
        vm.applyMealIntent()

        let ids = store.active.activeQuickActions.map(\.id)
        XCTAssertTrue(ids.contains(MealCapabilityID.QuickAction.takePhoto))
        XCTAssertTrue(ids.contains(MealCapabilityID.QuickAction.describeMeal))
        XCTAssertFalse(ids.contains(MealCapabilityID.QuickAction.askTai))
        XCTAssertEqual(meal.phase, .collecting)
    }
}
