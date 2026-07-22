import Foundation

// MARK: - Entry source

enum StrengthWorkoutEntrySource: String, Codable, Sendable, Equatable {
    case home
    case gymPlans
    case conversation
    case relaunch
    case deepLink
}

// MARK: - Session envelope (persisted in WorkoutSessionLog.activeSessionJSON)

enum WorkoutSessionSnapshotKind: String, Codable, Sendable {
    case legacyGymActive = "legacy_gym_active"
    case strengthCoach = "strength_coach"
}

struct WorkoutSessionSnapshotEnvelope: Codable, Equatable, Sendable {
    var kind: WorkoutSessionSnapshotKind
    var version: Int
    var strengthSession: StrengthWorkoutSession?
    var legacySession: GymActiveSession?

    static func strength(_ session: StrengthWorkoutSession) -> WorkoutSessionSnapshotEnvelope {
        WorkoutSessionSnapshotEnvelope(
            kind: .strengthCoach,
            version: StrengthSessionPersistence.currentSnapshotVersion,
            strengthSession: session,
            legacySession: nil
        )
    }

    static func legacy(_ session: GymActiveSession) -> WorkoutSessionSnapshotEnvelope {
        WorkoutSessionSnapshotEnvelope(
            kind: .legacyGymActive,
            version: 1,
            strengthSession: nil,
            legacySession: session
        )
    }

    init(
        kind: WorkoutSessionSnapshotKind,
        version: Int = StrengthSessionPersistence.currentSnapshotVersion,
        strengthSession: StrengthWorkoutSession?,
        legacySession: GymActiveSession?
    ) {
        self.kind = kind
        self.version = version
        self.strengthSession = strengthSession
        self.legacySession = legacySession
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        kind = try container.decode(WorkoutSessionSnapshotKind.self, forKey: .kind)
        version = try container.decodeIfPresent(Int.self, forKey: .version) ?? 1
        strengthSession = try container.decodeIfPresent(StrengthWorkoutSession.self, forKey: .strengthSession)
        legacySession = try container.decodeIfPresent(GymActiveSession.self, forKey: .legacySession)
    }
}

// MARK: - Strength workout session

struct StrengthWorkoutSession: Codable, Equatable, Sendable, Identifiable {
    var id: UUID { sessionID }
    var sessionID: UUID
    var planReference: GymPlanReference
    var title: String
    var sectionName: String?
    var sectionIndex: Int
    var prescription: GymProgramPrescription
    var exercises: [StrengthExerciseInstance]
    var currentExerciseInstanceID: UUID?
    var currentSetID: UUID?
    var startedAt: Date
    var pausedAt: Date?
    var accumulatedPauseSeconds: TimeInterval
    var status: GymWorkoutSessionStatus
    var mission: String
    var acceptedProposals: [String: StrengthAcceptedProposal]
    var preFlightProposals: [StrengthProgressionProposal]?
    var preFlightCompleted: Bool
    var origin: StrengthWorkoutEntrySource
    var snapshotVersion: Int
    var weightUnit: String
    var lastCoachingMessage: String?

    init(
        sessionID: UUID,
        planReference: GymPlanReference,
        title: String,
        sectionName: String?,
        sectionIndex: Int = 0,
        prescription: GymProgramPrescription,
        exercises: [StrengthExerciseInstance],
        currentExerciseInstanceID: UUID?,
        currentSetID: UUID?,
        startedAt: Date,
        pausedAt: Date?,
        accumulatedPauseSeconds: TimeInterval,
        status: GymWorkoutSessionStatus,
        mission: String,
        acceptedProposals: [String: StrengthAcceptedProposal],
        preFlightProposals: [StrengthProgressionProposal]? = nil,
        preFlightCompleted: Bool = false,
        origin: StrengthWorkoutEntrySource = .home,
        snapshotVersion: Int = StrengthSessionPersistence.currentSnapshotVersion,
        weightUnit: String,
        lastCoachingMessage: String?
    ) {
        self.sessionID = sessionID
        self.planReference = planReference
        self.title = title
        self.sectionName = sectionName
        self.sectionIndex = sectionIndex
        self.prescription = prescription
        self.exercises = exercises
        self.currentExerciseInstanceID = currentExerciseInstanceID
        self.currentSetID = currentSetID
        self.startedAt = startedAt
        self.pausedAt = pausedAt
        self.accumulatedPauseSeconds = accumulatedPauseSeconds
        self.status = status
        self.mission = mission
        self.acceptedProposals = acceptedProposals
        self.preFlightProposals = preFlightProposals
        self.preFlightCompleted = preFlightCompleted
        self.origin = origin
        self.snapshotVersion = snapshotVersion
        self.weightUnit = weightUnit
        self.lastCoachingMessage = lastCoachingMessage
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        sessionID = try container.decode(UUID.self, forKey: .sessionID)
        planReference = try container.decode(GymPlanReference.self, forKey: .planReference)
        title = try container.decode(String.self, forKey: .title)
        sectionName = try container.decodeIfPresent(String.self, forKey: .sectionName)
        sectionIndex = try container.decodeIfPresent(Int.self, forKey: .sectionIndex) ?? 0
        prescription = try container.decode(GymProgramPrescription.self, forKey: .prescription)
        exercises = try container.decode([StrengthExerciseInstance].self, forKey: .exercises)
        currentExerciseInstanceID = try container.decodeIfPresent(UUID.self, forKey: .currentExerciseInstanceID)
        currentSetID = try container.decodeIfPresent(UUID.self, forKey: .currentSetID)
        startedAt = try container.decode(Date.self, forKey: .startedAt)
        pausedAt = try container.decodeIfPresent(Date.self, forKey: .pausedAt)
        accumulatedPauseSeconds = try container.decodeIfPresent(TimeInterval.self, forKey: .accumulatedPauseSeconds) ?? 0
        status = try container.decode(GymWorkoutSessionStatus.self, forKey: .status)
        mission = try container.decode(String.self, forKey: .mission)
        acceptedProposals = try container.decodeIfPresent([String: StrengthAcceptedProposal].self, forKey: .acceptedProposals) ?? [:]
        preFlightProposals = try container.decodeIfPresent([StrengthProgressionProposal].self, forKey: .preFlightProposals)
        preFlightCompleted = try container.decodeIfPresent(Bool.self, forKey: .preFlightCompleted) ?? false
        origin = try container.decodeIfPresent(StrengthWorkoutEntrySource.self, forKey: .origin) ?? .relaunch
        snapshotVersion = try container.decodeIfPresent(Int.self, forKey: .snapshotVersion) ?? 1
        weightUnit = try container.decode(String.self, forKey: .weightUnit)
        lastCoachingMessage = try container.decodeIfPresent(String.self, forKey: .lastCoachingMessage)
    }

    var currentExerciseInstance: StrengthExerciseInstance? {
        guard let currentExerciseInstanceID else { return nil }
        return exercises.first { $0.id == currentExerciseInstanceID }
    }

    var currentSet: StrengthSetRecord? {
        guard let currentSetID else { return nil }
        return exercises.flatMap(\.sets).first { $0.id == currentSetID }
    }

    var isPaused: Bool { pausedAt != nil }

    var elapsedActiveSeconds: TimeInterval {
        let now = Date.now
        let end = status == .completed ? (pausedAt ?? now) : now
        let running = end.timeIntervalSince(startedAt) - accumulatedPauseSeconds
        if let pausedAt, status == .inProgress {
            return pausedAt.timeIntervalSince(startedAt) - accumulatedPauseSeconds
        }
        return max(0, running)
    }

    var completedWorkingSetCount: Int {
        exercises.reduce(0) { partial, exercise in
            partial + exercise.sets.filter { $0.status == .confirmed && !$0.isWarmup }.count
        }
    }

    var totalPlannedWorkingSets: Int {
        exercises.reduce(0) { partial, exercise in
            partial + exercise.sets.filter { !$0.isWarmup }.count
        }
    }

    var isComplete: Bool {
        exercises.allSatisfy { $0.status == .completed || $0.status == .skipped }
    }
}

enum StrengthExerciseStatus: String, Codable, Sendable {
    case pending
    case active
    case completed
    case skipped
}

struct StrengthExerciseInstance: Codable, Equatable, Sendable, Identifiable {
    var id: UUID
    var plannedExercise: GymPlannedExercise
    var status: StrengthExerciseStatus
    var sets: [StrengthSetRecord]

    var exerciseID: String { plannedExercise.id }
    var displayName: String { plannedExercise.displayName }

    var workingSets: [StrengthSetRecord] {
        sets.filter { !$0.isWarmup }
    }

    var confirmedWorkingSets: [StrengthSetRecord] {
        workingSets.filter { $0.status == .confirmed }
    }
}

enum StrengthSetStatus: String, Codable, Sendable {
    case pending
    case confirmed
    case skipped
}

struct StrengthSetRecord: Codable, Equatable, Sendable, Identifiable {
    var id: UUID
    var setNumber: Int
    var isWarmup: Bool
    var plannedReps: Int?
    var suggestedWeight: Double?
    var suggestedReps: Int?
    var confirmedWeight: Double?
    var confirmedReps: Int?
    var weightUnit: String
    var status: StrengthSetStatus
    var isUserAdded: Bool

    init(
        id: UUID,
        setNumber: Int,
        isWarmup: Bool,
        plannedReps: Int?,
        suggestedWeight: Double?,
        suggestedReps: Int?,
        confirmedWeight: Double?,
        confirmedReps: Int?,
        weightUnit: String,
        status: StrengthSetStatus,
        isUserAdded: Bool = false
    ) {
        self.id = id
        self.setNumber = setNumber
        self.isWarmup = isWarmup
        self.plannedReps = plannedReps
        self.suggestedWeight = suggestedWeight
        self.suggestedReps = suggestedReps
        self.confirmedWeight = confirmedWeight
        self.confirmedReps = confirmedReps
        self.weightUnit = weightUnit
        self.status = status
        self.isUserAdded = isUserAdded
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        setNumber = try container.decode(Int.self, forKey: .setNumber)
        isWarmup = try container.decode(Bool.self, forKey: .isWarmup)
        plannedReps = try container.decodeIfPresent(Int.self, forKey: .plannedReps)
        suggestedWeight = try container.decodeIfPresent(Double.self, forKey: .suggestedWeight)
        suggestedReps = try container.decodeIfPresent(Int.self, forKey: .suggestedReps)
        confirmedWeight = try container.decodeIfPresent(Double.self, forKey: .confirmedWeight)
        confirmedReps = try container.decodeIfPresent(Int.self, forKey: .confirmedReps)
        weightUnit = try container.decode(String.self, forKey: .weightUnit)
        status = try container.decode(StrengthSetStatus.self, forKey: .status)
        isUserAdded = try container.decodeIfPresent(Bool.self, forKey: .isUserAdded) ?? false
    }
}

// MARK: - Progression proposals (pre-flight, session-scoped)

enum StrengthProgressionDecision: String, Codable, Sendable {
    case increase
    case hold
    case decrease
}

enum StrengthProgressionConfidence: String, Codable, Sendable, Comparable {
    case low
    case medium
    case high

    private var rank: Int {
        switch self {
        case .low: return 0
        case .medium: return 1
        case .high: return 2
        }
    }

    static func < (lhs: StrengthProgressionConfidence, rhs: StrengthProgressionConfidence) -> Bool {
        lhs.rank < rhs.rank
    }
}

struct StrengthProgressionReasoning: Codable, Equatable, Sendable {
    var observation: String
    var rule: String
    var recommendation: String
    var targetRepsLabel: String
    var fallback: String
}

struct StrengthProgressionProposal: Codable, Equatable, Sendable, Identifiable {
    var id: String { exerciseID }
    var exerciseID: String
    var exerciseName: String
    var currentWeight: Double?
    var proposedWeight: Double?
    var decision: StrengthProgressionDecision
    var repRangeLower: Int
    var repRangeUpper: Int
    var reasoning: StrengthProgressionReasoning
    var confidence: StrengthProgressionConfidence
    var weightUnit: String
}

enum StrengthProposalUserDecision: String, Codable, Sendable {
    case accepted
    case hold
    case custom
}

struct StrengthAcceptedProposal: Codable, Equatable, Sendable {
    var exerciseID: String
    var decision: StrengthProposalUserDecision
    var weight: Double?
    var weightUnit: String
    var originalProposal: StrengthProgressionProposal
}

// MARK: - Debrief (persisted in WorkoutSessionLog.debriefJSON)

struct StrengthWorkoutDebrief: Codable, Equatable, Sendable {
    var sessionID: UUID
    var generatedAt: Date
    var durationSeconds: TimeInterval
    var exercisesCompleted: Int
    var exercisesSkipped: Int
    var totalWorkingSets: Int
    var wins: [StrengthDebriefExerciseSummary]
    var watchItems: [StrengthDebriefExerciseSummary]
    var nextTimeRecommendations: [StrengthDebriefNextRecommendation]
    var recoveryNote: String?
}

struct StrengthDebriefExerciseSummary: Codable, Equatable, Sendable, Identifiable {
    var id: String { exerciseID }
    var exerciseID: String
    var exerciseName: String
    var summaryLine: String
    var detail: String
}

struct StrengthDebriefNextRecommendation: Codable, Equatable, Sendable, Identifiable {
    var id: String { exerciseID }
    var exerciseID: String
    var exerciseName: String
    var recommendation: String
}

// MARK: - Briefing card models

enum StrengthTrainingCardState: Equatable, Sendable {
    case active(StrengthActiveWorkoutCardModel)
    case planned(StrengthPlannedWorkoutCardModel)
}

struct StrengthActiveWorkoutCardModel: Equatable, Sendable {
    var sessionID: UUID
    var title: String
    var elapsedSeconds: TimeInterval
    var completedSets: Int
    var totalSets: Int
    var currentExerciseName: String?
    var nextExerciseName: String?
}

struct StrengthPlannedWorkoutCardModel: Equatable, Sendable {
    var planReference: GymPlanReference
    var sectionIndex: Int
    var title: String
    var estimatedDurationMinutes: Int
    var exerciseCount: Int
    var mission: String
    var primaryProgression: StrengthProgressionProposal?
}
