import Foundation

enum StrengthConversationCapabilityID {
    static let capability = "strength.conversation"
    static let workoutOverviewCardType = "gym.strengthOverview"
    static let exerciseWorkspaceCardType = "gym.strengthExerciseWorkspace"
    static let photoReviewCardType = "gym.strengthPhotoReview"

    enum Phase: String, Sendable {
        case idle
        case active
        case interpretingPhoto
        case reviewingPhoto
        case savingSet
    }

    enum CardAction: String, Codable, Sendable {
        case applyPhotoReview
        case dismissPhotoReview
        case confirmSet
        case skipSet
        case addEvidence
        case openDedicatedWorkout
        case acceptProgression
        case holdProgression
        case acceptAllProgressions
        case activateExerciseWorkspace
    }
}

/// Minimal card reference — canonical session state lives in `WorkoutSessionLog`.
struct StrengthWorkoutOverviewCardPayload: Codable, Equatable, Sendable {
    var sessionID: UUID
}

struct StrengthExerciseWorkspaceCardPayload: Codable, Equatable, Sendable {
    var sessionID: UUID
    var exerciseInstanceID: UUID
}

struct StrengthPhotoReviewCardPayload: Codable, Equatable, Sendable {
    var reviewID: UUID
    var sessionID: UUID
    var detectedExerciseID: String?
    var detectedExerciseName: String?
    var suggestedWeight: Double?
    var weightUnit: String
    var suggestedReps: Int?
    var interpretation: GymPhotoInterpretationSnapshot
    var photoCount: Int
    var evidenceAttachmentIDs: [UUID]
    var isApplied: Bool
    var imageClassification: PersistedImageClassification?

    init(
        reviewID: UUID,
        sessionID: UUID,
        detectedExerciseID: String?,
        detectedExerciseName: String?,
        suggestedWeight: Double?,
        weightUnit: String,
        suggestedReps: Int?,
        interpretation: GymPhotoInterpretationSnapshot,
        photoCount: Int,
        evidenceAttachmentIDs: [UUID] = [],
        isApplied: Bool,
        imageClassification: PersistedImageClassification? = nil
    ) {
        self.reviewID = reviewID
        self.sessionID = sessionID
        self.detectedExerciseID = detectedExerciseID
        self.detectedExerciseName = detectedExerciseName
        self.suggestedWeight = suggestedWeight
        self.weightUnit = weightUnit
        self.suggestedReps = suggestedReps
        self.interpretation = interpretation
        self.photoCount = photoCount
        self.evidenceAttachmentIDs = evidenceAttachmentIDs
        self.isApplied = isApplied
        self.imageClassification = imageClassification
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        reviewID = try container.decode(UUID.self, forKey: .reviewID)
        sessionID = try container.decode(UUID.self, forKey: .sessionID)
        detectedExerciseID = try container.decodeIfPresent(String.self, forKey: .detectedExerciseID)
        detectedExerciseName = try container.decodeIfPresent(String.self, forKey: .detectedExerciseName)
        suggestedWeight = try container.decodeIfPresent(Double.self, forKey: .suggestedWeight)
        weightUnit = try container.decode(String.self, forKey: .weightUnit)
        suggestedReps = try container.decodeIfPresent(Int.self, forKey: .suggestedReps)
        interpretation = try container.decode(GymPhotoInterpretationSnapshot.self, forKey: .interpretation)
        photoCount = try container.decode(Int.self, forKey: .photoCount)
        evidenceAttachmentIDs = try container.decodeIfPresent([UUID].self, forKey: .evidenceAttachmentIDs) ?? []
        isApplied = try container.decode(Bool.self, forKey: .isApplied)
        imageClassification = try container.decodeIfPresent(PersistedImageClassification.self, forKey: .imageClassification)
    }
}

struct StrengthConversationActivityPayload: Codable, Equatable, Sendable {
    var sessionID: UUID

    static func encode(_ payload: StrengthConversationActivityPayload) -> Data? {
        try? JSONEncoder().encode(payload)
    }

    static func decode(_ data: Data?) -> StrengthConversationActivityPayload? {
        guard let data, !data.isEmpty else { return nil }
        return try? JSONDecoder().decode(StrengthConversationActivityPayload.self, from: data)
    }
}

enum StrengthConversationActivityCodec {
    static func makeActivity(phase: StrengthConversationCapabilityID.Phase, sessionID: UUID) -> ConversationActivity {
        let payload = StrengthConversationActivityPayload(sessionID: sessionID)
        return .capability(
            capabilityID: StrengthConversationCapabilityID.capability,
            phaseID: phase.rawValue,
            payload: StrengthConversationActivityPayload.encode(payload)
        )
    }

    static func sessionID(from activity: ConversationActivity) -> UUID? {
        guard case let .capability(capabilityID, _, payload) = activity,
              capabilityID == StrengthConversationCapabilityID.capability
        else { return nil }
        return StrengthConversationActivityPayload.decode(payload)?.sessionID
    }
}

enum StrengthWorkoutOverviewCardCodec {
    static func makeCard(payload: StrengthWorkoutOverviewCardPayload, interactive: Bool) -> ConversationCard {
        ConversationCard(
            typeID: StrengthConversationCapabilityID.workoutOverviewCardType,
            payload: (try? JSONEncoder().encode(payload)) ?? Data(),
            isInteractive: interactive
        )
    }

    static func decode(_ data: Data) -> StrengthWorkoutOverviewCardPayload? {
        try? JSONDecoder().decode(StrengthWorkoutOverviewCardPayload.self, from: data)
    }
}

enum StrengthExerciseWorkspaceCardCodec {
    static func makeCard(payload: StrengthExerciseWorkspaceCardPayload, interactive: Bool) -> ConversationCard {
        ConversationCard(
            typeID: StrengthConversationCapabilityID.exerciseWorkspaceCardType,
            payload: (try? JSONEncoder().encode(payload)) ?? Data(),
            isInteractive: interactive
        )
    }

    static func decode(_ data: Data) -> StrengthExerciseWorkspaceCardPayload? {
        try? JSONDecoder().decode(StrengthExerciseWorkspaceCardPayload.self, from: data)
    }
}

enum StrengthPhotoReviewCardCodec {
    static func makeCard(payload: StrengthPhotoReviewCardPayload, interactive: Bool) -> ConversationCard {
        ConversationCard(
            typeID: StrengthConversationCapabilityID.photoReviewCardType,
            payload: (try? JSONEncoder().encode(payload)) ?? Data(),
            isInteractive: interactive
        )
    }

    static func decode(_ data: Data) -> StrengthPhotoReviewCardPayload? {
        try? JSONDecoder().decode(StrengthPhotoReviewCardPayload.self, from: data)
    }
}

struct StrengthPhotoReviewState: Equatable, Sendable {
    var reviewID: UUID
    var interpretation: GymPhotoInterpretationSnapshot
    var detectedExerciseID: String?
    var detectedExerciseName: String?
    var suggestedWeight: Double?
    var weightUnit: String
    var suggestedReps: Int?
    var photoCount: Int
    var evidenceAttachmentIDs: [UUID]
    var imageClassification: PersistedImageClassification?
}
