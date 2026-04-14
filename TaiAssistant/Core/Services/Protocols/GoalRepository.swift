import Foundation

protocol GoalRepository {
    func fetchGoalProfiles(ownerID: String) async throws -> [GoalProfile]
    func upsertGoalProfile(_ profile: GoalProfile) async throws
    func fetchDailyTargets(goalProfileID: UUID) async throws -> DailyTargets?
    func saveDailyTargets(_ targets: DailyTargets, goalProfileID: UUID) async throws
}
