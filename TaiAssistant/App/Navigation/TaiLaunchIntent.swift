import Foundation

/// Typed intents from Home (or shell) into the single active Tai Conversation.
/// Logging is a capability inside Conversation — never a navigation destination.
struct TaiLaunchIntent: Equatable, Sendable {
    let kind: Kind
    let dayContext: NutritionDayContext?

    enum Kind: Equatable, Sendable {
        case openConversation
        case startMealCapture
        case focusComposer
        case manageGymPlans
        case startGymWorkout(GymPlanWorkoutTarget)
        case resumeGymWorkout
    }

    static let openConversation = TaiLaunchIntent(kind: .openConversation)
    static let startMealCapture = TaiLaunchIntent(kind: .startMealCapture)
    static let focusComposer = TaiLaunchIntent(kind: .focusComposer)

    init(kind: Kind, dayContext: NutritionDayContext? = nil) {
        self.kind = kind
        self.dayContext = dayContext
    }

    static func fromHomeDestination(
        _ destination: RecommendationActionDestination,
        dayContext: NutritionDayContext? = nil
    ) -> TaiLaunchIntent {
        switch destination {
        case .checkInMeal:
            return TaiLaunchIntent(kind: .startMealCapture, dayContext: dayContext)
        case .reviewGoal:
            return TaiLaunchIntent(kind: .openConversation, dayContext: dayContext)
        case .manageGymPlans:
            return TaiLaunchIntent(kind: .manageGymPlans, dayContext: dayContext)
        case .startGymWorkout(let templateID):
            return TaiLaunchIntent(
                kind: .startGymWorkout(GymPlanWorkoutTarget(reference: .starter(templateID), sectionIndex: 0)),
                dayContext: dayContext
            )
        case .startGymWorkoutPlan(let reference):
            return TaiLaunchIntent(
                kind: .startGymWorkout(GymPlanWorkoutTarget(reference: reference, sectionIndex: 0)),
                dayContext: dayContext
            )
        case .resumeGymWorkout:
            return TaiLaunchIntent(kind: .resumeGymWorkout, dayContext: dayContext)
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
