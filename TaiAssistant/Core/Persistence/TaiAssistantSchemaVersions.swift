import Foundation
import SwiftData

/// Schema before workout logging entities shipped (meals, goals, conversation only).
enum TaiAssistantSchemaV1: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(1, 0, 0) }

    static var models: [any PersistentModel.Type] {
        [
            GoalProfile.self,
            DailyTargets.self,
            MealLog.self,
            MealItem.self,
            FineTuneCorrection.self,
            RecurringMeal.self,
            AlcoholPlan.self,
            WeightLog.self,
            AppConfig.self,
            PersistedConversation.self,
        ]
    }
}

/// Adds `WorkoutSessionLog` and `WorkoutSetLog` for gym vertical slice.
enum TaiAssistantSchemaV2: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(2, 0, 0) }

    @Model
    final class WorkoutSessionLog {
        @Attribute(.unique) var id: UUID
        var ownerID: String
        var templateID: String
        var title: String
        var startedAt: Date
        var completedAt: Date?
        var statusRaw: String
        var activeSessionJSON: Data?
        @Relationship(deleteRule: .cascade, inverse: \WorkoutSetLog.session) var sets: [WorkoutSetLog]

        init(
            id: UUID = UUID(),
            ownerID: String,
            templateID: String,
            title: String,
            startedAt: Date = .now,
            completedAt: Date? = nil,
            statusRaw: String = GymWorkoutSessionStatus.inProgress.rawValue,
            activeSessionJSON: Data? = nil
        ) {
            self.id = id
            self.ownerID = ownerID
            self.templateID = templateID
            self.title = title
            self.startedAt = startedAt
            self.completedAt = completedAt
            self.statusRaw = statusRaw
            self.activeSessionJSON = activeSessionJSON
            self.sets = []
        }
    }

    @Model
    final class WorkoutSetLog {
        @Attribute(.unique) var id: UUID
        var exerciseID: String
        var exerciseName: String
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

    static var models: [any PersistentModel.Type] {
        TaiAssistantSchemaV1.models + [
            WorkoutSessionLog.self,
            WorkoutSetLog.self,
        ]
    }
}

/// Historical aliases used by migration tests and legacy container helpers.
typealias WorkoutSessionLogV2 = TaiAssistantSchemaV2.WorkoutSessionLog
typealias WorkoutSetLogV2 = TaiAssistantSchemaV2.WorkoutSetLog

/// Adds persisted user workout plans (`GymWorkoutPlan`) — pre-import shape only.
enum TaiAssistantSchemaV3: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(3, 0, 0) }

    /// Historical persisted entity name remains `GymWorkoutPlan` on disk.
    @Model
    final class GymWorkoutPlan {
        @Attribute(.unique) var id: UUID
        var ownerID: String
        var title: String
        /// When set, this row overrides the built-in starter template for the owner.
        var starterTemplateID: String?
        var exercisesJSON: Data
        var prescriptionJSON: Data
        var createdAt: Date
        var updatedAt: Date

        init(
            id: UUID = UUID(),
            ownerID: String,
            title: String,
            starterTemplateID: String? = nil,
            exercisesJSON: Data,
            prescriptionJSON: Data,
            createdAt: Date = .now,
            updatedAt: Date = .now
        ) {
            self.id = id
            self.ownerID = ownerID
            self.title = title
            self.starterTemplateID = starterTemplateID
            self.exercisesJSON = exercisesJSON
            self.prescriptionJSON = prescriptionJSON
            self.createdAt = createdAt
            self.updatedAt = updatedAt
        }
    }

    static var models: [any PersistentModel.Type] {
        TaiAssistantSchemaV1.models + [
            TaiAssistantSchemaV2.WorkoutSessionLog.self,
            TaiAssistantSchemaV2.WorkoutSetLog.self,
            GymWorkoutPlan.self,
        ]
    }
}

/// Historical alias used by migration tests and legacy container helpers.
typealias GymWorkoutPlanV3 = TaiAssistantSchemaV3.GymWorkoutPlan

/// Adds trainer-plan lifecycle and structured import metadata on `GymWorkoutPlan`.
enum TaiAssistantSchemaV4: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(4, 0, 0) }

    static var models: [any PersistentModel.Type] {
        TaiAssistantSchemaV1.models + [
            TaiAssistantSchemaV2.WorkoutSessionLog.self,
            TaiAssistantSchemaV2.WorkoutSetLog.self,
            GymWorkoutPlan.self,
        ]
    }
}

/// Adds workout debrief persistence on `WorkoutSessionLog`.
enum TaiAssistantSchemaV5: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(5, 0, 0) }

    static var models: [any PersistentModel.Type] {
        TaiAssistantSchemaV1.models + [
            WorkoutSessionLog.self,
            WorkoutSetLog.self,
            GymWorkoutPlan.self,
        ]
    }
}

enum TaiAssistantSchema {
    static let current = TaiAssistantSchemaV5.self
    static let currentVersionIdentifier = TaiAssistantSchemaV5.versionIdentifier
}
