import Foundation

struct MockAIService: AIService {
    func send(message: String, context: [String: String]) async throws -> String {
        "Mock response from Tai: \(message)"
    }

    func interpretMeal(request: AIInterpretMealRequest) async throws -> AIInterpretMealResponse {
        try await Task.sleep(nanoseconds: 300_000_000)

        let normalized = request.text?.lowercased() ?? ""
        let now = Date()
        let isoFormatter = ISO8601DateFormatter()
        let containsImage = request.image?.base64Data?.isEmpty == false || request.image?.uploadReference?.isEmpty == false

        let defaultMeal = AIInterpretedMeal(
            label: "Detected meal",
            timing: "other",
            eatenAtGuessISO8601: isoFormatter.string(from: now),
            items: [
                AIInterpretedMealItem(
                    name: "Main plate",
                    amount: 280,
                    unit: "g",
                    calories: 370,
                    proteinGrams: 24,
                    carbsGrams: 35,
                    fatGrams: 14,
                    fiberGrams: 4
                ),
                AIInterpretedMealItem(
                    name: "Side",
                    amount: 120,
                    unit: "g",
                    calories: 150,
                    proteinGrams: 8,
                    carbsGrams: 19,
                    fatGrams: 4,
                    fiberGrams: 3
                )
            ],
            calories: containsImage ? 610 : 520,
            proteinGrams: 32,
            carbsGrams: 54,
            fatGrams: 18,
            confidence: 0.63,
            alternatives: []
        )

        if normalized.contains("breakfast") || normalized.contains("shake") {
            return AIInterpretMealResponse(
                interpretedMeals: [
                    AIInterpretedMeal(
                        label: normalized.contains("shake") ? "Protein shake" : "Usual breakfast",
                        timing: "breakfast",
                        eatenAtGuessISO8601: isoFormatter.string(from: now),
                        items: [
                            AIInterpretedMealItem(name: "Whey protein", amount: 35, unit: "g", calories: 140, proteinGrams: 28, carbsGrams: 3, fatGrams: 2, fiberGrams: 0),
                            AIInterpretedMealItem(name: "Banana", amount: 100, unit: "g", calories: 89, proteinGrams: 1.1, carbsGrams: 23, fatGrams: 0.3, fiberGrams: 2.6),
                            AIInterpretedMealItem(name: "Milk", amount: 240, unit: "ml", calories: 110, proteinGrams: 8, carbsGrams: 11, fatGrams: 5, fiberGrams: 0)
                        ],
                        calories: normalized.contains("shake") ? 280 : 430,
                        proteinGrams: normalized.contains("shake") ? 34 : 33,
                        carbsGrams: normalized.contains("shake") ? 24 : 46,
                        fatGrams: normalized.contains("shake") ? 7 : 14,
                        confidence: 0.83,
                        alternatives: []
                    )
                ],
                uiNotes: "Mock AI interpretation. Adjust items before saving."
            )
        }

        if normalized.contains("lunch") || normalized.contains("dinner") || normalized.contains("family") {
            return AIInterpretMealResponse(
                interpretedMeals: [
                    AIInterpretedMeal(
                        label: normalized.contains("family") ? "Family dinner" : "Inferred meal",
                        timing: normalized.contains("dinner") || normalized.contains("family") ? "dinner" : "lunch",
                        eatenAtGuessISO8601: isoFormatter.string(from: now),
                        items: [
                            AIInterpretedMealItem(name: "Chicken breast", amount: 140, unit: "g", calories: 220, proteinGrams: 43, carbsGrams: 0, fatGrams: 4.5, fiberGrams: 0),
                            AIInterpretedMealItem(name: "Rice", amount: 160, unit: "g", calories: 210, proteinGrams: 4, carbsGrams: 45, fatGrams: 0.5, fiberGrams: 1),
                            AIInterpretedMealItem(name: "Vegetables", amount: 110, unit: "g", calories: 80, proteinGrams: 3, carbsGrams: 13, fatGrams: 1, fiberGrams: 4)
                        ],
                        calories: normalized.contains("family") ? 760 : 620,
                        proteinGrams: normalized.contains("family") ? 42 : 36,
                        carbsGrams: normalized.contains("family") ? 71 : 58,
                        fatGrams: normalized.contains("family") ? 31 : 24,
                        confidence: 0.76,
                        alternatives: []
                    )
                ],
                uiNotes: "Mock AI interpretation. Nutrients are approximate."
            )
        }

        return AIInterpretMealResponse(
            interpretedMeals: [defaultMeal],
            uiNotes: "Mock AI interpretation from generic meal template."
        )
    }

    func coach(request: AICoachRequest) async throws -> AICoachResponse {
        try await Task.sleep(nanoseconds: 200_000_000)
        let ask = request.message.lowercased()
        let proteinRemaining: Int? = {
            guard let day = request.context?.dayNutrition,
                  let target = day.proteinTarget
            else { return nil }
            return max(0, Int(target - day.proteinGrams))
        }()

        if ask.contains("diagnos") || ask.contains("chest pain") || ask.contains("suicid") {
            return AICoachResponse(
                assistantText: "I can’t help with medical diagnosis or urgent symptoms. Please contact a clinician or emergency services if you’re in danger.",
                evidence: [],
                confidence: "high",
                limitations: [],
                quickActions: [],
                requiresUserDecision: false,
                safety: AICoachSafety(state: "refuse", reason: "medical_or_urgent")
            )
        }

        if ask.contains("protein") {
            let remainingText = proteinRemaining.map { "\($0)g" } ?? "your remaining target"
            return AICoachResponse(
                assistantText: "Based on today’s confirmed meals, you have about \(remainingText) of protein left toward your goal. A protein-forward dinner (eggs, fish, Greek yogurt, or lean meat with vegetables) would help close the gap.",
                recommendation: AICoachRecommendation(
                    title: "Prioritise protein at dinner",
                    detail: "Aim for a meal that covers most of the remaining protein."
                ),
                evidence: [
                    AICoachEvidenceItem(
                        kind: "day_progress",
                        label: "Today’s protein progress",
                        detail: proteinRemaining.map { "About \($0)g remaining vs target" }
                    ),
                    AICoachEvidenceItem(
                        kind: "goal_target",
                        label: "Active goal targets",
                        detail: request.context?.goal?.title
                    ),
                ].filter { $0.detail != nil || $0.kind == "day_progress" },
                confidence: request.context?.dayNutrition?.proteinTarget == nil ? "low" : "medium",
                limitations: request.context?.dayNutrition?.proteinTarget == nil
                    ? ["No protein target is set yet"]
                    : [],
                quickActions: [
                    AICoachQuickAction(id: "liveTai.why", title: "Why?"),
                    AICoachQuickAction(id: "meal.describeMeal", title: "Describe Meal"),
                ],
                requiresUserDecision: false,
                safety: AICoachSafety(state: "ok", reason: nil)
            )
        }

        let mealCount = request.context?.dayNutrition?.mealCount ?? 0
        return AICoachResponse(
            assistantText: mealCount == 0
                ? "I don’t have confirmed meals for today yet. Tell me what you’ve eaten, or ask about your goals and I’ll coach from what we know."
                : "Here’s my take from today’s confirmed logs: you’ve logged \(mealCount) meal(s). Ask about protein left, dinner ideas, or how today compares — I’ll stay grounded in what you’ve confirmed.",
            evidence: [
                AICoachEvidenceItem(
                    kind: "confirmed_meal",
                    label: "Today’s meal count",
                    detail: "\(mealCount) confirmed meal(s)"
                ),
            ],
            confidence: mealCount == 0 ? "low" : "medium",
            limitations: mealCount == 0 ? ["No confirmed meals logged today"] : [],
            quickActions: [AICoachQuickAction(id: "liveTai.why", title: "Why?")],
            requiresUserDecision: false,
            safety: AICoachSafety(state: "ok", reason: nil)
        )
    }

    func interpretGoal(request: AIInterpretGoalRequest) async throws -> AIInterpretGoalResponse {
        try await Task.sleep(nanoseconds: 250_000_000)
        let trimmed = request.prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalized = trimmed.lowercased()

        let goalType: String
        let title: String
        let calories: Int
        let protein: Double
        let carbs: Double
        let fat: Double

        if normalized.contains("cut") || normalized.contains("lose") || normalized.contains("lean") {
            goalType = "fat_loss"
            title = "Fat loss while keeping strength"
            calories = 1850
            protein = 165
            carbs = 155
            fat = 62
        } else if normalized.contains("maintain") {
            goalType = "maintenance"
            title = "Balanced maintenance"
            calories = 2200
            protein = 150
            carbs = 230
            fat = 75
        } else {
            goalType = "performance"
            title = "Training-focused nutrition"
            calories = 2300
            protein = 160
            carbs = 250
            fat = 72
        }

        return AIInterpretGoalResponse(
            originalPrompt: trimmed,
            goalType: goalType,
            title: title,
            calorieTarget: calories,
            proteinTarget: protein,
            carbsTarget: carbs,
            fatTarget: fat,
            fiberTarget: 28,
            waterTarget: 2600,
            activityIntent: "Mock interpretation: align protein with training days and keep changes gradual.",
            uiNotes: "Mock goal interpretation — connect a real proxy for personalized targets.",
            confidence: 0.72
        )
    }

    func interpretGymPhoto(request: AIInterpretGymPhotoRequest) async throws -> AIInterpretGymPhotoResponse {
        try await Task.sleep(nanoseconds: 250_000_000)
        let expectedID = request.context?.expectedExerciseID ?? GymExerciseID.legPress.rawValue
        let displayName = GymExerciseCatalog.displayName(for: expectedID)
        let unit = request.context?.weightUnitPreference ?? "kg"
        return AIInterpretGymPhotoResponse(
            schemaVersion: 1,
            exerciseCandidates: [
                AIInterpretGymExerciseCandidate(
                    exerciseID: expectedID,
                    confidence: 0.86,
                    reason: "Machine setup matches \(displayName)"
                ),
            ],
            detectedWeight: AIInterpretGymDetectedWeight(
                value: unit == "lb" ? 85 : 39,
                unit: unit,
                confidence: 0.72,
                reason: "Selector pin appears aligned with the labeled plate"
            ),
            limitations: ["Mock interpretation — confirm exercise and weight before saving."],
            requiresConfirmation: true
        )
    }

    func interpretWorkoutPlan(request: AIInterpretWorkoutPlanRequest) async throws -> AIInterpretWorkoutPlanResponse {
        try await Task.sleep(nanoseconds: 300_000_000)
        return MockWorkoutPlanInterpretation.trainerFixtureResponse(for: request)
    }
}

struct MockHealthService: HealthService {
    func requestAuthorization() async throws {
        // Intentionally no-op in scaffold phase.
    }

    func latestDailySummary() async throws -> DailyHealthSummary? {
        DailyHealthSummary(date: .now, caloriesBurned: 0, steps: 0)
    }
}

final class MockMealRepository: MealRepository {
    private var meals: [MealLog]

    init() {
        self.meals = MockSeedData.makeMealLogs()
    }

    func fetchMealLogs(ownerID: String, from startDate: Date, to endDate: Date) async throws -> [MealLog] {
        return meals.filter {
            $0.ownerID == ownerID && $0.eatenAt >= startDate && $0.eatenAt < endDate
        }
    }

    func createMealLog(_ meal: MealLog) async throws {
        if meals.contains(where: { $0.id == meal.id }) {
            throw MealRepositoryError.mealLogAlreadyExists(id: meal.id)
        }
        meals.append(meal)
    }

    func updateMealLog(_ meal: MealLog) async throws {
        guard let index = meals.firstIndex(where: { $0.id == meal.id }) else {
            throw MealRepositoryError.mealLogNotFound(id: meal.id)
        }
        meals[index] = meal
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
        copy.items = source.items.map { Self.cloneMealItem(from: $0) }
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
        copy.items = template.items.map { Self.cloneMealItem(from: $0) }
        return copy
    }

    func deleteMealLog(id: UUID) async throws {
        meals.removeAll { $0.id == id }
    }

    private static func cloneMealItem(from source: MealItem) -> MealItem {
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

final class MockWorkoutRepository: WorkoutRepository {
    private var sessions: [WorkoutSessionLog] = []

    func fetchSessions(ownerID: String, from startDate: Date, to endDate: Date) async throws -> [WorkoutSessionLog] {
        sessions.filter {
            $0.ownerID == ownerID && $0.startedAt >= startDate && $0.startedAt < endDate
        }
    }

    func fetchInProgressSession(ownerID: String) async throws -> WorkoutSessionLog? {
        sessions.first { $0.ownerID == ownerID && $0.status == .inProgress }
    }

    func createSession(_ session: WorkoutSessionLog) async throws {
        if sessions.contains(where: { $0.id == session.id }) {
            throw WorkoutRepositoryError.sessionAlreadyExists(id: session.id)
        }
        if session.status == .inProgress,
           let existing = sessions.first(where: { $0.ownerID == session.ownerID && $0.status == .inProgress }),
           existing.id != session.id
        {
            throw WorkoutRepositoryError.activeSessionAlreadyExists(existingSessionID: existing.id)
        }
        sessions.append(session)
    }

    func updateSession(_ session: WorkoutSessionLog) async throws {
        guard let index = sessions.firstIndex(where: { $0.id == session.id }) else {
            throw WorkoutRepositoryError.sessionNotFound(id: session.id)
        }
        let existingSets = sessions[index].sets
        sessions[index] = session
        if session.sets.isEmpty, !existingSets.isEmpty {
            sessions[index].sets = existingSets
        }
    }

    func appendSet(_ set: WorkoutSetLog, to sessionID: UUID) async throws {
        guard let index = sessions.firstIndex(where: { $0.id == sessionID }) else {
            throw WorkoutRepositoryError.sessionNotFound(id: sessionID)
        }
        set.session = sessions[index]
        sessions[index].sets.append(set)
    }

    func completeSession(id: UUID, completedAt: Date, debriefJSON: Data?) async throws {
        guard let index = sessions.firstIndex(where: { $0.id == id }) else {
            throw WorkoutRepositoryError.sessionNotFound(id: id)
        }
        sessions[index].status = .completed
        sessions[index].completedAt = completedAt
        sessions[index].activeSessionJSON = nil
        sessions[index].debriefJSON = debriefJSON
    }

    func abandonSession(id: UUID) async throws {
        guard let index = sessions.firstIndex(where: { $0.id == id }) else {
            throw WorkoutRepositoryError.sessionNotFound(id: id)
        }
        sessions.remove(at: index)
    }
}

final class MockGymPlanRepository: GymPlanRepository {
    private var customPlans: [UUID: GymPlanDraft] = [:]
    private var starterOverrides: [GymProgramTemplateID: GymPlanDraft] = [:]
    /// Test hook: artificial delay before resolving plans to exercise in-flight start guards.
    var resolvePlanDelayNanoseconds: UInt64 = 0

    func fetchLibrary(ownerID: String) async throws -> GymPlanLibrarySnapshot {
        let summaries = try await fetchSummaries(ownerID: ownerID)
        return GymPlanLibrarySnapshot(
            activePlan: summaries.first { $0.lifecycleStatus == .active },
            previousPlans: summaries.filter { $0.lifecycleStatus != .active },
            hasUserPlans: !summaries.isEmpty
        )
    }

    func fetchTemplateSummaries() -> [GymPlanSummary] {
        GymProgramTemplateID.allCases.map { GymProgramTemplateLibrary.starterSummary(for: $0) }
    }

    func fetchSummaries(ownerID: String) async throws -> [GymPlanSummary] {
        _ = ownerID
        return customPlans.map { id, draft in
            summary(for: .custom(id), draft: draft, isEditedStarter: false)
        }.sorted { ($0.importedAt ?? .distantPast) > ($1.importedAt ?? .distantPast) }
    }

    func resolvePlan(reference: GymPlanReference, sectionIndex: Int, ownerID: String) async throws -> GymResolvablePlan {
        if resolvePlanDelayNanoseconds > 0 {
            try await Task.sleep(nanoseconds: resolvePlanDelayNanoseconds)
        }
        _ = ownerID
        let draft = try await loadDraft(reference: reference, ownerID: ownerID)
        guard draft.sections.indices.contains(sectionIndex) else {
            throw GymPlanRepositoryError.sectionNotFound
        }
        let section = draft.sections.sorted { $0.orderIndex < $1.orderIndex }[sectionIndex]
        return GymResolvablePlan(
            reference: reference,
            title: draft.sections.count > 1 ? "\(draft.title) — \(section.name)" : draft.title,
            sectionName: section.name,
            sectionIndex: sectionIndex,
            exercises: section.exercises,
            prescription: section.prescription ?? draft.prescription,
            generalInstructions: draft.generalInstructions
        )
    }

    func loadDraft(reference: GymPlanReference, ownerID: String) async throws -> GymPlanDraft {
        _ = ownerID
        switch reference {
        case .starter(let templateID):
            if let override = starterOverrides[templateID] {
                return override
            }
            let starter = GymProgramTemplateLibrary.resolvableStarter(templateID)
            return GymPlanDraft(
                reference: reference,
                title: starter.title,
                sections: [
                    GymPlanSectionDraft(
                        name: starter.title,
                        orderIndex: 0,
                        exercises: starter.exercises,
                        prescription: starter.prescription
                    )
                ],
                prescription: starter.prescription,
                generalInstructions: starter.generalInstructions,
                suggestedDurationWeeks: nil,
                lifecycleStatus: .inactive,
                importedAt: nil
            )
        case .custom(let id):
            guard let draft = customPlans[id] else { throw GymPlanRepositoryError.planNotFound }
            return draft
        }
    }

    func saveDraft(_ draft: GymPlanDraft, ownerID: String, activation: GymPlanSaveActivation) async throws -> GymPlanReference {
        _ = ownerID
        guard !draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !draft.exercises.isEmpty else {
            throw GymPlanRepositoryError.invalidDraft
        }
        var saved = draft
        if activation == .makeActive {
            for (id, var plan) in customPlans {
                if plan.lifecycleStatus == .active {
                    plan.lifecycleStatus = .archived
                    customPlans[id] = plan
                }
            }
            saved.lifecycleStatus = .active
        } else if saved.lifecycleStatus != .active {
            saved.lifecycleStatus = .inactive
        }

        if let reference = draft.reference {
            switch reference {
            case .starter(let templateID):
                saved.reference = reference
                starterOverrides[templateID] = saved
                return reference
            case .custom(let id):
                saved.reference = reference
                customPlans[id] = saved
                return reference
            }
        }
        let id = UUID()
        saved.reference = .custom(id)
        if saved.importedAt == nil { saved.importedAt = .now }
        customPlans[id] = saved
        return .custom(id)
    }

    func duplicatePlan(reference: GymPlanReference, ownerID: String) async throws -> GymPlanReference {
        var copy = try await loadDraft(reference: reference, ownerID: ownerID)
        copy.reference = nil
        copy.title = "Copy of \(copy.title)"
        copy.lifecycleStatus = .inactive
        return try await saveDraft(copy, ownerID: ownerID, activation: .saveOnly)
    }

    func deletePlan(reference: GymPlanReference, ownerID: String) async throws {
        _ = ownerID
        switch reference {
        case .starter:
            throw GymPlanRepositoryError.cannotDeleteStarter
        case .custom(let id):
            customPlans.removeValue(forKey: id)
        }
    }

    func archivePlan(reference: GymPlanReference, ownerID: String) async throws {
        _ = ownerID
        guard case .custom(let id) = reference, var draft = customPlans[id] else { return }
        draft.lifecycleStatus = .archived
        customPlans[id] = draft
    }

    func resetStarterPlan(templateID: GymProgramTemplateID, ownerID: String) async throws {
        _ = ownerID
        starterOverrides.removeValue(forKey: templateID)
    }

    private func summary(for reference: GymPlanReference, draft: GymPlanDraft, isEditedStarter: Bool) -> GymPlanSummary {
        GymPlanSummary(
            reference: reference,
            title: draft.title,
            exerciseCount: draft.exercises.count,
            sectionCount: draft.sections.count,
            workingSetsPerExercise: draft.prescription.workingSetsPerExercise,
            repRangeLabel: draft.prescription.repRangeLabel,
            isStarter: reference.isStarter,
            isCustom: !reference.isStarter,
            isEditedStarter: isEditedStarter,
            lifecycleStatus: draft.lifecycleStatus,
            importedAt: draft.importedAt,
            suggestedDurationWeeks: draft.suggestedDurationWeeks,
            sectionNames: draft.sections.map(\.name)
        )
    }
}

final class MockGoalRepository: GoalRepository {
    private var goals: [GoalProfile]
    private var targetsByGoalID: [UUID: DailyTargets]

    init() {
        let seeded = MockSeedData.makeGoalProfileAndTargets()
        self.goals = [seeded.profile]
        self.targetsByGoalID = [seeded.profile.id: seeded.targets]
    }

    func fetchGoalProfiles(ownerID: String) async throws -> [GoalProfile] {
        return goals.filter { $0.ownerID == ownerID }
    }

    func upsertGoalProfile(_ profile: GoalProfile) async throws {
        if let index = goals.firstIndex(where: { $0.id == profile.id }) {
            goals[index] = profile
        } else {
            goals.append(profile)
        }
    }

    func fetchDailyTargets(goalProfileID: UUID) async throws -> DailyTargets? {
        return targetsByGoalID[goalProfileID]
    }

    func saveDailyTargets(_ targets: DailyTargets, goalProfileID: UUID) async throws {
        targetsByGoalID[goalProfileID] = targets
    }
}

final class MockFineTuneCorrectionRepository: FineTuneCorrectionRepository {
    private var corrections: [FineTuneCorrection] = []

    func fetchCorrections(ownerID: String, since: Date?) async throws -> [FineTuneCorrection] {
        let ownerScoped = corrections.filter { $0.ownerID == ownerID }
        guard let since else { return ownerScoped }
        return ownerScoped.filter { $0.createdAt >= since }
    }

    func saveCorrection(_ correction: FineTuneCorrection) async throws {
        corrections.append(correction)
    }
}

final class MockRecurringMealRepository: RecurringMealRepository {
    private var recurringMeals: [RecurringMeal]

    init() {
        self.recurringMeals = MockSeedData.makeRecurringMeals()
    }

    func fetchRecurringMeals(ownerID: String, activeOnly: Bool) async throws -> [RecurringMeal] {
        let ownerScoped = recurringMeals.filter { $0.ownerID == ownerID }
        return activeOnly ? ownerScoped.filter(\.isActive) : ownerScoped
    }

    func upsertRecurringMeal(_ recurringMeal: RecurringMeal) async throws {
        if let index = recurringMeals.firstIndex(where: { $0.id == recurringMeal.id }) {
            recurringMeals[index] = recurringMeal
        } else {
            recurringMeals.append(recurringMeal)
        }
    }
}

final class MockAlcoholPlanRepository: AlcoholPlanRepository {
    private var plansByOwnerID: [String: AlcoholPlan]

    init() {
        let plan = MockSeedData.makeAlcoholPlan()
        self.plansByOwnerID = [plan.ownerID: plan]
    }

    func fetchAlcoholPlan(ownerID: String) async throws -> AlcoholPlan? {
        return plansByOwnerID[ownerID]
    }

    func saveAlcoholPlan(_ plan: AlcoholPlan) async throws {
        plansByOwnerID[plan.ownerID] = plan
    }
}

final class MockWeightLogRepository: WeightLogRepository {
    private var logs: [WeightLog] = []

    func fetchWeightLogs(ownerID: String, limit: Int?) async throws -> [WeightLog] {
        let ownerScoped = logs.filter { $0.ownerID == ownerID }.sorted { $0.loggedAt > $1.loggedAt }
        guard let limit else { return ownerScoped }
        return Array(ownerScoped.prefix(limit))
    }

    func saveWeightLog(_ log: WeightLog) async throws {
        logs.append(log)
    }
}

final class MockAppConfigRepository: AppConfigRepository {
    private var configsByOwnerID: [String: AppConfig] = [:]

    func fetchAppConfig(ownerID: String) async throws -> AppConfig? {
        return configsByOwnerID[ownerID]
    }

    func saveAppConfig(_ config: AppConfig) async throws {
        configsByOwnerID[config.ownerID] = config
    }
}

private enum MockSeedData {
    static let ownerID = "preview.user"

    static func makeGoalProfileAndTargets() -> (profile: GoalProfile, targets: DailyTargets) {
        let targets = DailyTargets(
            calories: 2100,
            proteinGrams: 150,
            carbsGrams: 210,
            fatGrams: 70,
            fiberGrams: 30,
            waterMilliliters: 2600
        )
        let profile = GoalProfile(
            ownerID: ownerID,
            title: "Lean maintenance",
            notes: "Default seeded profile for dashboard-first flow."
        )
        profile.dailyTargets = targets
        return (profile, targets)
    }

    static func makeMealLogs() -> [MealLog] {
        let breakfast = MealLog(
            ownerID: ownerID,
            eatenAt: Calendar.current.date(byAdding: .hour, value: -4, to: .now) ?? .now,
            timing: .breakfast,
            notes: "High-protein breakfast."
        )
        breakfast.items = [
            MealItem(
                name: "Greek yogurt",
                amount: 220,
                unit: "g",
                calories: 210,
                proteinGrams: 22,
                carbsGrams: 10,
                fatGrams: 9,
                fiberGrams: 0
            ),
            MealItem(
                name: "Banana",
                amount: 1,
                unit: "item",
                calories: 110,
                proteinGrams: 1,
                carbsGrams: 28,
                fatGrams: 0,
                fiberGrams: 3
            )
        ]

        let lunch = MealLog(
            ownerID: ownerID,
            eatenAt: Calendar.current.date(byAdding: .hour, value: -1, to: .now) ?? .now,
            timing: .lunch,
            notes: "Lunch before meetings.",
            alcoholStandardDrinks: 1
        )
        lunch.items = [
            MealItem(
                name: "Chicken bowl",
                amount: 1,
                unit: "serving",
                calories: 610,
                proteinGrams: 44,
                carbsGrams: 54,
                fatGrams: 20,
                fiberGrams: 7
            ),
            MealItem(
                name: "Red wine",
                amount: 150,
                unit: "ml",
                calories: 120,
                proteinGrams: 0,
                carbsGrams: 4,
                fatGrams: 0,
                fiberGrams: 0,
                alcoholGrams: 14
            )
        ]
        return [breakfast, lunch]
    }

    static func makeRecurringMeals() -> [RecurringMeal] {
        let breakfast = RecurringMeal(
            ownerID: ownerID,
            name: "Weekday protein breakfast",
            cadenceDays: 1,
            preferredTiming: .breakfast
        )
        let dinner = RecurringMeal(
            ownerID: ownerID,
            name: "Fast high-fiber dinner bowl",
            cadenceDays: 2,
            preferredTiming: .dinner
        )
        let snack = RecurringMeal(
            ownerID: ownerID,
            name: "Post-lift snack",
            cadenceDays: 1,
            preferredTiming: .snack
        )
        return [breakfast, dinner, snack]
    }

    static func makeAlcoholPlan() -> AlcoholPlan {
        AlcoholPlan(
            ownerID: ownerID,
            maxStandardDrinksPerDay: 2,
            maxStandardDrinksPerWeek: 8,
            alcoholFreeDaysTarget: 3
        )
    }
}
