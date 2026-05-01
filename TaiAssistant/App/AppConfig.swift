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

    /// Dev default: talk to local stub (`backend/server.mjs` on port 8080). Switch to `.mock` for fully offline UI.
    static let `default` = RuntimeAppConfig(
        assistantName: "Tai",
        useInMemoryStore: false,
        isIPhoneOnlyV1: true,
        localOwnerID: "preview.user",
        mealInterpretationProvider: .openAIProxy,
        aiProxyBaseURL: URL(string: "https://tai-ai-proxy.taiassistant.workers.dev"),
        aiProxyBearerToken: "3f7c9e8a6b2d41c5f9a1e0d7c4b8a6e2f1c9d7b5a3e8c6f4d2b1a9e7c5f3d1a8",
        aiInterpretMealPath: "/ai/interpret-meal"
    )
}
