import Foundation
import SwiftData

@Model
final class WorkoutSessionLog {
    @Attribute(.unique) var id: UUID
    var ownerID: String
    var templateID: String
    var title: String
    var startedAt: Date
    var completedAt: Date?
    /// `inProgress` | `completed`
    var statusRaw: String
    /// JSON-encoded session snapshot for in-progress restore.
    var activeSessionJSON: Data?
    /// JSON-encoded `StrengthWorkoutDebrief` after completion.
    var debriefJSON: Data?
    @Relationship(deleteRule: .cascade, inverse: \WorkoutSetLog.session) var sets: [WorkoutSetLog]

    init(
        id: UUID = UUID(),
        ownerID: String,
        templateID: String,
        title: String,
        startedAt: Date = .now,
        completedAt: Date? = nil,
        statusRaw: String = GymWorkoutSessionStatus.inProgress.rawValue,
        activeSessionJSON: Data? = nil,
        debriefJSON: Data? = nil
    ) {
        self.id = id
        self.ownerID = ownerID
        self.templateID = templateID
        self.title = title
        self.startedAt = startedAt
        self.completedAt = completedAt
        self.statusRaw = statusRaw
        self.activeSessionJSON = activeSessionJSON
        self.debriefJSON = debriefJSON
        self.sets = []
    }

    var status: GymWorkoutSessionStatus {
        get { GymWorkoutSessionStatus(rawValue: statusRaw) ?? .inProgress }
        set { statusRaw = newValue.rawValue }
    }
}

@Model
final class WorkoutSetLog {
    @Attribute(.unique) var id: UUID
    var exerciseID: String
    var exerciseName: String
    /// 1-based set number within the exercise.
    var setNumber: Int
    var weightValue: Double
    var weightUnit: String
    var repetitions: Int
    var performedAt: Date
    var session: WorkoutSessionLog?

    init(
        id: UUID = UUID(),
        exerciseID: String,
        exerciseName: String,
        setNumber: Int,
        weightValue: Double,
        weightUnit: String,
        repetitions: Int,
        performedAt: Date = .now
    ) {
        self.id = id
        self.exerciseID = exerciseID
        self.exerciseName = exerciseName
        self.setNumber = setNumber
        self.weightValue = weightValue
        self.weightUnit = weightUnit
        self.repetitions = repetitions
        self.performedAt = performedAt
    }
}
