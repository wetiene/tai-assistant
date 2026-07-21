import Foundation

/// DEBUG-only runtime counters for progressive Conversation degradation.
/// No user content, meal text, or image bytes are logged.
enum ConversationRuntimeProbe {
    #if DEBUG
    private(set) static var attachmentDiskLoadCount = 0
    private(set) static var imageCacheHitCount = 0
    private(set) static var imageCacheMissCount = 0
    private(set) static var cardDecodeCount = 0
    private(set) static var cardDecodeCacheHitCount = 0
    private(set) static var composerStoreUpdateCount = 0
    private(set) static var scrollToBottomCount = 0
    private(set) static var debounceTaskCreatedCount = 0

    static func reset() {
        attachmentDiskLoadCount = 0
        imageCacheHitCount = 0
        imageCacheMissCount = 0
        cardDecodeCount = 0
        cardDecodeCacheHitCount = 0
        composerStoreUpdateCount = 0
        scrollToBottomCount = 0
        debounceTaskCreatedCount = 0
    }

    static func recordAttachmentDiskLoad() {
        attachmentDiskLoadCount += 1
    }

    static func recordImageCache(hit: Bool) {
        if hit { imageCacheHitCount += 1 } else { imageCacheMissCount += 1 }
    }

    static func recordCardDecode(cacheHit: Bool) {
        if cacheHit {
            cardDecodeCacheHitCount += 1
        } else {
            cardDecodeCount += 1
        }
    }

    static func recordComposerStoreUpdate() {
        composerStoreUpdateCount += 1
    }

    static func recordScrollToBottom() {
        scrollToBottomCount += 1
    }

    static func recordDebounceTaskCreated() {
        debounceTaskCreatedCount += 1
    }
    #else
    static func reset() {}
    static func recordAttachmentDiskLoad() {}
    static func recordImageCache(hit: Bool) {}
    static func recordCardDecode(cacheHit: Bool) {}
    static func recordComposerStoreUpdate() {}
    static func recordScrollToBottom() {}
    static func recordDebounceTaskCreated() {}
    #endif
}
