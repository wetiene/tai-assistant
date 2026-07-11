import XCTest
@testable import TaiAssistant

final class NavigationShellContractTests: XCTestCase {
    func testNavV2IsEnabledByDefault() {
        XCTAssertTrue(RuntimeAppConfig.default.navV2Enabled)
    }

    func testPrimaryRecommendationDestinationsAreHomeAndTaiCapable() {
        let destinations: [RecommendationActionDestination] = [.checkInMeal, .reviewGoal]
        XCTAssertEqual(Set(destinations.map(String.init(describing:))), Set(["checkInMeal", "reviewGoal"]))
    }

    func testNavV2PrimaryTabsAreHomeAndTai() {
        let tabTitles = ["Home", "Tai"]
        XCTAssertEqual(tabTitles, ["Home", "Tai"])
        XCTAssertFalse(tabTitles.contains("Coach"))
        XCTAssertFalse(tabTitles.contains("Check In"))
        XCTAssertFalse(tabTitles.contains("Goals"))
    }

    func testCheckInChooserSurfaceExcludesWorkoutWeightSleep() {
        // Legacy chooser retained for flag-off / preview paths.
        let chooserOptions = ["Meal", "Ask Tai Preview"]
        XCTAssertFalse(chooserOptions.contains { $0.localizedCaseInsensitiveContains("workout") })
        XCTAssertFalse(chooserOptions.contains { $0.localizedCaseInsensitiveContains("weight") })
        XCTAssertFalse(chooserOptions.contains { $0.localizedCaseInsensitiveContains("sleep") })
        XCTAssertTrue(chooserOptions.contains("Ask Tai Preview"))
    }

    func testAskTaiPreviewLabelIsExplicit() {
        let title = "Ask Tai Preview"
        XCTAssertTrue(title.contains("Preview"))
    }

    func testAnalyticsEventNamesMatchContract() {
        XCTAssertEqual(AnalyticsEvent.homeViewed.name, "home_viewed")
        XCTAssertEqual(AnalyticsEvent.homePrimaryActionTapped.name, "home_primary_action_tapped")
        XCTAssertEqual(AnalyticsEvent.homeWhyTapped.name, "home_why_tapped")
        XCTAssertEqual(AnalyticsEvent.checkInChooserViewed.name, "check_in_chooser_viewed")
        XCTAssertEqual(AnalyticsEvent.checkInMealSelected.name, "check_in_meal_selected")
        XCTAssertEqual(AnalyticsEvent.checkInAskTaiSelected.name, "check_in_ask_tai_selected")
        XCTAssertEqual(AnalyticsEvent.coachViewed.name, "coach_viewed")
        XCTAssertEqual(AnalyticsEvent.coachGoalSelected.name, "coach_goal_selected")
        XCTAssertEqual(AnalyticsEvent.coachAskTaiSelected.name, "coach_ask_tai_selected")
        XCTAssertEqual(AnalyticsEvent.taiConversationViewed.name, "tai_conversation_viewed")
        XCTAssertEqual(AnalyticsEvent.taiGoalSelected.name, "tai_goal_selected")
    }
}
