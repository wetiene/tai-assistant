import Foundation

/// Assembles a typed `/ai/coach` request from an immutable Sendable snapshot.
/// Isolated off the MainActor — never receives SwiftData models or Observable state.
actor LiveTaiContextAssembler {
    func assemble(snapshot: LiveTaiContextSnapshot) -> AICoachRequest {
        let meals = snapshot.mealsToday.prefix(LiveTaiContextLimits.maxMealsToday).map { meal in
            AICoachMealContext(
                label: meal.label,
                eatenAtISO8601: ISO8601DateFormatter().string(from: meal.eatenAt),
                calories: meal.calories,
                proteinGrams: meal.proteinGrams,
                carbsGrams: meal.carbsGrams,
                fatGrams: meal.fatGrams
            )
        }

        let turns = snapshot.recentTurns.prefix(LiveTaiContextLimits.maxRecentTurns).map { turn in
            AICoachTurnContext(
                role: turn.role.rawValue,
                text: String(turn.text.prefix(LiveTaiContextLimits.maxTurnCharacters))
            )
        }

        let goal = snapshot.goal.map {
            AICoachGoalContext(
                title: $0.title,
                calorieTarget: $0.calorieTarget,
                proteinTarget: $0.proteinTarget,
                carbsTarget: $0.carbsTarget,
                fatTarget: $0.fatTarget
            )
        }

        let day = snapshot.dayNutrition
        let context = AICoachRequestContext(
            localeIdentifier: snapshot.localeIdentifier,
            timeZoneIdentifier: snapshot.timeZoneIdentifier,
            dayNutrition: AICoachDayNutritionContext(
                mealCount: day.mealCount,
                calories: day.calories,
                proteinGrams: day.proteinGrams,
                carbsGrams: day.carbsGrams,
                fatGrams: day.fatGrams,
                calorieTarget: day.calorieTarget,
                proteinTarget: day.proteinTarget,
                carbsTarget: day.carbsTarget,
                fatTarget: day.fatTarget
            ),
            mealsToday: Array(meals),
            goal: goal,
            recentTurns: Array(turns),
            limitations: snapshot.knownLimitations,
            capabilityFlags: AICoachCapabilityFlags(
                hasHealthKit: snapshot.capabilityFlags.hasHealthKit,
                hasWorkouts: snapshot.capabilityFlags.hasWorkouts,
                hasLocation: snapshot.capabilityFlags.hasLocation,
                hasMealMemory: snapshot.capabilityFlags.hasMealMemory
            )
        )

        return AICoachRequest(message: snapshot.userAsk, context: context)
    }
}

/// Captures value-type context on the MainActor / repository boundary.
enum LiveTaiContextSnapshotBuilder {
    @MainActor
    static func capture(
        userAsk: String,
        messages: [ConversationMessage],
        mealsToday: [LiveTaiMealSnapshot],
        goal: LiveTaiGoalSnapshot?,
        dayNutrition: LiveTaiDayNutritionSnapshot,
        now: Date = .now,
        locale: Locale = .current,
        timeZone: TimeZone = .current
    ) -> LiveTaiContextSnapshot {
        let turns = messages.reversed().compactMap { message -> LiveTaiTurnSnippet? in
            guard let text = message.text?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !text.isEmpty
            else { return nil }
            let role: LiveTaiTurnSnippet.Role
            switch message.actor {
            case .user: role = .user
            case .assistant: role = .assistant
            case .system: return nil
            }
            return LiveTaiTurnSnippet(
                role: role,
                text: String(text.prefix(LiveTaiContextLimits.maxTurnCharacters))
            )
        }
        .prefix(LiveTaiContextLimits.maxRecentTurns)
        .reversed()

        return LiveTaiContextSnapshot(
            capturedAt: now,
            localeIdentifier: locale.identifier,
            timeZoneIdentifier: timeZone.identifier,
            userAsk: userAsk,
            recentTurns: Array(turns),
            dayNutrition: dayNutrition,
            mealsToday: Array(mealsToday.prefix(LiveTaiContextLimits.maxMealsToday)),
            goal: goal,
            capabilityFlags: .p0Defaults,
            knownLimitations: LiveTaiKnownLimitations.defaults
        )
    }

    /// Extract Sendable meal values from confirmed MealLog Artifacts (call on MainActor).
    @MainActor
    static func mealSnapshots(from logs: [MealLog]) -> [LiveTaiMealSnapshot] {
        logs.map { log in
            let items = log.items
            return LiveTaiMealSnapshot(
                label: log.notes.isEmpty ? "Meal" : log.notes,
                eatenAt: log.eatenAt,
                calories: items.reduce(0) { $0 + $1.calories },
                proteinGrams: items.reduce(0) { $0 + $1.proteinGrams },
                carbsGrams: items.reduce(0) { $0 + $1.carbsGrams },
                fatGrams: items.reduce(0) { $0 + $1.fatGrams }
            )
        }
    }

    @MainActor
    static func goalSnapshot(profile: GoalProfile?, targets: DailyTargets?) -> LiveTaiGoalSnapshot? {
        guard let profile else { return nil }
        return LiveTaiGoalSnapshot(
            title: profile.title,
            calorieTarget: targets?.calories ?? 0,
            proteinTarget: targets?.proteinGrams ?? 0,
            carbsTarget: targets?.carbsGrams ?? 0,
            fatTarget: targets?.fatGrams ?? 0
        )
    }

    @MainActor
    static func dayNutrition(
        meals: [LiveTaiMealSnapshot],
        goal: LiveTaiGoalSnapshot?
    ) -> LiveTaiDayNutritionSnapshot {
        LiveTaiDayNutritionSnapshot(
            mealCount: meals.count,
            calories: meals.reduce(0) { $0 + $1.calories },
            proteinGrams: meals.reduce(0) { $0 + $1.proteinGrams },
            carbsGrams: meals.reduce(0) { $0 + $1.carbsGrams },
            fatGrams: meals.reduce(0) { $0 + $1.fatGrams },
            calorieTarget: goal.map(\.calorieTarget),
            proteinTarget: goal.map(\.proteinTarget),
            carbsTarget: goal.map(\.carbsTarget),
            fatTarget: goal.map(\.fatTarget)
        )
    }
}
