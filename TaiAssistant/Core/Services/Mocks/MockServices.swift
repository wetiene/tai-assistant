import Foundation

struct MockAIService: AIService {
    func send(message: String, context: [String: String]) async throws -> String {
        "Mock response from Tai: \(message)"
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

actor MockMealRepository: MealRepository {
    private var meals: [MealRecord] = []

    func fetchMeals(for date: Date) async throws -> [MealRecord] {
        meals.filter { Calendar.current.isDate($0.date, inSameDayAs: date) }
    }

    func saveMeal(summary: String, date: Date) async throws {
        meals.append(MealRecord(summary: summary, date: date))
    }
}

actor MockGoalRepository: GoalRepository {
    private var goals: [GoalRecord] = []

    func fetchGoals() async throws -> [GoalRecord] {
        goals
    }

    func saveGoal(title: String, targetValue: Double) async throws {
        goals.append(GoalRecord(title: title, targetValue: targetValue))
    }
}
