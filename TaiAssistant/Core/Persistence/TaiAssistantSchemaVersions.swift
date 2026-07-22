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

    static var models: [any PersistentModel.Type] {
        TaiAssistantSchemaV1.models + [
            WorkoutSessionLog.self,
            WorkoutSetLog.self,
        ]
    }
}

/// Adds persisted user workout plans (`GymWorkoutPlan`) — pre-import shape only.
enum TaiAssistantSchemaV3: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(3, 0, 0) }

    static var models: [any PersistentModel.Type] {
        TaiAssistantSchemaV2.models + [
            GymWorkoutPlan.self,
        ]
    }

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
}

/// Historical alias used by migration tests and legacy container helpers.
typealias GymWorkoutPlanV3 = TaiAssistantSchemaV3.GymWorkoutPlan

/// Adds trainer-plan lifecycle and structured import metadata on `GymWorkoutPlan`.
enum TaiAssistantSchemaV4: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(4, 0, 0) }

    static var models: [any PersistentModel.Type] {
        TaiAssistantSchemaV2.models + [
            GymWorkoutPlan.self,
        ]
    }
}

enum TaiAssistantSchema {
    static let current = TaiAssistantSchemaV4.self
    static let currentVersionIdentifier = TaiAssistantSchemaV4.versionIdentifier
}
