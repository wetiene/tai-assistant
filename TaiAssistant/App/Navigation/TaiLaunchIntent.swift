import Foundation

/// Typed intents from Home (or shell) into the single active Tai Conversation.
/// Logging is a capability inside Conversation — never a navigation destination.
enum TaiLaunchIntent: Equatable, Sendable {
    /// Switch to Tai and show the active Conversation as-is.
    case openConversation
    /// Begin meal capture / logging inside the active Conversation.
    case startMealCapture
    /// Focus the composer for a free-form question.
    case focusComposer

    static func fromHomeDestination(_ destination: RecommendationActionDestination) -> TaiLaunchIntent {
        switch destination {
        case .checkInMeal:
            return .startMealCapture
        case .reviewGoal:
            return .openConversation
        }
    }
}

/// Contract surface for Nav V2 primary destinations (testable without SwiftUI).
enum NavV2PrimaryTab: String, CaseIterable, Sendable {
    case home
    case tai

    var title: String {
        switch self {
        case .home: return "Home"
        case .tai: return "Tai"
        }
    }

    static var titles: [String] { allCases.map(\.title) }
}
