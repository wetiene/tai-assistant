import SwiftUI

/// Versioned AI processing consent.
/// - Version 1: meal check-in (text/photo) + goal strategy interpretation.
/// - Version 2: also Live Tai general coaching (`POST /ai/coach`) with bounded confirmed context.
/// - Version 3: gym set photo interpretation (`POST /ai/interpret-gym-photo`).
enum AIDataProcessingConsentStore {
    static let mealAndGoalVersion = 1
    static let liveTaiVersion = 2
    static let gymPhotoVersion = 3
    static let currentVersion = gymPhotoVersion

    private static let acceptedKey = "tai.aiDataProcessingConsent.accepted"
    private static let versionKey = "tai.aiDataProcessingConsent.acceptedVersion"

    /// Highest consent version the user has accepted. Migrates legacy boolean → version 1.
    static var acceptedVersion: Int {
        let stored = UserDefaults.standard.integer(forKey: versionKey)
        if stored > 0 { return stored }
        if UserDefaults.standard.bool(forKey: acceptedKey) {
            UserDefaults.standard.set(mealAndGoalVersion, forKey: versionKey)
            return mealAndGoalVersion
        }
        return 0
    }

    /// True when the user has accepted at least meal/goal AI processing (v1+).
    static var hasAccepted: Bool {
        acceptedVersion >= mealAndGoalVersion
    }

    static func hasAccepted(version minimum: Int) -> Bool {
        acceptedVersion >= minimum
    }

    static func accept(version: Int = currentVersion) {
        let next = max(acceptedVersion, version)
        UserDefaults.standard.set(true, forKey: acceptedKey)
        UserDefaults.standard.set(next, forKey: versionKey)
    }

    /// Test helper — clears consent state.
    static func resetForTests() {
        UserDefaults.standard.removeObject(forKey: acceptedKey)
        UserDefaults.standard.removeObject(forKey: versionKey)
    }
}

enum AIDataProcessingConsentKind: Equatable {
    /// Meal check-in + goal strategy (v1).
    case mealAndGoal
    /// General coaching with confirmed local context (v2).
    case liveTai
    /// Gym set photo interpretation (v3).
    case gymPhoto

    var requiredVersion: Int {
        switch self {
        case .mealAndGoal: return AIDataProcessingConsentStore.mealAndGoalVersion
        case .liveTai: return AIDataProcessingConsentStore.liveTaiVersion
        case .gymPhoto: return AIDataProcessingConsentStore.gymPhotoVersion
        }
    }
}

struct AIDataProcessingConsentSheet: View {
    var kind: AIDataProcessingConsentKind = .mealAndGoal
    let onAccept: () -> Void
    let onDecline: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: DSSpacing.lg) {
                    Text("AI processing")
                        .font(.title2.weight(.bold))
                        .foregroundStyle(DSColor.textPrimary)

                    ForEach(Array(bodyParagraphs.enumerated()), id: \.offset) { _, paragraph in
                        Text(paragraph)
                            .font(.subheadline)
                            .foregroundStyle(DSColor.textSecondary)
                    }

                    Link("Privacy Policy", destination: AppLegalLinks.privacyPolicyURL)
                        .font(.subheadline.weight(.semibold))
                }
                .padding(DSSpacing.lg)
            }
            .background(DSColor.background.ignoresSafeArea())
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: DSSpacing.sm) {
                    Button("Continue") {
                        AIDataProcessingConsentStore.accept(version: kind.requiredVersion)
                        onAccept()
                    }
                    .buttonStyle(CoralGradientButtonStyle())

                    Button("Not now", action: onDecline)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(DSColor.textSecondary)
                }
                .padding(DSSpacing.lg)
                .background(.ultraThinMaterial)
            }
        }
    }

    private var bodyParagraphs: [String] {
        switch kind {
        case .mealAndGoal:
            return [
                "When you check in with text or a meal photo, or describe a goal strategy, Tai sends that content to our backend for analysis. Photos are resized before upload. Meal photos are not kept on your device after you confirm a check-in.",
                "OpenAI is our third-party AI provider. Content is transmitted through our Cloudflare Worker proxy and processed to return nutrition estimates or suggested macro targets. Do not include sensitive personal information in descriptions or photos.",
                "Nutrition and goal suggestions are approximate and are not medical advice. To withdraw consent or learn how your data is handled, see our Privacy Policy.",
            ]
        case .liveTai:
            return [
                "When you ask Tai a coaching question, Tai sends your question, a bounded selection of your confirmed meals and goals, and relevant recent conversation text to our backend for analysis. Meal photos are not sent through this coaching path.",
                "OpenAI is our third-party AI provider. Content is transmitted through our Cloudflare Worker proxy so Tai can give context-aware guidance grounded in what you have already confirmed. Do not include sensitive personal information you do not want processed.",
                "Coaching suggestions are approximate and are not medical advice. Tai may recommend actions, but it will not change your meals, goals or other saved data unless you confirm. Declining this does not turn off meal or goal check-in AI you already accepted. To withdraw consent or learn how your data is handled, see our Privacy Policy.",
            ]
        case .gymPhoto:
            return [
                "When you log a gym set with a photo, Tai sends that photo to our backend for analysis to identify the exercise and weight. Photos are resized before upload and are not stored on your device, in conversation history, or in workout records after analysis completes.",
                "OpenAI is our third-party AI provider. Content is transmitted through our Cloudflare Worker proxy and processed to return exercise and weight suggestions. Do not include people or sensitive information in gym photos.",
                "Exercise and weight suggestions are approximate — always confirm before saving a set. To withdraw consent or learn how your data is handled, see our Privacy Policy.",
            ]
        }
    }
}
