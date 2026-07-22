import Foundation
import SwiftData

enum VisibilityScope: String, Codable, CaseIterable {
    case `private`
    case household
    case sharedLink
}

enum MeasurementSystem: String, Codable, CaseIterable {
    case metric
    case imperial
}

enum CorrectionSource: String, Codable, CaseIterable {
    case user
    case model
}

enum MealTiming: String, Codable, CaseIterable {
    case breakfast
    case lunch
    case dinner
    case snack
    case other
}

@Model
final class GoalProfile {
    @Attribute(.unique) var id: UUID
    var ownerID: String
    var visibility: VisibilityScope
    var sharingGroupID: String?
    var title: String
    var notes: String
    var createdAt: Date
    var updatedAt: Date
    @Relationship(inverse: \DailyTargets.goalProfile) var dailyTargets: DailyTargets?

    init(
        id: UUID = UUID(),
        ownerID: String,
        visibility: VisibilityScope = .private,
        sharingGroupID: String? = nil,
        title: String,
        notes: String = "",
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.ownerID = ownerID
        self.visibility = visibility
        self.sharingGroupID = sharingGroupID
        self.title = title
        self.notes = notes
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

@Model
final class DailyTargets {
    @Attribute(.unique) var id: UUID
    var calories: Int
    var proteinGrams: Double
    var carbsGrams: Double
    var fatGrams: Double
    var fiberGrams: Double
    var waterMilliliters: Int
    var updatedAt: Date
    var goalProfile: GoalProfile?

    init(
        id: UUID = UUID(),
        calories: Int,
        proteinGrams: Double,
        carbsGrams: Double,
        fatGrams: Double,
        fiberGrams: Double,
        waterMilliliters: Int,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.calories = calories
        self.proteinGrams = proteinGrams
        self.carbsGrams = carbsGrams
        self.fatGrams = fatGrams
        self.fiberGrams = fiberGrams
        self.waterMilliliters = waterMilliliters
        self.updatedAt = updatedAt
    }
}

@Model
final class MealLog {
    @Attribute(.unique) var id: UUID
    var ownerID: String
    var visibility: VisibilityScope
    var sharingGroupID: String?
    /// When the meal occurred. Determines nutrition-day membership, ordering, and displayed meal time.
    var eatenAt: Date
    var timing: MealTiming
    var notes: String
    var alcoholStandardDrinks: Double
    /// When this meal was first confirmed and persisted. Immutable after creation.
    var createdAt: Date
    /// When this meal was last modified through an approved user action.
    var updatedAt: Date
    @Relationship(deleteRule: .cascade, inverse: \MealItem.mealLog) var items: [MealItem]

    init(
        id: UUID = UUID(),
        ownerID: String,
        visibility: VisibilityScope = .private,
        sharingGroupID: String? = nil,
        eatenAt: Date,
        timing: MealTiming = .other,
        notes: String = "",
        alcoholStandardDrinks: Double = 0,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.ownerID = ownerID
        self.visibility = visibility
        self.sharingGroupID = sharingGroupID
        self.eatenAt = eatenAt
        self.timing = timing
        self.notes = notes
        self.alcoholStandardDrinks = alcoholStandardDrinks
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.items = []
    }
}

@Model
final class MealItem {
    @Attribute(.unique) var id: UUID
    var name: String
    var amount: Double
    var unit: String
    var calories: Int
    var proteinGrams: Double
    var carbsGrams: Double
    var fatGrams: Double
    var fiberGrams: Double
    var alcoholGrams: Double
    var mealLog: MealLog?
    var recurringMeal: RecurringMeal?

    init(
        id: UUID = UUID(),
        name: String,
        amount: Double,
        unit: String,
        calories: Int,
        proteinGrams: Double,
        carbsGrams: Double,
        fatGrams: Double,
        fiberGrams: Double,
        alcoholGrams: Double = 0
    ) {
        self.id = id
        self.name = name
        self.amount = amount
        self.unit = unit
        self.calories = calories
        self.proteinGrams = proteinGrams
        self.carbsGrams = carbsGrams
        self.fatGrams = fatGrams
        self.fiberGrams = fiberGrams
        self.alcoholGrams = alcoholGrams
    }
}

@Model
final class FineTuneCorrection {
    @Attribute(.unique) var id: UUID
    var ownerID: String
    var visibility: VisibilityScope
    var sharingGroupID: String?
    var mealLogID: UUID?
    var mealItemID: UUID?
    var fieldName: String
    var previousValue: String
    var correctedValue: String
    var source: CorrectionSource
    var reason: String
    var createdAt: Date

    init(
        id: UUID = UUID(),
        ownerID: String,
        visibility: VisibilityScope = .private,
        sharingGroupID: String? = nil,
        mealLogID: UUID? = nil,
        mealItemID: UUID? = nil,
        fieldName: String,
        previousValue: String,
        correctedValue: String,
        source: CorrectionSource = .user,
        reason: String = "",
        createdAt: Date = .now
    ) {
        self.id = id
        self.ownerID = ownerID
        self.visibility = visibility
        self.sharingGroupID = sharingGroupID
        self.mealLogID = mealLogID
        self.mealItemID = mealItemID
        self.fieldName = fieldName
        self.previousValue = previousValue
        self.correctedValue = correctedValue
        self.source = source
        self.reason = reason
        self.createdAt = createdAt
    }
}

@Model
final class RecurringMeal {
    @Attribute(.unique) var id: UUID
    var ownerID: String
    var visibility: VisibilityScope
    var sharingGroupID: String?
    var name: String
    var cadenceDays: Int
    var isActive: Bool
    var preferredTiming: MealTiming
    var createdAt: Date
    var updatedAt: Date
    @Relationship(deleteRule: .cascade, inverse: \MealItem.recurringMeal) var items: [MealItem]

    init(
        id: UUID = UUID(),
        ownerID: String,
        visibility: VisibilityScope = .private,
        sharingGroupID: String? = nil,
        name: String,
        cadenceDays: Int,
        isActive: Bool = true,
        preferredTiming: MealTiming = .other,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.ownerID = ownerID
        self.visibility = visibility
        self.sharingGroupID = sharingGroupID
        self.name = name
        self.cadenceDays = cadenceDays
        self.isActive = isActive
        self.preferredTiming = preferredTiming
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.items = []
    }
}

@Model
final class AlcoholPlan {
    @Attribute(.unique) var id: UUID
    var ownerID: String
    var visibility: VisibilityScope
    var sharingGroupID: String?
    var maxStandardDrinksPerDay: Double
    var maxStandardDrinksPerWeek: Double
    var alcoholFreeDaysTarget: Int
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        ownerID: String,
        visibility: VisibilityScope = .private,
        sharingGroupID: String? = nil,
        maxStandardDrinksPerDay: Double,
        maxStandardDrinksPerWeek: Double,
        alcoholFreeDaysTarget: Int,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.ownerID = ownerID
        self.visibility = visibility
        self.sharingGroupID = sharingGroupID
        self.maxStandardDrinksPerDay = maxStandardDrinksPerDay
        self.maxStandardDrinksPerWeek = maxStandardDrinksPerWeek
        self.alcoholFreeDaysTarget = alcoholFreeDaysTarget
        self.updatedAt = updatedAt
    }
}

@Model
final class WeightLog {
    @Attribute(.unique) var id: UUID
    var ownerID: String
    var visibility: VisibilityScope
    var sharingGroupID: String?
    var loggedAt: Date
    var weightKilograms: Double
    var bodyFatPercent: Double?
    var note: String

    init(
        id: UUID = UUID(),
        ownerID: String,
        visibility: VisibilityScope = .private,
        sharingGroupID: String? = nil,
        loggedAt: Date,
        weightKilograms: Double,
        bodyFatPercent: Double? = nil,
        note: String = ""
    ) {
        self.id = id
        self.ownerID = ownerID
        self.visibility = visibility
        self.sharingGroupID = sharingGroupID
        self.loggedAt = loggedAt
        self.weightKilograms = weightKilograms
        self.bodyFatPercent = bodyFatPercent
        self.note = note
    }
}

@Model
final class AppConfig {
    @Attribute(.unique) var id: UUID
    var ownerID: String
    var visibility: VisibilityScope
    var sharingGroupID: String?
    var measurementSystem: MeasurementSystem
    var timeZoneIdentifier: String
    var healthSyncEnabled: Bool
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        ownerID: String,
        visibility: VisibilityScope = .private,
        sharingGroupID: String? = nil,
        measurementSystem: MeasurementSystem = .metric,
        timeZoneIdentifier: String,
        healthSyncEnabled: Bool = false,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.ownerID = ownerID
        self.visibility = visibility
        self.sharingGroupID = sharingGroupID
        self.measurementSystem = measurementSystem
        self.timeZoneIdentifier = timeZoneIdentifier
        self.healthSyncEnabled = healthSyncEnabled
        self.updatedAt = updatedAt
    }
}
