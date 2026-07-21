import UIKit

/// Decodes Conversation JPEG attachments once and reuses them across SwiftUI invalidations.
/// Keys are attachment IDs (or synthetic composer keys). No image bytes are logged.
///
/// Critical: always probe the cache by id **before** loading bytes from disk.
enum ConversationImageCache {
    private static let cache: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.countLimit = 48
        cache.totalCostLimit = 24 * 1024 * 1024
        return cache
    }()

    /// Cache hit only — never touches disk or decodes.
    static func cached(id: UUID) -> UIImage? {
        cache.object(forKey: id.uuidString as NSString)
    }

    static func cached(key: String) -> UIImage? {
        cache.object(forKey: key as NSString)
    }

    static func image(id: UUID, data: Data) -> UIImage? {
        image(key: id.uuidString, data: data)
    }

    /// Loads bytes only on cache miss. `loadData` must be side-effect free aside from I/O.
    static func image(id: UUID, loadData: () -> Data?) -> UIImage? {
        if let cached = cached(id: id) {
            ConversationRuntimeProbe.recordImageCache(hit: true)
            return cached
        }
        ConversationRuntimeProbe.recordImageCache(hit: false)
        guard let data = loadData() else { return nil }
        return image(key: id.uuidString, data: data)
    }

    static func image(key: String, data: Data) -> UIImage? {
        let nsKey = key as NSString
        if let cached = cache.object(forKey: nsKey) {
            ConversationRuntimeProbe.recordImageCache(hit: true)
            return cached
        }
        ConversationRuntimeProbe.recordImageCache(hit: false)
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
