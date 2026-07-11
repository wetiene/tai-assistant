import Foundation
import SwiftData

final class LocalSwiftDataActiveConversationRepository: ActiveConversationRepository {
    private let container: ModelContainer

    init(container: ModelContainer) {
        self.container = container
    }

    func loadOrCreateActive(ownerID: String) throws -> ActiveConversation {
        let context = ModelContext(container)
        if let existing = try fetchActive(ownerID: ownerID, context: context) {
            var conversation = try mapToDomain(existing)
            let healed = ConversationRestoration.healInterruptedWork(conversation)
            if healed.didHeal {
                conversation = healed.0
                try write(conversation, ownerID: ownerID, context: context)
            }
            return conversation
        }

        // Migration: existing installs with meals/goals but no Conversation get one active thread.
        let fresh = ActiveConversation()
        try write(fresh, ownerID: ownerID, context: context)
        return fresh
    }

    func saveActive(_ conversation: ActiveConversation, ownerID: String) throws {
        let context = ModelContext(container)
        try write(conversation, ownerID: ownerID, context: context)
    }

    func saveComposerDraft(_ composer: ConversationComposerState, ownerID: String) throws {
        let context = ModelContext(container)
        guard let existing = try fetchActive(ownerID: ownerID, context: context) else {
            // No row yet — create a minimal active conversation with this draft.
            try write(
                ActiveConversation(composer: composer),
                ownerID: ownerID,
                context: context
            )
            return
        }
        existing.composerText = composer.text
        existing.composerPendingPhotoJPEG = composer.pendingPhotoJPEG
        existing.updatedAt = .now
        try context.save()
    }

    func beginArchiveTransition(ownerID: String) throws -> ActiveConversation {
        let context = ModelContext(container)
        if let existing = try fetchActive(ownerID: ownerID, context: context) {
            existing.status = .archived
            existing.updatedAt = .now
        }
        let fresh = ActiveConversation()
        try write(fresh, ownerID: ownerID, context: context)
        return fresh
    }

    // MARK: - Private

    private func fetchActive(ownerID: String, context: ModelContext) throws -> PersistedConversation? {
        let activeRaw = PersistedConversationStatus.active.rawValue
        let descriptor = FetchDescriptor<PersistedConversation>(
            predicate: #Predicate<PersistedConversation> { row in
                row.ownerID == ownerID && row.statusRaw == activeRaw
            },
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )
        let actives = try context.fetch(descriptor)
        // Exactly one active: if duplicates exist (corruption), keep newest and archive the rest.
        if actives.count > 1 {
            for stale in actives.dropFirst() {
                stale.status = .archived
                stale.updatedAt = .now
            }
            try context.save()
        }
        return actives.first
    }

    private func write(_ conversation: ActiveConversation, ownerID: String, context: ModelContext) throws {
        let messagesJSON = try ConversationSnapshotCodec.encodeMessages(conversation.messages)
        let activityJSON = try ConversationSnapshotCodec.encodeActivity(conversation.activity)
        let quickActionsJSON = try ConversationSnapshotCodec.encodeQuickActions(conversation.activeQuickActions)
        let metadataJSON = try ConversationSnapshotCodec.encodeMetadata()

        if let existing = try fetchActive(ownerID: ownerID, context: context) {
            // Preserve conversation identity when the in-memory id matches; otherwise replace payload on the active row.
            if existing.id != conversation.id {
                // New active id (e.g. post-archive): archive old row if still active with different id.
                existing.status = .archived
                existing.updatedAt = .now
                let row = PersistedConversation(
                    id: conversation.id,
                    ownerID: ownerID,
                    status: .active,
                    createdAt: conversation.createdAt,
                    updatedAt: .now,
                    schemaVersion: PersistedConversation.currentSchemaVersion,
                    messagesJSON: messagesJSON,
                    composerText: conversation.composer.text,
                    composerPendingPhotoJPEG: conversation.composer.pendingPhotoJPEG,
                    activityJSON: activityJSON,
                    activeQuickActionsJSON: quickActionsJSON,
                    scrollAnchorMessageID: conversation.scrollAnchorMessageID,
                    metadataJSON: metadataJSON
                )
                context.insert(row)
            } else {
                existing.messagesJSON = messagesJSON
                existing.composerText = conversation.composer.text
                existing.composerPendingPhotoJPEG = conversation.composer.pendingPhotoJPEG
                existing.activityJSON = activityJSON
                existing.activeQuickActionsJSON = quickActionsJSON
                existing.scrollAnchorMessageID = conversation.scrollAnchorMessageID
                existing.metadataJSON = metadataJSON
                existing.schemaVersion = PersistedConversation.currentSchemaVersion
                existing.updatedAt = .now
            }
        } else {
            let row = PersistedConversation(
                id: conversation.id,
                ownerID: ownerID,
                status: .active,
                createdAt: conversation.createdAt,
                updatedAt: .now,
                schemaVersion: PersistedConversation.currentSchemaVersion,
                messagesJSON: messagesJSON,
                composerText: conversation.composer.text,
                composerPendingPhotoJPEG: conversation.composer.pendingPhotoJPEG,
                activityJSON: activityJSON,
                activeQuickActionsJSON: quickActionsJSON,
                scrollAnchorMessageID: conversation.scrollAnchorMessageID,
                metadataJSON: metadataJSON
            )
            context.insert(row)
        }
        try context.save()
    }

    private func mapToDomain(_ row: PersistedConversation) throws -> ActiveConversation {
        let messages = try ConversationSnapshotCodec.decodeMessages(row.messagesJSON)
        let activity = try ConversationSnapshotCodec.decodeActivity(row.activityJSON)
        let quickActions = try ConversationSnapshotCodec.decodeQuickActions(row.activeQuickActionsJSON)
        return ActiveConversation(
            id: row.id,
            messages: messages,
            composer: ConversationComposerState(
                text: row.composerText,
                pendingPhotoJPEG: row.composerPendingPhotoJPEG
            ),
            activity: activity,
            activeQuickActions: quickActions,
            createdAt: row.createdAt,
            scrollAnchorMessageID: row.scrollAnchorMessageID
        )
    }
}

/// In-memory repository for previews and unit tests (no SwiftData).
final class InMemoryActiveConversationRepository: ActiveConversationRepository {
    private var activeByOwner: [String: ActiveConversation] = [:]
    private var archived: [ActiveConversation] = []

    func loadOrCreateActive(ownerID: String) throws -> ActiveConversation {
        if var existing = activeByOwner[ownerID] {
            let healed = ConversationRestoration.healInterruptedWork(existing)
            if healed.didHeal {
                existing = healed.0
                activeByOwner[ownerID] = existing
            }
            return existing
        }
        let fresh = ActiveConversation()
        activeByOwner[ownerID] = fresh
        return fresh
    }

    func saveActive(_ conversation: ActiveConversation, ownerID: String) throws {
        activeByOwner[ownerID] = conversation
    }

    func saveComposerDraft(_ composer: ConversationComposerState, ownerID: String) throws {
        var current = activeByOwner[ownerID] ?? ActiveConversation()
        current.composer = composer
        activeByOwner[ownerID] = current
    }

    func beginArchiveTransition(ownerID: String) throws -> ActiveConversation {
        if let current = activeByOwner[ownerID] {
            archived.append(current)
        }
        let fresh = ActiveConversation()
        activeByOwner[ownerID] = fresh
        return fresh
    }
}
