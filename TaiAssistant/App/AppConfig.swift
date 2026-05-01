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
        aiInterpretMealPath: "/ai/interpret-meal"
    )
}
