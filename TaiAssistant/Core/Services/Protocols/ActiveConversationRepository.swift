import Foundation

/// Persists the single active Conversation as interaction history.
/// Does not write domain Artifacts (meals, goals) — those stay in feature repositories.
protocol ActiveConversationRepository: AnyObject {
    /// Load the active Conversation, creating one if missing (existing-user migration).
    func loadOrCreateActive(ownerID: String) throws -> ActiveConversation

    /// Replace the durable snapshot of the active Conversation. Idempotent by conversation id.
    func saveActive(_ conversation: ActiveConversation, ownerID: String) throws

    /// Persist composer draft only — must not rewrite `messagesJSON`.
    func saveComposerDraft(_ composer: ConversationComposerState, ownerID: String) throws

    /// Future Archive transition: mark the current active thread archived and return a fresh empty active.
    /// Not used by product UI yet — kept so Archive is a status transition, not a redesign.
    func beginArchiveTransition(ownerID: String) throws -> ActiveConversation
}
