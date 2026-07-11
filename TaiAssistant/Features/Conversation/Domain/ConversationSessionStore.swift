import Foundation

/// In-memory store for the single active conversation.
/// Archive / multi-conversation can wrap this later without changing the UI contract.
@MainActor
@Observable
final class ConversationSessionStore {
    private(set) var active: ActiveConversation

    init(seed: ActiveConversation? = nil) {
        self.active = seed ?? ActiveConversation()
    }

    func replace(_ conversation: ActiveConversation) {
        active = conversation
    }

    func mutate(_ body: (inout ActiveConversation) -> Void) {
        var copy = active
        body(&copy)
        active = copy
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

    func updateComposer(_ body: (inout ConversationComposerState) -> Void) {
        mutate { body(&$0.composer) }
    }

    /// Freeze prior interactive cards matching `typeID` so history is immutable.
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

    /// Designed extension point: archive current, start fresh (not implemented in P0 meal slice).
    func prepareForArchiveReplacement(newConversation: ActiveConversation) {
        active = newConversation
    }
}
