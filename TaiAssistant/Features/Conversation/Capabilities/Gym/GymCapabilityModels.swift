import Foundation

enum GymCapabilityID {
    static let capability = "gym"
    static let workoutPlanCardType = "gym.workoutPlan"
    static let setConfirmCardType = "gym.setConfirm"

    enum Phase: String, Sendable {
        case idle
        case active
        case interpreting
        case reviewingSet
        case savingSet
        case completed
    }

    enum QuickAction {
        static let startUpperBody = "gym.startUpperBody"
        static let startLowerBody = "gym.startLowerBody"
        static let takeSetPhoto = "gym.takeSetPhoto"
        static let finishWorkout = "gym.finishWorkout"
        static let resumeWorkout = "gym.resumeWorkout"
    }

    enum CardAction: String, Codable, Sendable {
        case saveSet
        case retakePhoto
        case cancelSet
    }
}

struct GymTemplateExerciseOption: Codable, Equatable, Sendable, Identifiable {
    var id: String { exerciseID }
    var exerciseID: String
    var displayName: String
    var isOptional: Bool
}

struct GymCapabilityActivityPayload: Codable, Equatable, Sendable {
    var sessionID: UUID
    var activeSession: GymActiveSession

    static func encode(_ payload: GymCapabilityActivityPayload) -> Data? {
        try? JSONEncoder().encode(payload)
    }

    static func decode(_ data: Data?) -> GymCapabilityActivityPayload? {
        guard let data, !data.isEmpty else { return nil }
        return try? JSONDecoder().decode(GymCapabilityActivityPayload.self, from: data)
    }
}

enum GymCapabilityActivityCodec {
    static func makeActivity(phase: GymCapabilityID.Phase, session: GymActiveSession) -> ConversationActivity {
        let payload = GymCapabilityActivityPayload(sessionID: session.sessionID, activeSession: session)
        return .capability(
            capabilityID: GymCapabilityID.capability,
            phaseID: phase.rawValue,
            payload: GymCapabilityActivityPayload.encode(payload)
        )
    }

    static func activeSession(from activity: ConversationActivity) -> GymActiveSession? {
        guard case let .capability(capabilityID, _, payload) = activity,
              capabilityID == GymCapabilityID.capability
        else { return nil }
        return GymCapabilityActivityPayload.decode(payload)?.activeSession
    }
}

struct GymWorkoutPlanCardPayload: Codable, Equatable, Sendable {
    var sessionID: UUID
    var title: String
    var exercises: [GymPlanExerciseRow]
    var currentExerciseIndex: Int
    var currentSetNumber: Int
    var workingSetsPerExercise: Int
    var repRangeLabel: String
    var coachingNote: String
    var isActive: Bool
}

struct GymPlanExerciseRow: Codable, Equatable, Sendable, Identifiable {
    var id: String { exerciseID }
    var exerciseID: String
    var displayName: String
    var isOptional: Bool
    var isCurrent: Bool
    var completedSets: Int
    var workingSets: Int
}

struct GymSetConfirmationCardPayload: Codable, Equatable, Sendable {
    var draftID: UUID
    var sessionID: UUID
    var plannedExerciseID: String
    var plannedExerciseName: String
    var setNumber: Int
    var selectedExerciseID: String
    var selectedExerciseName: String
    var weightValue: Double?
    var weightUnit: String
    var repetitions: Int?
    var interpretation: GymPhotoInterpretationSnapshot
    var templateExerciseOptions: [GymTemplateExerciseOption]
    var isSaved: Bool

    /// Legacy decode keys — ignored for save validation.
    private var exerciseConfirmed: Bool?
    private var weightConfirmed: Bool?

  enum CodingKeys: String, CodingKey {
    case draftID, sessionID, plannedExerciseID, plannedExerciseName, setNumber
    case selectedExerciseID, selectedExerciseName, weightValue, weightUnit, repetitions
    case interpretation, templateExerciseOptions, isSaved
    case exerciseConfirmed, weightConfirmed
  }

    init(
        draftID: UUID,
        sessionID: UUID,
        plannedExerciseID: String,
        plannedExerciseName: String,
        setNumber: Int,
        selectedExerciseID: String,
        selectedExerciseName: String,
        weightValue: Double?,
        weightUnit: String,
        repetitions: Int?,
        interpretation: GymPhotoInterpretationSnapshot,
        templateExerciseOptions: [GymTemplateExerciseOption],
        isSaved: Bool,
        exerciseConfirmed: Bool? = nil,
        weightConfirmed: Bool? = nil
    ) {
        self.draftID = draftID
        self.sessionID = sessionID
        self.plannedExerciseID = plannedExerciseID
        self.plannedExerciseName = plannedExerciseName
        self.setNumber = setNumber
        self.selectedExerciseID = selectedExerciseID
        self.selectedExerciseName = selectedExerciseName
        self.weightValue = weightValue
        self.weightUnit = weightUnit
        self.repetitions = repetitions
        self.interpretation = interpretation
        self.templateExerciseOptions = templateExerciseOptions
        self.isSaved = isSaved
        self.exerciseConfirmed = exerciseConfirmed
        self.weightConfirmed = weightConfirmed
    }

    var canSaveSet: Bool {
        GymSetCardValidation.canSave(
            selectedExerciseID: selectedExerciseID,
            templateExerciseOptions: templateExerciseOptions,
            weightValue: weightValue,
            repetitions: repetitions,
            isSaved: isSaved
        )
    }
}

enum GymWorkoutPlanCardCodec {
    static func makeCard(payload: GymWorkoutPlanCardPayload, interactive: Bool) -> ConversationCard {
        ConversationCard(
            typeID: GymCapabilityID.workoutPlanCardType,
            payload: (try? JSONEncoder().encode(payload)) ?? Data(),
            isInteractive: interactive
        )
    }

    static func decode(_ data: Data) -> GymWorkoutPlanCardPayload? {
        try? JSONDecoder().decode(GymWorkoutPlanCardPayload.self, from: data)
    }
}

enum GymSetConfirmationCardCodec {
    static func makeCard(payload: GymSetConfirmationCardPayload, interactive: Bool) -> ConversationCard {
        ConversationCard(
            typeID: GymCapabilityID.setConfirmCardType,
            payload: (try? JSONEncoder().encode(payload)) ?? Data(),
            isInteractive: interactive
        )
    }

    static func decode(_ data: Data) -> GymSetConfirmationCardPayload? {
        try? JSONDecoder().decode(GymSetConfirmationCardPayload.self, from: data)
    }
}

enum GymInterpretationOutcome: Equatable, Sendable {
    struct Success: Equatable, Sendable {
        var draft: GymSetDraft
        var assistantNote: String?
    }

    case success(Success)
    case failure(String)
}

enum GymCapabilitySaveError: Error, Equatable {
    case nothingToSave
    case persistenceFailed
    case validationFailed(String)
    case alreadySaved
    case draftMismatch
    case noActiveSession
}
