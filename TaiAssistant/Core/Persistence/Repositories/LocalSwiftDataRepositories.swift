import Foundation
import SwiftData

final class LocalSwiftDataGoalRepository: GoalRepository {
    private let container: ModelContainer

    init(container: ModelContainer) {
        self.container = container
    }

    func fetchGoalProfiles(ownerID: String) async throws -> [GoalProfile] {
        let context = ModelContext(container)
        let descriptor = FetchDescriptor<GoalProfile>(
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )
        return try context.fetch(descriptor).filter { $0.ownerID == ownerID }
    }

    func upsertGoalProfile(_ profile: GoalProfile) async throws {
        let context = ModelContext(container)
        let existing = try context.fetch(FetchDescriptor<GoalProfile>())
            .first { $0.id == profile.id }

        if let existing {
            existing.title = profile.title
            existing.notes = profile.notes
            existing.visibility = profile.visibility
            existing.sharingGroupID = profile.sharingGroupID
            existing.updatedAt = .now
        } else {
            profile.updatedAt = .now
            context.insert(profile)
        }
        try context.save()
    }

    func fetchDailyTargets(goalProfileID: UUID) async throws -> DailyTargets? {
        let context = ModelContext(container)
        let goal = try context.fetch(FetchDescriptor<GoalProfile>())
            .first { $0.id == goalProfileID }
        return goal?.dailyTargets
    }

    func saveDailyTargets(_ targets: DailyTargets, goalProfileID: UUID) async throws {
        let context = ModelContext(container)
        guard let goal = try context.fetch(FetchDescriptor<GoalProfile>())
            .first(where: { $0.id == goalProfileID }) else { return }

        let existing = goal.dailyTargets
        if let existing {
            existing.calories = targets.calories
            existing.proteinGrams = targets.proteinGrams
            existing.carbsGrams = targets.carbsGrams
            existing.fatGrams = targets.fatGrams
            existing.fiberGrams = targets.fiberGrams
            existing.waterMilliliters = targets.waterMilliliters
            existing.updatedAt = .now
        } else {
            targets.goalProfile = goal
            context.insert(targets)
        }
        goal.updatedAt = .now
        try context.save()
    }
}

final class LocalSwiftDataMealRepository: MealRepository {
    private let container: ModelContainer

    init(container: ModelContainer) {
        self.container = container
    }

    func fetchMealLogs(ownerID: String, from startDate: Date, to endDate: Date) async throws -> [MealLog] {
        let context = ModelContext(container)
        let predicate = #Predicate<MealLog> { meal in
            meal.ownerID == ownerID && meal.eatenAt >= startDate && meal.eatenAt < endDate
        }
        let descriptor = FetchDescriptor<MealLog>(
            predicate: predicate,
            sortBy: [SortDescriptor(\.eatenAt, order: .reverse)]
        )
        return try context.fetch(descriptor)
    }

    func createMealLog(_ meal: MealLog) async throws {
        let context = ModelContext(container)
        let mealID = meal.id
        let clashDescriptor = FetchDescriptor<MealLog>(
            predicate: #Predicate<MealLog> { $0.id == mealID }
        )
        if try context.fetch(clashDescriptor).first != nil {
            throw MealRepositoryError.mealLogAlreadyExists(id: meal.id)
        }
        meal.updatedAt = .now
        context.insert(meal)
        try context.save()
    }

    func updateMealLog(_ meal: MealLog) async throws {
        let context = ModelContext(container)
        let mealID = meal.id
        let descriptor = FetchDescriptor<MealLog>(
            predicate: #Predicate<MealLog> { $0.id == mealID }
        )
        guard let existing = try context.fetch(descriptor).first else {
            throw MealRepositoryError.mealLogNotFound(id: meal.id)
        }

        MealLogWriteSemantics.assertCreatedAtImmutableOnUpdate(existing: existing, incoming: meal)

        // Top-level truth on the persisted row only.
        existing.eatenAt = meal.eatenAt
        existing.timing = meal.timing
        existing.notes = meal.notes
        existing.alcoholStandardDrinks = meal.alcoholStandardDrinks
        existing.visibility = meal.visibility
        existing.sharingGroupID = meal.sharingGroupID

        // Full line-item replacement: remove old rows, attach fresh clones (V1 — no partial diff).
        let staleItems = Array(existing.items)
        for item in staleItems {
            context.delete(item)
        }
        existing.items = []

        let replacement = meal.items.map { Self.cloneMealItemDetached(from: $0) }
        for item in replacement {
            item.mealLog = existing
            context.insert(item)
        }
        existing.items = replacement
        existing.updatedAt = .now
        try context.save()
    }

    func duplicateMealLog(from source: MealLog, eatenAt: Date) -> MealLog {
        let copy = MealLog(
            ownerID: source.ownerID,
            visibility: source.visibility,
            sharingGroupID: source.sharingGroupID,
            eatenAt: eatenAt,
            timing: source.timing,
            notes: source.notes,
            alcoholStandardDrinks: source.alcoholStandardDrinks
        )
        copy.items = source.items.map { Self.cloneMealItemDetached(from: $0) }
        return copy
    }

    func duplicateMealLog(fromRecurringTemplate template: RecurringMeal, eatenAt: Date) -> MealLog {
        let copy = MealLog(
            ownerID: template.ownerID,
            visibility: template.visibility,
            sharingGroupID: template.sharingGroupID,
            eatenAt: eatenAt,
            timing: template.preferredTiming,
            notes: template.name,
            alcoholStandardDrinks: 0
        )
        copy.items = template.items.map { Self.cloneMealItemDetached(from: $0) }
        return copy
    }

    func deleteMealLog(id: UUID) async throws {
        let context = ModelContext(container)
        let descriptor = FetchDescriptor<MealLog>(
            predicate: #Predicate<MealLog> { $0.id == id }
        )
        guard let existing = try context.fetch(descriptor).first else { return }
        context.delete(existing)
        try context.save()
    }

    /// New `MealItem` row (new identity) for persistence; not linked to any log until caller sets `mealLog`.
    private static func cloneMealItemDetached(from source: MealItem) -> MealItem {
        MealItem(
            name: source.name,
            amount: source.amount,
            unit: source.unit,
            calories: source.calories,
            proteinGrams: source.proteinGrams,
            carbsGrams: source.carbsGrams,
            fatGrams: source.fatGrams,
            fiberGrams: source.fiberGrams,
            alcoholGrams: source.alcoholGrams
        )
    }
}

final class LocalSwiftDataFineTuneCorrectionRepository: FineTuneCorrectionRepository {
    private let container: ModelContainer

    init(container: ModelContainer) {
        self.container = container
    }

    func fetchCorrections(ownerID: String, since: Date?) async throws -> [FineTuneCorrection] {
        let context = ModelContext(container)
        let descriptor = FetchDescriptor<FineTuneCorrection>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        let corrections = try context.fetch(descriptor).filter { $0.ownerID == ownerID }
        guard let since else { return corrections }
        return corrections.filter { $0.createdAt >= since }
    }

    func saveCorrection(_ correction: FineTuneCorrection) async throws {
        let context = ModelContext(container)
        context.insert(correction)
        try context.save()
    }
}

final class LocalSwiftDataRecurringMealRepository: RecurringMealRepository {
    private let container: ModelContainer

    init(container: ModelContainer) {
        self.container = container
    }

    func fetchRecurringMeals(ownerID: String, activeOnly: Bool) async throws -> [RecurringMeal] {
        let context = ModelContext(container)
        let descriptor = FetchDescriptor<RecurringMeal>(
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )
        let recurringMeals = try context.fetch(descriptor).filter { $0.ownerID == ownerID }
        return activeOnly ? recurringMeals.filter(\.isActive) : recurringMeals
    }

    func upsertRecurringMeal(_ recurringMeal: RecurringMeal) async throws {
        let context = ModelContext(container)
        let existing = try context.fetch(FetchDescriptor<RecurringMeal>())
            .first { $0.id == recurringMeal.id }

        if let existing {
            existing.name = recurringMeal.name
            existing.cadenceDays = recurringMeal.cadenceDays
            existing.isActive = recurringMeal.isActive
            existing.preferredTiming = recurringMeal.preferredTiming
            existing.visibility = recurringMeal.visibility
            existing.sharingGroupID = recurringMeal.sharingGroupID
            existing.updatedAt = .now
        } else {
            recurringMeal.updatedAt = .now
            context.insert(recurringMeal)
        }
        try context.save()
    }
}

final class LocalSwiftDataAlcoholPlanRepository: AlcoholPlanRepository {
    private let container: ModelContainer

    init(container: ModelContainer) {
        self.container = container
    }

    func fetchAlcoholPlan(ownerID: String) async throws -> AlcoholPlan? {
        let context = ModelContext(container)
        let descriptor = FetchDescriptor<AlcoholPlan>(
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )
        return try context.fetch(descriptor).first { $0.ownerID == ownerID }
    }

    func saveAlcoholPlan(_ plan: AlcoholPlan) async throws {
        let context = ModelContext(container)
        let existing = try context.fetch(FetchDescriptor<AlcoholPlan>())
            .first { $0.ownerID == plan.ownerID }

        if let existing {
            existing.maxStandardDrinksPerDay = plan.maxStandardDrinksPerDay
            existing.maxStandardDrinksPerWeek = plan.maxStandardDrinksPerWeek
            existing.alcoholFreeDaysTarget = plan.alcoholFreeDaysTarget
            existing.visibility = plan.visibility
            existing.sharingGroupID = plan.sharingGroupID
            existing.updatedAt = .now
        } else {
            plan.updatedAt = .now
            context.insert(plan)
        }
        try context.save()
    }
}

final class LocalSwiftDataWeightLogRepository: WeightLogRepository {
    private let container: ModelContainer

    init(container: ModelContainer) {
        self.container = container
    }

    func fetchWeightLogs(ownerID: String, limit: Int?) async throws -> [WeightLog] {
        let context = ModelContext(container)
        let descriptor = FetchDescriptor<WeightLog>(
            sortBy: [SortDescriptor(\.loggedAt, order: .reverse)]
        )
        let logs = try context.fetch(descriptor).filter { $0.ownerID == ownerID }
        guard let limit else { return logs }
        return Array(logs.prefix(limit))
    }

    func saveWeightLog(_ log: WeightLog) async throws {
        let context = ModelContext(container)
        context.insert(log)
        try context.save()
    }
}

final class LocalSwiftDataAppConfigRepository: AppConfigRepository {
    private let container: ModelContainer

    init(container: ModelContainer) {
        self.container = container
    }

    func fetchAppConfig(ownerID: String) async throws -> AppConfig? {
        let context = ModelContext(container)
        let descriptor = FetchDescriptor<AppConfig>(
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )
        return try context.fetch(descriptor).first { $0.ownerID == ownerID }
    }

    func saveAppConfig(_ config: AppConfig) async throws {
        let context = ModelContext(container)
        let existing = try context.fetch(FetchDescriptor<AppConfig>())
            .first { $0.ownerID == config.ownerID }

        if let existing {
            existing.measurementSystem = config.measurementSystem
            existing.timeZoneIdentifier = config.timeZoneIdentifier
            existing.healthSyncEnabled = config.healthSyncEnabled
            existing.visibility = config.visibility
            existing.sharingGroupID = config.sharingGroupID
            existing.updatedAt = .now
        } else {
            config.updatedAt = .now
            context.insert(config)
        }
        try context.save()
    }
}
