import Foundation

/// Debug-only counters for Conversation startup / restore cost.
/// No user content is logged.
enum ConversationStartupProbe {
    #if DEBUG
    private(set) static var loadOrCreateCount = 0
    private(set) static var snapshotDecodeCount = 0
    private(set) static var persistCallbackCount = 0
    private(set) static var persistDuringBootstrapCount = 0
    private(set) static var lastLoadMilliseconds: Double = 0
    private(set) static var lastDecodeMilliseconds: Double = 0
    static var isBootstrapping = false

    static func resetSession() {
        loadOrCreateCount = 0
        snapshotDecodeCount = 0
        persistCallbackCount = 0
        persistDuringBootstrapCount = 0
        lastLoadMilliseconds = 0
        lastDecodeMilliseconds = 0
        isBootstrapping = false
    }

    static func recordLoadOrCreate(durationMilliseconds: Double) {
        loadOrCreateCount += 1
        lastLoadMilliseconds = durationMilliseconds
        print("[TaiStartup] loadOrCreateActive #\(loadOrCreateCount) \(format(durationMilliseconds))ms")
    }

    static func recordSnapshotDecode(durationMilliseconds: Double) {
        snapshotDecodeCount += 1
        lastDecodeMilliseconds = durationMilliseconds
        print("[TaiStartup] snapshotDecode #\(snapshotDecodeCount) \(format(durationMilliseconds))ms")
    }

    static func recordPersist() {
        persistCallbackCount += 1
        if isBootstrapping {
            persistDuringBootstrapCount += 1
            print("[TaiStartup] persist during bootstrap #\(persistDuringBootstrapCount)")
        }
    }

    private static func format(_ ms: Double) -> String {
        String(format: "%.1f", ms)
    }
    #else
    static var isBootstrapping = false
    static func resetSession() {}
    static func recordLoadOrCreate(durationMilliseconds: Double) {}
    static func recordSnapshotDecode(durationMilliseconds: Double) {}
    static func recordPersist() {}
    #endif
}
