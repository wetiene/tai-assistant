import Foundation

/// Serialises Conversation disk writes and runs encode/save off the caller's thread.
/// Coalesces rapid mutations to the latest snapshot so the MainActor never blocks on JSON/JPEG I/O.
final class ConversationPersistCoordinator: @unchecked Sendable {
    private let repository: ActiveConversationRepository
    private let ownerID: String
    private let lock = NSLock()
    private var pendingActive: ActiveConversation?
    private var pendingComposer: ConversationComposerState?
    private var isDraining = false

    init(repository: ActiveConversationRepository, ownerID: String) {
        self.repository = repository
        self.ownerID = ownerID
    }

    func enqueueActive(_ conversation: ActiveConversation) {
        lock.lock()
        pendingActive = conversation
        let shouldStart = !isDraining
        if shouldStart { isDraining = true }
        lock.unlock()
        guard shouldStart else { return }
        DispatchQueue.global(qos: .utility).async { [weak self] in
            self?.drain()
        }
    }

    func enqueueComposer(_ composer: ConversationComposerState) {
        lock.lock()
        pendingComposer = composer
        let shouldStart = !isDraining
        if shouldStart { isDraining = true }
        lock.unlock()
        guard shouldStart else { return }
        DispatchQueue.global(qos: .utility).async { [weak self] in
            self?.drain()
        }
    }

    private func drain() {
        while true {
            lock.lock()
            let active = pendingActive
            pendingActive = nil
            let composer = pendingComposer
            pendingComposer = nil
            if active == nil && composer == nil {
                isDraining = false
                lock.unlock()
                return
            }
            lock.unlock()

            if let active {
                ConversationStartupProbe.recordPersist()
                try? repository.saveActive(active, ownerID: ownerID)
            }
            if let composer {
                ConversationStartupProbe.recordComposerPersist()
                try? repository.saveComposerDraft(composer, ownerID: ownerID)
            }
        }
    }
}
