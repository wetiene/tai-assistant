import Foundation

enum StrengthConversationUITestSupport {
    static var isEnabled: Bool {
        ProcessInfo.processInfo.arguments.contains("-UITestStrengthConversation")
            || ProcessInfo.processInfo.environment["UITEST_STRENGTH_CONVERSATION"] == "1"
    }

    /// Pins starter plan selection for deterministic UI tests (avoids weekday-based upper/lower rotation).
    static var forcesLowerBodyPlan: Bool {
        ProcessInfo.processInfo.environment["UITEST_STRENGTH_FORCE_LOWER_BODY"] == "1"
    }
}
