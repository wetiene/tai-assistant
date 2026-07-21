import Foundation

/// Bounded cache for decoded meal-estimate card payloads.
/// Prevents JSON decode on every SwiftUI body pass for the same card identity.
enum MealCardPayloadCache {
    private final class Box: NSObject {
        let payload: MealEstimateCardPayload
        init(_ payload: MealEstimateCardPayload) { self.payload = payload }
    }

    private static let cache: NSCache<NSString, Box> = {
        let cache = NSCache<NSString, Box>()
        cache.countLimit = 64
        cache.totalCostLimit = 2 * 1024 * 1024
        return cache
    }()

    static func payload(for card: ConversationCard) -> MealEstimateCardPayload? {
        // Include a cheap content fingerprint so in-place payload updates miss stale entries.
        let fingerprint = card.payload.hashValue
        let key = "\(card.id.uuidString):\(fingerprint)" as NSString
        if let box = cache.object(forKey: key) {
            ConversationRuntimeProbe.recordCardDecode(cacheHit: true)
            return box.payload
        }
        ConversationRuntimeProbe.recordCardDecode(cacheHit: false)
        guard let decoded = MealCardCodec.decode(card.payload) else { return nil }
        cache.setObject(Box(decoded), forKey: key, cost: max(card.payload.count, 1))
        return decoded
    }

    static func invalidate(cardID: UUID) {
        // Cost-based keys include payload count; clear all entries for this id prefix.
        // NSCache has no prefix API — rely on countLimit eviction after updates replace cards.
        _ = cardID
    }

    #if DEBUG
    static func resetForTests() {
        cache.removeAllObjects()
    }
    #endif
}
