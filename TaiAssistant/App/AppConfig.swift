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

    static let `default` = RuntimeAppConfig(
        assistantName: "Tai",
        useInMemoryStore: false,
        isIPhoneOnlyV1: true,
        localOwnerID: "preview.user",
        mealInterpretationProvider: .mock,
        aiProxyBaseURL: URL(string: "https://api.tai.your-backend.example"),
        aiProxyBearerToken: nil,
        aiInterpretMealPath: "/ai/interpret-meal"
    )
}
