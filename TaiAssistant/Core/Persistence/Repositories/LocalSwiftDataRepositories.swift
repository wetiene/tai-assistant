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
            predicate: #Predicate { $0.ownerID == ownerID },
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )
        return try context.fetch(descriptor)
    }

    func upsertGoalProfile(_ profile: GoalProfile) async throws {
        let context = ModelContext(container)
        let existing = try context.fetch(
            FetchDescriptor<GoalProfile>(
                predicate: #Predicate { $0.id == profile.id }
            )
        ).first

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
        let goal = try context.fetch(
            FetchDescriptor<GoalProfile>(
                predicate: #Predicate { $0.id == goalProfileID }
            )
        ).first
        return goal?.dailyTargets
    }

    func saveDailyTargets(_ targets: DailyTargets, goalProfileID: UUID) async throws {
        let context = ModelContext(container)
        guard let goal = try context.fetch(
            FetchDescriptor<GoalProfile>(
                predicate: #Predicate { $0.id == goalProfileID }
            )
        ).first else { return }

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
        let descriptor = FetchDescriptor<MealLog>(
            predicate: #Predicate {
                $0.ownerID == ownerID && $0.eatenAt >= startDate && $0.eatenAt < endDate
            },
            sortBy: [SortDescriptor(\.eatenAt, order: .reverse)]
        )
        return try context.fetch(descriptor)
    }

    func upsertMealLog(_ mealLog: MealLog) async throws {
        let context = ModelContext(container)
        let existing = try context.fetch(
            FetchDescriptor<MealLog>(
                predicate: #Predicate { $0.id == mealLog.id }
            )
        ).first

        if let existing {
            existing.eatenAt = mealLog.eatenAt
            existing.timing = mealLog.timing
            existing.notes = mealLog.notes
            existing.alcoholStandardDrinks = mealLog.alcoholStandardDrinks
            existing.visibility = mealLog.visibility
            existing.sharingGroupID = mealLog.sharingGroupID
            existing.updatedAt = .now
        } else {
            mealLog.updatedAt = .now
            context.insert(mealLog)
        }
        try context.save()
    }

    func deleteMealLog(id: UUID) async throws {
        let context = ModelContext(container)
        guard let existing = try context.fetch(
            FetchDescriptor<MealLog>(
                predicate: #Predicate { $0.id == id }
            )
        ).first else { return }
        context.delete(existing)
        try context.save()
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
            predicate: #Predicate { $0.ownerID == ownerID },
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        let corrections = try context.fetch(descriptor)
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
            predicate: #Predicate { $0.ownerID == ownerID },
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )
        let recurringMeals = try context.fetch(descriptor)
        return activeOnly ? recurringMeals.filter(\.isActive) : recurringMeals
    }

    func upsertRecurringMeal(_ recurringMeal: RecurringMeal) async throws {
        let context = ModelContext(container)
        let existing = try context.fetch(
            FetchDescriptor<RecurringMeal>(
                predicate: #Predicate { $0.id == recurringMeal.id }
            )
        ).first

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
            predicate: #Predicate { $0.ownerID == ownerID },
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )
        return try context.fetch(descriptor).first
    }

    func saveAlcoholPlan(_ plan: AlcoholPlan) async throws {
        let context = ModelContext(container)
        let existing = try context.fetch(
            FetchDescriptor<AlcoholPlan>(
                predicate: #Predicate { $0.ownerID == plan.ownerID }
            )
        ).first

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
            predicate: #Predicate { $0.ownerID == ownerID },
            sortBy: [SortDescriptor(\.loggedAt, order: .reverse)]
        )
        let logs = try context.fetch(descriptor)
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
            predicate: #Predicate { $0.ownerID == ownerID },
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )
        return try context.fetch(descriptor).first
    }

    func saveAppConfig(_ config: AppConfig) async throws {
        let context = ModelContext(container)
        let existing = try context.fetch(
            FetchDescriptor<AppConfig>(
                predicate: #Predicate { $0.ownerID == config.ownerID }
            )
        ).first

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
