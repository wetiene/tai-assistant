import Foundation

/// File-backed storage for Conversation photo attachments.
/// Keeps large JPEG payloads out of `messagesJSON` while preserving attachment identity.
///
/// Thread-safe. Safe to call from background encode/decode work.
final class ConversationAttachmentStore: @unchecked Sendable {
    /// Process-wide store used by UI resolution and the active Conversation repository.
    /// Reassigned only at app bootstrap / test setup.
    static var shared: ConversationAttachmentStore = .makeDefault()

    private let rootDirectory: URL
    private let fileManager: FileManager
    private let lock = NSLock()

    init(rootDirectory: URL, fileManager: FileManager = .default) {
        self.rootDirectory = rootDirectory
        self.fileManager = fileManager
        try? fileManager.createDirectory(at: rootDirectory, withIntermediateDirectories: true)
    }

    static func makeDefault(fileManager: FileManager = .default) -> ConversationAttachmentStore {
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        let root = base
            .appendingPathComponent("Tai", isDirectory: true)
            .appendingPathComponent("ConversationAttachments", isDirectory: true)
        return ConversationAttachmentStore(rootDirectory: root, fileManager: fileManager)
    }

    static func makeEphemeralForTests(fileManager: FileManager = .default) -> ConversationAttachmentStore {
        let root = fileManager.temporaryDirectory
            .appendingPathComponent("TaiConversationAttachments-\(UUID().uuidString)", isDirectory: true)
        return ConversationAttachmentStore(rootDirectory: root, fileManager: fileManager)
    }

    func fileURL(for id: UUID) -> URL {
        rootDirectory.appendingPathComponent("\(id.uuidString).jpg", isDirectory: false)
    }

    func exists(_ id: UUID) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return fileManager.fileExists(atPath: fileURL(for: id).path)
    }

    /// Writes JPEG bytes for `id`. Idempotent when content is already present.
    func save(id: UUID, data: Data) throws {
        lock.lock()
        defer { lock.unlock() }
        let url = fileURL(for: id)
        if fileManager.fileExists(atPath: url.path) {
            return
        }
        try data.write(to: url, options: .atomic)
    }

    func load(id: UUID) throws -> Data? {
        lock.lock()
        defer { lock.unlock() }
        let url = fileURL(for: id)
        guard fileManager.fileExists(atPath: url.path) else { return nil }
        ConversationRuntimeProbe.recordAttachmentDiskLoad()
        return try Data(contentsOf: url)
    }

    func delete(id: UUID) throws {
        lock.lock()
        defer { lock.unlock() }
        let url = fileURL(for: id)
        guard fileManager.fileExists(atPath: url.path) else { return }
        try fileManager.removeItem(at: url)
    }

    /// Ensures inline bytes are on disk and returns a file-backed attachment.
    func externalize(_ attachment: ConversationAttachment) throws -> ConversationAttachment {
        switch attachment.kind {
        case .photoJPEG(let data):
            try save(id: attachment.id, data: data)
            return ConversationAttachment(id: attachment.id, kind: .photoJPEGFile)
        case .photoJPEGFile:
            return attachment
        }
    }

    func resolvedJPEGData(for attachment: ConversationAttachment) -> Data? {
        switch attachment.kind {
        case .photoJPEG(let data):
            return data
        case .photoJPEGFile:
            return try? load(id: attachment.id)
        }
    }
}
