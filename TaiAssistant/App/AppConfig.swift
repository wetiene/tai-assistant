import Foundation

enum MealInterpretationProvider: String {
    case mock
    case openAIProxy
}

struct RuntimeAppConfig {
    let assistantName: String
    let useInMemoryStore: Bool
    let isIPhoneOnlyV1: Bool
    /// Single-tenant owner key until authentication exists; repositories and seed data must agree on this value.
    let localOwnerID: String
    let mealInterpretationProvider: MealInterpretationProvider
    let aiProxyBaseURL: URL?
    let aiProxyBearerToken: String?
    let aiInterpretMealPath: String
    let aiInterpretGoalPath: String
    let aiCoachPath: String
    /// When true, ships Home / Check In chooser / Coach. When false, restores Dashboard / Check In / Goals.
    let navV2Enabled: Bool

    private enum LocalProxyAuth {
        static let envTokenKey = "TAI_AI_PROXY_BEARER_TOKEN"
        static let infoPlistTokenKey = "AI_PROXY_BEARER_TOKEN"

        static func resolveBearerToken() -> String? {
            let envToken = ProcessInfo.processInfo.environment[envTokenKey]?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if let envToken, !envToken.isEmpty {
                return envToken
            }

            let plistToken = Bundle.main.object(forInfoDictionaryKey: infoPlistTokenKey) as? String
            let trimmedPlistToken = plistToken?.trimmingCharacters(in: .whitespacesAndNewlines)
            if let trimmedPlistToken, !trimmedPlistToken.isEmpty {
                return trimmedPlistToken
            }

            return nil
        }
    }

    private enum FeatureFlags {
        static let navV2EnvKey = "TAI_NAV_V2_ENABLED"

        /// Defaults on. Set `TAI_NAV_V2_ENABLED=0` (or `false` / `no`) to restore the legacy shell.
        static func resolveNavV2Enabled() -> Bool {
            guard let raw = ProcessInfo.processInfo.environment[navV2EnvKey]?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased(),
                !raw.isEmpty
            else {
                return true
            }
            switch raw {
            case "0", "false", "no", "off":
                return false
            default:
                return true
            }
        }
    }

    /// Dev default: talk to deployed proxy.
    /// Keep `aiProxyBearerToken` nil in source and inject via local runtime wiring.
    static let `default` = RuntimeAppConfig(
        assistantName: "Tai",
        useInMemoryStore: false,
        isIPhoneOnlyV1: true,
        localOwnerID: "preview.user",
        mealInterpretationProvider: .openAIProxy,
        aiProxyBaseURL: URL(string: "https://tai-ai-proxy.taiassistant.workers.dev"),
        aiProxyBearerToken: LocalProxyAuth.resolveBearerToken(),
        aiInterpretMealPath: "/ai/interpret-meal",
        aiInterpretGoalPath: "/ai/interpret-goal",
        aiCoachPath: "/ai/coach",
        navV2Enabled: FeatureFlags.resolveNavV2Enabled()
    )
}
