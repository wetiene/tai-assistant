import Foundation

enum AnalyticsEvent: Equatable, Sendable {
    case homeViewed
    case homePrimaryActionTapped
    case homeWhyTapped
    case checkInChooserViewed
    case checkInMealSelected
    case checkInAskTaiSelected
    case coachViewed
    case coachGoalSelected
    case coachAskTaiSelected
    case taiConversationViewed
    case taiGoalSelected

    var name: String {
        switch self {
        case .homeViewed: return "home_viewed"
        case .homePrimaryActionTapped: return "home_primary_action_tapped"
        case .homeWhyTapped: return "home_why_tapped"
        case .checkInChooserViewed: return "check_in_chooser_viewed"
        case .checkInMealSelected: return "check_in_meal_selected"
        case .checkInAskTaiSelected: return "check_in_ask_tai_selected"
        case .coachViewed: return "coach_viewed"
        case .coachGoalSelected: return "coach_goal_selected"
        case .coachAskTaiSelected: return "coach_ask_tai_selected"
        case .taiConversationViewed: return "tai_conversation_viewed"
        case .taiGoalSelected: return "tai_goal_selected"
        }
    }
}

protocol AnalyticsClient: Sendable {
    func track(_ event: AnalyticsEvent)
}

struct NoOpAnalyticsClient: AnalyticsClient {
    func track(_ event: AnalyticsEvent) {}
}

#if DEBUG
struct LoggingAnalyticsClient: AnalyticsClient {
    func track(_ event: AnalyticsEvent) {
        print("[analytics] \(event.name)")
    }
}
#endif
