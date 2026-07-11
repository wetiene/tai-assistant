import Foundation

/// In-memory store for the single active conversation.
/// Persistence is injected via `onPersist` so Archive can later wrap the same UI contract.
@MainActor
@Observable
final class ConversationSessionStore {
    private(set) var active: ActiveConversation

    /// Called after durable mutations. Must not be invoked for every compositor keystroke.
    var onPersist: ((ActiveConversation) -> Void)?

    /// When true, mutations skip `onPersist` (used during bootstrap).
    var suppressPersistence = false

    private var composerPersistTask: Task<Void, Never>?

    init(seed: ActiveConversation? = nil) {
        self.active = seed ?? ActiveConversation()
    }

    func replace(_ conversation: ActiveConversation) {
        active = conversation
        persistIfNeeded()
    }

    func mutate(_ body: (inout ActiveConversation) -> Void) {
        var copy = active
        body(&copy)
        if let lastID = copy.messages.last?.id {
            copy.scrollAnchorMessageID = lastID
        }
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

    /// Composer text/photo updates: in-memory immediately; disk debounced to avoid write storms.
    func updateComposer(_ body: (inout ConversationComposerState) -> Void) {
        var copy = active
        body(&copy.composer)
        active = copy
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
        persistIfNeeded()
    }

    private func scheduleDebouncedComposerPersist() {
        guard !suppressPersistence else { return }
        composerPersistTask?.cancel()
        composerPersistTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 400_000_000)
            guard !Task.isCancelled else { return }
            persistIfNeeded()
        }
    }

    private func persistIfNeeded() {
        guard !suppressPersistence else { return }
        onPersist?(active)
    }
}
