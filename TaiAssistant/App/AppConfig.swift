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

    /// Dev default: talk to deployed proxy.
    /// Keep `aiProxyBearerToken` nil in source and inject via local runtime wiring.
    static let `default` = RuntimeAppConfig(
        assistantName: "Tai",
        useInMemoryStore: false,
        isIPhoneOnlyV1: true,
        localOwnerID: "preview.user",
        mealInterpretationProvider: .openAIProxy,
        aiProxyBaseURL: URL(string: "https://tai-ai-proxy.taiassistant.workers.dev"),
        aiProxyBearerToken: nil,
        aiInterpretMealPath: "/ai/interpret-meal"
    )
}
