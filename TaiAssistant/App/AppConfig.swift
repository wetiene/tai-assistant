import Foundation

struct AppConfig {
    let assistantName: String
    let useInMemoryStore: Bool
    let isIPhoneOnlyV1: Bool

    static let `default` = AppConfig(
        assistantName: "Tai",
        useInMemoryStore: false,
        isIPhoneOnlyV1: true
    )
}
