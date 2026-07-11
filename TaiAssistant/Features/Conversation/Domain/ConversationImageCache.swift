import UIKit

/// Decodes Conversation JPEG attachments once and reuses them across SwiftUI invalidations.
/// Keys are attachment IDs (or synthetic composer keys). No image bytes are logged.
enum ConversationImageCache {
    private static let cache: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.countLimit = 48
        cache.totalCostLimit = 32 * 1024 * 1024
        return cache
    }()

    static func image(id: UUID, data: Data) -> UIImage? {
        image(key: id.uuidString, data: data)
    }

    static func image(key: String, data: Data) -> UIImage? {
        let nsKey = key as NSString
        if let cached = cache.object(forKey: nsKey) {
            return cached
        }
        guard let image = UIImage(data: data) else { return nil }
        cache.setObject(image, forKey: nsKey, cost: data.count)
        return image
    }

    static func remove(id: UUID) {
        cache.removeObject(forKey: id.uuidString as NSString)
    }

    #if DEBUG
    static func resetForTests() {
        cache.removeAllObjects()
    }
    #endif
}
