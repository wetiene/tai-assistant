import Foundation

// MARK: - Codable records (persistence DTOs)

struct ConversationMessageRecord: Codable, Equatable, Sendable {
    var id: UUID
    var actor: String
    var createdAt: Date
    var text: String?
    var attachment: ConversationAttachmentRecord?
    var card: ConversationCardRecord?
    var quickActions: [ConversationQuickActionRecord]?
}

struct ConversationAttachmentRecord: Codable, Equatable, Sendable {
    var id: UUID
    var kind: String
    var jpegData: Data?

    static let photoJPEGKind = "photoJPEG"
}

struct ConversationCardRecord: Codable, Equatable, Sendable {
    var id: UUID
    var typeID: String
    var payload: Data
    var isInteractive: Bool
}

struct ConversationQuickActionRecord: Codable, Equatable, Sendable {
    var id: String
    var title: String
    var systemImage: String?
    var accessibilityHint: String?
}

struct ConversationActivityRecord: Codable, Equatable, Sendable {
    var kind: String
    var reason: String?
    var capabilityID: String?
    var phaseID: String?
    var payload: Data?

    static let idle = ConversationActivityRecord(kind: "idle")
    static let awaitingUser = ConversationActivityRecord(kind: "awaitingUser")

    static func processing(reason: String) -> ConversationActivityRecord {
        ConversationActivityRecord(kind: "processing", reason: reason)
    }

    static func capability(capabilityID: String, phaseID: String, payload: Data?) -> ConversationActivityRecord {
        ConversationActivityRecord(
            kind: "capability",
            capabilityID: capabilityID,
            phaseID: phaseID,
            payload: payload
        )
    }
}

struct ConversationMetadataRecord: Codable, Equatable, Sendable {
    /// Reserved for Archive package linkage later.
    var archivePackageID: UUID?
}

enum ConversationSnapshotCodec {
    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    // MARK: Encode domain → records

    static func encodeMessages(_ messages: [ConversationMessage]) throws -> Data {
        try encoder.encode(messages.map(messageRecord(from:)))
    }

    static func encodeActivity(_ activity: ConversationActivity) throws -> Data {
        try encoder.encode(activityRecord(from: activity))
    }

    static func encodeQuickActions(_ actions: [ConversationQuickAction]) throws -> Data {
        try encoder.encode(actions.map(quickActionRecord(from:)))
    }

    static func encodeMetadata(_ metadata: ConversationMetadataRecord = ConversationMetadataRecord()) throws -> Data {
        try encoder.encode(metadata)
    }

    // MARK: Decode records → domain

    static func decodeMessages(_ data: Data) throws -> [ConversationMessage] {
        let started = CFAbsoluteTimeGetCurrent()
        let records = try decoder.decode([ConversationMessageRecord].self, from: data)
        let messages = records.compactMap(message(from:))
        ConversationStartupProbe.recordSnapshotDecode(
            durationMilliseconds: (CFAbsoluteTimeGetCurrent() - started) * 1000
        )
        return messages
    }

    static func decodeActivity(_ data: Data) throws -> ConversationActivity {
        if data.isEmpty {
            return .idle
        }
        let record = try decoder.decode(ConversationActivityRecord.self, from: data)
        return activity(from: record)
    }

    static func decodeQuickActions(_ data: Data) throws -> [ConversationQuickAction] {
        if data.isEmpty {
            return []
        }
        let records = try decoder.decode([ConversationQuickActionRecord].self, from: data)
        return records.map(quickAction(from:))
    }

    static func decodeMetadata(_ data: Data) -> ConversationMetadataRecord {
        (try? decoder.decode(ConversationMetadataRecord.self, from: data)) ?? ConversationMetadataRecord()
    }

    // MARK: Domain ↔ record

    static func messageRecord(from message: ConversationMessage) -> ConversationMessageRecord {
        ConversationMessageRecord(
            id: message.id,
            actor: actorString(message.actor),
            createdAt: message.createdAt,
            text: message.text,
            attachment: message.attachment.map(attachmentRecord(from:)),
            card: message.card.map(cardRecord(from:)),
            quickActions: message.quickActions?.map(quickActionRecord(from:))
        )
    }

    static func message(from record: ConversationMessageRecord) -> ConversationMessage? {
        guard let actor = actor(from: record.actor) else { return nil }
        return ConversationMessage(
            id: record.id,
            actor: actor,
            createdAt: record.createdAt,
            text: record.text,
            attachment: record.attachment.flatMap(attachment(from:)),
            card: record.card.map(card(from:)),
            quickActions: record.quickActions?.map(quickAction(from:))
        )
    }

    static func activityRecord(from activity: ConversationActivity) -> ConversationActivityRecord {
        switch activity {
        case .idle:
            return .idle
        case .awaitingUser:
            return .awaitingUser
        case .processing(let reason):
            return .processing(reason: reason)
        case .capability(let capabilityID, let phaseID, let payload):
            return .capability(capabilityID: capabilityID, phaseID: phaseID, payload: payload)
        }
    }

    static func activity(from record: ConversationActivityRecord) -> ConversationActivity {
        switch record.kind {
        case "awaitingUser":
            return .awaitingUser
        case "processing":
            return .processing(reason: record.reason ?? "unknown")
        case "capability":
            return .capability(
                capabilityID: record.capabilityID ?? "",
                phaseID: record.phaseID ?? "",
                payload: record.payload
            )
        default:
            return .idle
        }
    }

    private static func attachmentRecord(from attachment: ConversationAttachment) -> ConversationAttachmentRecord {
        switch attachment.kind {
        case .photoJPEG(let data):
            return ConversationAttachmentRecord(
                id: attachment.id,
                kind: ConversationAttachmentRecord.photoJPEGKind,
                jpegData: data
            )
        }
    }

    private static func attachment(from record: ConversationAttachmentRecord) -> ConversationAttachment? {
        guard record.kind == ConversationAttachmentRecord.photoJPEGKind, let data = record.jpegData else {
            return nil
        }
        return ConversationAttachment(id: record.id, kind: .photoJPEG(data))
    }

    private static func cardRecord(from card: ConversationCard) -> ConversationCardRecord {
        ConversationCardRecord(
            id: card.id,
            typeID: card.typeID,
            payload: card.payload,
            isInteractive: card.isInteractive
        )
    }

    private static func card(from record: ConversationCardRecord) -> ConversationCard {
        ConversationCard(
            id: record.id,
            typeID: record.typeID,
            payload: record.payload,
            isInteractive: record.isInteractive
        )
    }

    private static func quickActionRecord(from action: ConversationQuickAction) -> ConversationQuickActionRecord {
        ConversationQuickActionRecord(
            id: action.id,
            title: action.title,
            systemImage: action.systemImage,
            accessibilityHint: action.accessibilityHint
        )
    }

    private static func quickAction(from record: ConversationQuickActionRecord) -> ConversationQuickAction {
        ConversationQuickAction(
            id: record.id,
            title: record.title,
            systemImage: record.systemImage,
            accessibilityHint: record.accessibilityHint
        )
    }

    private static func actorString(_ actor: ConversationActor) -> String {
        switch actor {
        case .assistant: return "assistant"
        case .user: return "user"
        case .system: return "system"
        }
    }

    private static func actor(from raw: String) -> ConversationActor? {
        switch raw {
        case "assistant": return .assistant
        case "user": return .user
        case "system": return .system
        default: return nil
        }
    }
}
