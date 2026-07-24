import Foundation

// MARK: - Domain-agnostic conversation primitives
//
// The conversation layer understands only messages, cards, composer, attachments,
// quick actions, and conversation state. Domain behaviour lives in capabilities.

enum ConversationActor: Equatable, Sendable {
    case assistant
    case user
    case system
}

struct ConversationAttachment: Identifiable, Equatable, Sendable {
    let id: UUID
    let kind: Kind

    enum Kind: Equatable, Sendable {
        /// In-memory bytes (composer capture / not yet externalised).
        case photoJPEG(Data)
        /// Durable file reference; bytes live in `ConversationAttachmentStore` keyed by `id`.
        case photoJPEGFile
    }

    init(id: UUID = UUID(), kind: Kind) {
        self.id = id
        self.kind = kind
    }

    /// Convenience: externalise immediately via the process store.
    static func storedPhotoJPEG(_ data: Data, id: UUID = UUID(), store: ConversationAttachmentStore = .shared) throws -> ConversationAttachment {
        try store.save(id: id, data: data)
        return ConversationAttachment(id: id, kind: .photoJPEGFile)
    }
}

/// Opaque card payload. Capabilities register typed content; the renderer switches on `typeID`.
struct ConversationCard: Identifiable, Equatable, Sendable {
    let id: UUID
    /// Stable capability-scoped type, e.g. `meal.estimate`.
    let typeID: String
    let payload: Data
    /// When false, historical cards stay visible but non-interactive.
    let isInteractive: Bool

    init(id: UUID = UUID(), typeID: String, payload: Data, isInteractive: Bool = true) {
        self.id = id
        self.typeID = typeID
        self.payload = payload
        self.isInteractive = isInteractive
    }
}

struct ConversationMessage: Identifiable, Equatable, Sendable {
    let id: UUID
    let actor: ConversationActor
    let createdAt: Date
    let text: String?
    let attachment: ConversationAttachment?
    let card: ConversationCard?
    let quickActions: [ConversationQuickAction]?

    init(
        id: UUID = UUID(),
        actor: ConversationActor,
        createdAt: Date = .now,
        text: String? = nil,
        attachment: ConversationAttachment? = nil,
        card: ConversationCard? = nil,
        quickActions: [ConversationQuickAction]? = nil
    ) {
        self.id = id
        self.actor = actor
        self.createdAt = createdAt
        self.text = text
        self.attachment = attachment
        self.card = card
        self.quickActions = quickActions
    }
}

struct ConversationQuickAction: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let systemImage: String?
    let accessibilityHint: String?

    init(
        id: String,
        title: String,
        systemImage: String? = nil,
        accessibilityHint: String? = nil
    ) {
        self.id = id
        self.title = title
        self.systemImage = systemImage
        self.accessibilityHint = accessibilityHint
    }
}

struct ConversationComposerState: Equatable, Sendable {
    var text: String = ""
    var pendingPhotoJPEG: Data? = nil
    var pendingPhotoJPEGs: [Data] = []

    var hasPendingPhotos: Bool {
        pendingPhotoJPEG != nil || !pendingPhotoJPEGs.isEmpty
    }

    var resolvedPendingPhotos: [Data] {
        if !pendingPhotoJPEGs.isEmpty {
            return pendingPhotoJPEGs
        }
        if let pendingPhotoJPEG {
            return [pendingPhotoJPEG]
        }
        return []
    }

    var isSendEnabled: Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty || hasPendingPhotos
    }
}

/// Extensible conversation activity — avoid boolean flag soup.
/// Future capabilities add cases or nest under `.capability` without rewriting the core.
enum ConversationActivity: Equatable, Sendable {
    case idle
    case awaitingUser
    case processing(reason: String)
    /// Opaque capability phase encoded as capabilityID + phaseID (+ optional JSON).
    case capability(capabilityID: String, phaseID: String, payload: Data?)
}

struct ActiveConversation: Identifiable, Equatable, Sendable {
    let id: UUID
    var messages: [ConversationMessage]
    var composer: ConversationComposerState
    var activity: ConversationActivity
    var activeQuickActions: [ConversationQuickAction]
    let createdAt: Date
    /// Last message the user was looking at; restored when practical.
    var scrollAnchorMessageID: UUID?

    init(
        id: UUID = UUID(),
        messages: [ConversationMessage] = [],
        composer: ConversationComposerState = ConversationComposerState(),
        activity: ConversationActivity = .idle,
        activeQuickActions: [ConversationQuickAction] = [],
        createdAt: Date = .now,
        scrollAnchorMessageID: UUID? = nil
    ) {
        self.id = id
        self.messages = messages
        self.composer = composer
        self.activity = activity
        self.activeQuickActions = activeQuickActions
        self.createdAt = createdAt
        self.scrollAnchorMessageID = scrollAnchorMessageID
    }
}

enum ConversationDefaults {
    /// IDs must match `MealCapabilityID.QuickAction` (kept as literals to avoid Domain→Capability coupling).
    static let mealQuickActions: [ConversationQuickAction] = [
        ConversationQuickAction(
            id: "meal.takePhoto",
            title: "Take Photo",
            systemImage: "camera.fill",
            accessibilityHint: "Open the camera to log a meal"
        ),
        ConversationQuickAction(
            id: "meal.describeMeal",
            title: "Describe Meal",
            systemImage: "fork.knife",
            accessibilityHint: "Type a description of what you ate"
        ),
        ConversationQuickAction(
            id: "meal.askTai",
            title: "Ask Tai",
            systemImage: "bubble.left.fill",
            accessibilityHint: "Ask Tai a question"
        ),
    ]

    static let gymStartQuickActions: [ConversationQuickAction] = [
        ConversationAllowedQuickAction.gymStartUpperBody.asConversationQuickAction(),
        ConversationAllowedQuickAction.gymStartLowerBody.asConversationQuickAction(),
        ConversationAllowedQuickAction.gymManagePlans.asConversationQuickAction(),
    ]

    static let gymActiveQuickActions: [ConversationQuickAction] = [
        ConversationAllowedQuickAction.gymTakeSetPhoto.asConversationQuickAction(),
        ConversationAllowedQuickAction.gymManagePlans.asConversationQuickAction(),
        ConversationAllowedQuickAction.gymFinishWorkout.asConversationQuickAction(),
    ]

    static let strengthConversationQuickActions: [ConversationQuickAction] = [
        ConversationAllowedQuickAction.gymTakeSetPhoto.asConversationQuickAction(),
        ConversationAllowedQuickAction.gymFinishWorkout.asConversationQuickAction(),
    ]

    static var strengthConversationQuickActionsForUITest: [ConversationQuickAction] {
        [
            ConversationQuickAction(
                id: "strength.uitest.fixturePhotos",
                title: "Send test photos",
                systemImage: "photo.on.rectangle"
            ),
        ] + strengthConversationQuickActions
    }
}
