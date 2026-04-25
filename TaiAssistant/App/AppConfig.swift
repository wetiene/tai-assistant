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
        aiProxyBaseURL: URL(string: "http://192.168.86.42:8080"),
        aiProxyBearerToken: nil,
        aiInterpretMealPath: "/ai/interpret-meal"
    )
}
