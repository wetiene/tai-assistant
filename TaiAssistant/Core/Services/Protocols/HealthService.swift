import Foundation

struct DailyHealthSummary: Sendable {
    let date: Date
    let caloriesBurned: Double
    let steps: Int
}

protocol HealthService {
    func requestAuthorization() async throws
    func latestDailySummary() async throws -> DailyHealthSummary?
}
