import Foundation

enum WorkoutRepositoryError: Error, Equatable {
    case sessionNotFound(id: UUID)
    case sessionAlreadyExists(id: UUID)
    case nothingToSave
    case invalidSet
}

protocol WorkoutRepository {
    func fetchSessions(ownerID: String, from startDate: Date, to endDate: Date) async throws -> [WorkoutSessionLog]

    func fetchInProgressSession(ownerID: String) async throws -> WorkoutSessionLog?

    func createSession(_ session: WorkoutSessionLog) async throws

    func updateSession(_ session: WorkoutSessionLog) async throws

    func appendSet(_ set: WorkoutSetLog, to sessionID: UUID) async throws

    func completeSession(id: UUID, completedAt: Date) async throws

    /// Removes an in-progress session without marking it completed.
    func abandonSession(id: UUID) async throws
}
