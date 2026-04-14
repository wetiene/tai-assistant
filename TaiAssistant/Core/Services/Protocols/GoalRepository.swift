import Foundation

protocol GoalRepository {
    func fetchGoals() async throws -> [GoalRecord]
    func saveGoal(title: String, targetValue: Double) async throws
}
