import Foundation
import SwiftData

/// Lifecycle status for a persisted Conversation.
/// Archive later flips `active` → `archived` without redesigning storage.
enum PersistedConversationStatus: String, Codable, Sendable {
    case active
    case archived
}

/// Durable interaction-history record for one Conversation thread.
/// Not the Artifact source of truth — meals/goals remain in their own stores.
@Model
final class PersistedConversation {
    static let currentSchemaVersion = 1

    @Attribute(.unique) var id: UUID
    var ownerID: String
    /// `PersistedConversationStatus.rawValue`
    var statusRaw: String
    var createdAt: Date
    var updatedAt: Date
    var schemaVersion: Int
    /// Encoded `[ConversationMessageRecord]` — Raw Archive material later.
    var messagesJSON: Data
    var composerText: String
    var composerPendingPhotoJPEG: Data?
    /// Encoded `ConversationActivityRecord`
    var activityJSON: Data
    /// Encoded `[ConversationQuickActionRecord]`
    var activeQuickActionsJSON: Data
    var scrollAnchorMessageID: UUID?
    /// Opaque metadata bag for future Archive / continuity fields.
    var metadataJSON: Data

    var status: PersistedConversationStatus {
        get { PersistedConversationStatus(rawValue: statusRaw) ?? .active }
        set { statusRaw = newValue.rawValue }
    }

    init(
        id: UUID = UUID(),
        ownerID: String,
        status: PersistedConversationStatus = .active,
        createdAt: Date = .now,
        updatedAt: Date = .now,
        schemaVersion: Int = PersistedConversation.currentSchemaVersion,
        messagesJSON: Data = Data("[]".utf8),
        composerText: String = "",
        composerPendingPhotoJPEG: Data? = nil,
        activityJSON: Data = Data("{\"kind\":\"idle\"}".utf8),
        activeQuickActionsJSON: Data = Data("[]".utf8),
        scrollAnchorMessageID: UUID? = nil,
        metadataJSON: Data = Data("{}".utf8)
    ) {
        self.id = id
        self.ownerID = ownerID
        self.statusRaw = status.rawValue
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.schemaVersion = schemaVersion
        self.messagesJSON = messagesJSON
        self.composerText = composerText
        self.composerPendingPhotoJPEG = composerPendingPhotoJPEG
        self.activityJSON = activityJSON
        self.activeQuickActionsJSON = activeQuickActionsJSON
        self.scrollAnchorMessageID = scrollAnchorMessageID
        self.metadataJSON = metadataJSON
    }
}
