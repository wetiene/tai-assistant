import Foundation

/// In-memory store for the single active conversation.
/// Persistence is injected via callbacks so Archive can later wrap the same UI contract.
///
/// Composer draft is intentionally separate from `active` so keystrokes do not invalidate
/// the message list Observation graph.
@MainActor
@Observable
final class ConversationSessionStore {
    private(set) var active: ActiveConversation

    /// Live composer state. Not part of `active` until a full snapshot persist merges it.
    var composerDraft: ConversationComposerState

    /// Called after durable history mutations (messages, activity, quick actions).
    var onPersist: ((ActiveConversation) -> Void)?

    /// Called after debounced composer-only changes. Must not rewrite messagesJSON.
    var onPersistComposer: ((ConversationComposerState) -> Void)?

    /// When true, mutations skip persistence (used during bootstrap).
    var suppressPersistence = false

    private var composerPersistTask: Task<Void, Never>?

    init(seed: ActiveConversation? = nil) {
        let seed = seed ?? ActiveConversation()
        self.active = seed
        self.composerDraft = seed.composer
    }

    /// Domain snapshot including the live composer draft (for full saves / probes).
    var snapshotIncludingComposer: ActiveConversation {
        var snap = active
        snap.composer = composerDraft
        return snap
    }

    func replace(_ conversation: ActiveConversation) {
        active = conversation
        composerDraft = conversation.composer
        persistIfNeeded()
    }

    func mutate(_ body: (inout ActiveConversation) -> Void) {
        var copy = active
        body(&copy)
        if let lastID = copy.messages.last?.id {
            copy.scrollAnchorMessageID = lastID
        }
        // Preserve live draft; history mutations must not clobber in-progress typing.
        copy.composer = composerDraft
        active = copy
        persistIfNeeded()
    }

    func append(_ message: ConversationMessage) {
        mutate { $0.messages.append(message) }
    }

    func setActivity(_ activity: ConversationActivity) {
        mutate { $0.activity = activity }
    }

    func setQuickActions(_ actions: [ConversationQuickAction]) {
        mutate { $0.activeQuickActions = actions }
    }

    /// Composer text/photo updates: mutate draft only; disk debounced via composer-only path.
    func updateComposer(_ body: (inout ConversationComposerState) -> Void) {
        body(&composerDraft)
        scheduleDebouncedComposerPersist()
    }

    /// Freeze prior interactive cards matching `typeID` so superseded cards remain in history.
    func freezeInteractiveCards(typeID: String) {
        mutate { conversation in
            conversation.messages = conversation.messages.map { message in
                guard var card = message.card, card.typeID == typeID, card.isInteractive else {
                    return message
                }
                card = ConversationCard(
                    id: card.id,
                    typeID: card.typeID,
                    payload: card.payload,
                    isInteractive: false
                )
                return ConversationMessage(
                    id: message.id,
                    actor: message.actor,
                    createdAt: message.createdAt,
                    text: message.text,
                    attachment: message.attachment,
                    card: card,
                    quickActions: message.quickActions
                )
            }
        }
    }

    /// Designed extension point: archive current, start fresh (Archive product slice).
    func prepareForArchiveReplacement(newConversation: ActiveConversation) {
        active = newConversation
        composerDraft = newConversation.composer
        persistIfNeeded()
    }

    private func scheduleDebouncedComposerPersist() {
        guard !suppressPersistence else { return }
        composerPersistTask?.cancel()
        composerPersistTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 400_000_000)
            guard !Task.isCancelled else { return }
            persistComposerIfNeeded()
        }
    }

    private func persistComposerIfNeeded() {
        guard !suppressPersistence else { return }
        if let onPersistComposer {
            onPersistComposer(composerDraft)
        } else {
            // Fallback for tests that only wire full-snapshot persistence.
            persistIfNeeded()
        }
    }

    private func persistIfNeeded() {
        guard !suppressPersistence else { return }
        onPersist?(snapshotIncludingComposer)
    }
}
