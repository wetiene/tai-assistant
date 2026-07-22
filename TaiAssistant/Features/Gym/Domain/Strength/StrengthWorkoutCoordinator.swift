import Foundation

struct StrengthWorkoutStartRequest: Equatable, Sendable {
    var target: GymPlanWorkoutTarget
    var source: StrengthWorkoutEntrySource
    var skipPreFlight: Bool
}

struct StrengthWorkoutPresentation: Equatable, Sendable, Identifiable {
    let id: UUID
    var plan: GymResolvablePlan
    var proposals: [StrengthProgressionProposal]
    var historySessions: [WorkoutSessionLog]
    var resumeSession: StrengthWorkoutSession?
    var source: StrengthWorkoutEntrySource
    var sessionID: UUID?

    static func start(
        plan: GymResolvablePlan,
        proposals: [StrengthProgressionProposal],
        historySessions: [WorkoutSessionLog],
        source: StrengthWorkoutEntrySource
    ) -> StrengthWorkoutPresentation {
        StrengthWorkoutPresentation(
            id: UUID(),
            plan: plan,
            proposals: proposals,
            historySessions: historySessions,
            resumeSession: nil,
            source: source,
            sessionID: nil
        )
    }

    static func resume(
        session: StrengthWorkoutSession,
        plan: GymResolvablePlan,
        proposals: [StrengthProgressionProposal],
        historySessions: [WorkoutSessionLog],
        source: StrengthWorkoutEntrySource
    ) -> StrengthWorkoutPresentation {
        StrengthWorkoutPresentation(
            id: UUID(),
            plan: plan,
            proposals: proposals,
            historySessions: historySessions,
            resumeSession: session,
            source: source,
            sessionID: session.sessionID
        )
    }
}

struct StrengthActiveWorkoutContext: Equatable, Sendable {
    var sessionID: UUID
    var title: String
    var planReference: GymPlanReference
    var isStrengthSession: Bool
    var strengthSession: StrengthWorkoutSession?
    var legacySession: GymActiveSession?

    var matchesTarget: (GymPlanWorkoutTarget) -> Bool {
        { $0.reference == planReference }
    }
}

enum StrengthWorkoutCoordinatorError: Error, Equatable {
    case planResolutionFailed
    case activeSessionInProgress(sessionID: UUID)
}

/// Canonical entry point for structured strength workout lifecycle.
@MainActor
struct StrengthWorkoutCoordinator {
    let workoutRepository: WorkoutRepository
    let gymPlanRepository: GymPlanRepository
    let ownerID: String

    // MARK: - Detection

    func fetchActiveWorkout() async throws -> StrengthActiveWorkoutContext? {
        guard let log = try await workoutRepository.fetchInProgressSession(ownerID: ownerID) else {
            return nil
        }
        if let strength = StrengthSessionPersistence.decodeStrength(from: log.activeSessionJSON) {
            return StrengthActiveWorkoutContext(
                sessionID: strength.sessionID,
                title: strength.title,
                planReference: strength.planReference,
                isStrengthSession: true,
                strengthSession: strength,
                legacySession: nil
            )
        }
        if let legacy = StrengthSessionPersistence.decodeLegacyGymActive(from: log.activeSessionJSON) {
            return StrengthActiveWorkoutContext(
                sessionID: legacy.sessionID,
                title: legacy.title,
                planReference: legacy.planReference,
                isStrengthSession: false,
                strengthSession: nil,
                legacySession: legacy
            )
        }
        return nil
    }

    func detectStartConflict(
        requestedTarget: GymPlanWorkoutTarget,
        requestedTitle: String,
        entrySource: StrengthWorkoutEntrySource
    ) async throws -> GymWorkoutStartConflict? {
        guard let active = try await fetchActiveWorkout() else { return nil }
        if active.planReference == requestedTarget.reference {
            return nil
        }
        let progress = Self.progressFields(for: active)
        return GymWorkoutStartConflict(
            activeSessionTitle: active.title,
            activePlanReference: active.planReference,
            requestedPlanReference: requestedTarget.reference,
            requestedPlanTitle: requestedTitle,
            requestedWorkoutTarget: requestedTarget,
            entrySource: entrySource,
            activeProgressSummary: progress.summary,
            activeCompletedSets: progress.completedSets,
            activeTotalSets: progress.totalSets
        )
    }

    // MARK: - Launch

    func buildStartPresentation(
        request: StrengthWorkoutStartRequest
    ) async throws -> StrengthWorkoutPresentation {
        let plan = try await gymPlanRepository.resolvePlan(
            reference: request.target.reference,
            sectionIndex: request.target.sectionIndex,
            ownerID: ownerID
        )
        let history = try await fetchHistory()
        let proposals = StrengthSessionBuilder.proposals(for: plan, historySessions: history)
        return .start(plan: plan, proposals: proposals, historySessions: history, source: request.source)
    }

    func buildResumePresentation(
        source: StrengthWorkoutEntrySource
    ) async throws -> StrengthWorkoutPresentation? {
        guard let active = try await fetchActiveWorkout() else { return nil }

        if let strength = active.strengthSession {
            let plan = try await resolvePlan(for: strength)
            let history = try await fetchHistory()
            let proposals = strength.preFlightProposals
                ?? StrengthSessionBuilder.proposals(for: plan, historySessions: history)
            return .resume(
                session: strength,
                plan: plan,
                proposals: proposals,
                historySessions: history,
                source: source
            )
        }

        if let legacy = active.legacySession {
            let migrated = StrengthSessionPersistence.migrateLegacySession(legacy)
            let plan = try await resolvePlan(for: migrated)
            let history = try await fetchHistory()
            let proposals = StrengthSessionBuilder.proposals(for: plan, historySessions: history)
            return .resume(
                session: migrated,
                plan: plan,
                proposals: proposals,
                historySessions: history,
                source: source
            )
        }

        return nil
    }

    // MARK: - Lifecycle mutations

    func abandonActiveWorkout() async throws {
        guard let active = try await fetchActiveWorkout() else { return }
        try await workoutRepository.abandonSession(id: active.sessionID)
    }

    func finishActiveWorkout() async throws {
        guard let active = try await fetchActiveWorkout() else { return }
        if let strength = active.strengthSession {
            let controller = StrengthWorkoutController(workoutRepository: workoutRepository, ownerID: ownerID)
            controller.loadSession(strength)
            _ = try await controller.finishWorkout()
            return
        }
        if let legacy = active.legacySession {
            try await workoutRepository.completeSession(
                id: legacy.sessionID,
                completedAt: .now,
                debriefJSON: nil
            )
        }
    }

    // MARK: - Helpers

    func fetchHistory() async throws -> [WorkoutSessionLog] {
        let from = Calendar.current.date(byAdding: .year, value: -1, to: .now) ?? .distantPast
        return try await workoutRepository.fetchSessions(
            ownerID: ownerID,
            from: from,
            to: .now.addingTimeInterval(86400)
        )
    }

    private func resolvePlan(for session: StrengthWorkoutSession) async throws -> GymResolvablePlan {
        try await gymPlanRepository.resolvePlan(
            reference: session.planReference,
            sectionIndex: session.sectionIndex,
            ownerID: ownerID
        )
    }

    private static func progressFields(
        for active: StrengthActiveWorkoutContext
    ) -> (summary: String?, completedSets: Int?, totalSets: Int?) {
        if let strength = active.strengthSession {
            let completed = strength.completedWorkingSetCount
            let total = strength.totalPlannedWorkingSets
            let duration = formatElapsed(strength.elapsedActiveSeconds)
            return ("\(completed)/\(total) sets · \(duration)", completed, total)
        }
        if let legacy = active.legacySession {
            let position = min(legacy.currentExerciseIndex + 1, legacy.exercises.count)
            return ("Exercise \(position) of \(legacy.exercises.count)", nil, nil)
        }
        return (nil, nil, nil)
    }

    private static func formatElapsed(_ seconds: TimeInterval) -> String {
        let minutes = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", minutes, secs)
    }
}
