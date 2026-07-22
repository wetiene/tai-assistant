import Foundation

enum GymWorkoutSessionStatus: String, Codable, Sendable {
    case inProgress
    case completed
}

/// In-flight workout state persisted for restore after app termination.
struct GymActiveSession: Codable, Equatable, Sendable {
    var sessionID: UUID
    var planReference: GymPlanReference
    var title: String
    var exercises: [GymPlannedExercise]
    var prescription: GymProgramPrescription
    var currentExerciseIndex: Int
    /// 1-based set number within the current exercise.
    var currentSetNumber: Int
    var startedAt: Date
    var status: GymWorkoutSessionStatus

    /// Legacy field for sessions saved before plan references shipped.
    private var templateID: GymProgramTemplateID?

    init(
        sessionID: UUID,
        planReference: GymPlanReference,
        title: String,
        exercises: [GymPlannedExercise],
        prescription: GymProgramPrescription,
        currentExerciseIndex: Int,
        currentSetNumber: Int,
        startedAt: Date,
        status: GymWorkoutSessionStatus
    ) {
        self.sessionID = sessionID
        self.planReference = planReference
        self.title = title
        self.exercises = exercises
        self.prescription = prescription
        self.currentExerciseIndex = currentExerciseIndex
        self.currentSetNumber = currentSetNumber
        self.startedAt = startedAt
        self.status = status
        self.templateID = nil
    }

    enum CodingKeys: String, CodingKey {
        case sessionID, planReference, templateID, title, exercises, prescription
        case currentExerciseIndex, currentSetNumber, startedAt, status
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        sessionID = try container.decode(UUID.self, forKey: .sessionID)
        if let reference = try container.decodeIfPresent(GymPlanReference.self, forKey: .planReference) {
            planReference = reference
        } else if let legacyTemplateID = try container.decodeIfPresent(GymProgramTemplateID.self, forKey: .templateID) {
            planReference = .starter(legacyTemplateID)
        } else {
            planReference = .starter(.upperBody)
        }
        templateID = try container.decodeIfPresent(GymProgramTemplateID.self, forKey: .templateID)
        title = try container.decode(String.self, forKey: .title)
        exercises = try container.decode([GymPlannedExercise].self, forKey: .exercises)
        prescription = try container.decode(GymProgramPrescription.self, forKey: .prescription)
        currentExerciseIndex = try container.decode(Int.self, forKey: .currentExerciseIndex)
        currentSetNumber = try container.decode(Int.self, forKey: .currentSetNumber)
        startedAt = try container.decode(Date.self, forKey: .startedAt)
        status = try container.decode(GymWorkoutSessionStatus.self, forKey: .status)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(sessionID, forKey: .sessionID)
        try container.encode(planReference, forKey: .planReference)
        try container.encode(title, forKey: .title)
        try container.encode(exercises, forKey: .exercises)
        try container.encode(prescription, forKey: .prescription)
        try container.encode(currentExerciseIndex, forKey: .currentExerciseIndex)
        try container.encode(currentSetNumber, forKey: .currentSetNumber)
        try container.encode(startedAt, forKey: .startedAt)
        try container.encode(status, forKey: .status)
    }

    var currentExercise: GymPlannedExercise? {
        guard exercises.indices.contains(currentExerciseIndex) else { return nil }
        return exercises[currentExerciseIndex]
    }

    var totalWorkingSets: Int {
        exercises.count * prescription.workingSetsPerExercise
    }

    var completedSetCount: Int {
        let priorExercises = currentExerciseIndex * prescription.workingSetsPerExercise
        let currentSets = max(0, currentSetNumber - 1)
        return priorExercises + currentSets
    }

    var isComplete: Bool {
        guard let last = exercises.last, let current = currentExercise else { return true }
        let onLastExercise = current.exerciseID == last.exerciseID
        return onLastExercise && currentSetNumber > prescription.workingSetsPerExercise
    }

    mutating func advanceAfterSavedSet() {
        if currentSetNumber < prescription.workingSetsPerExercise {
            currentSetNumber += 1
            return
        }
        if currentExerciseIndex + 1 < exercises.count {
            currentExerciseIndex += 1
            currentSetNumber = 1
        } else {
            currentSetNumber = prescription.workingSetsPerExercise + 1
            status = .completed
        }
    }
}

struct GymPhotoInterpretationSnapshot: Codable, Equatable, Sendable {
    var exerciseCandidates: [GymExerciseCandidateSnapshot]
    var detectedWeight: GymDetectedWeightSnapshot?
    var limitations: [String]
    var requiresConfirmation: Bool

    static let empty = GymPhotoInterpretationSnapshot(
        exerciseCandidates: [],
        detectedWeight: nil,
        limitations: [],
        requiresConfirmation: true
    )
}

struct GymExerciseCandidateSnapshot: Codable, Equatable, Sendable {
    var exerciseID: String
    var displayName: String
    var confidence: Double
    var reason: String
}

struct GymDetectedWeightSnapshot: Codable, Equatable, Sendable {
    var value: Double
    var unit: String
    var confidence: Double
    var reason: String
}

struct GymSetDraft: Equatable, Sendable {
    let draftID: UUID
    let sessionID: UUID
    let plannedExerciseID: String
    let plannedExerciseName: String
    let setNumber: Int
    var selectedExerciseID: String
    var selectedExerciseName: String
    var weightValue: Double?
    var weightUnit: String
    var repetitions: Int?
    var interpretation: GymPhotoInterpretationSnapshot
}
