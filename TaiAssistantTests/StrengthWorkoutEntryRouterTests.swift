import XCTest
@testable import TaiAssistant

@MainActor
final class StrengthWorkoutEntryRouterTests: XCTestCase {
    private let ownerID = "strength.entry.router"

    private func makeRouter(
        workoutRepository: WorkoutRepository = MockWorkoutRepository(),
        gymPlanRepository: GymPlanRepository = MockGymPlanRepository(),
        onPresent: @escaping (StrengthWorkoutPresentation) -> Void = { _ in }
    ) -> (StrengthWorkoutEntryRouter, MockWorkoutRepository) {
        let repository = workoutRepository as? MockWorkoutRepository ?? MockWorkoutRepository()
        let coordinator = StrengthWorkoutCoordinator(
            workoutRepository: repository,
            gymPlanRepository: gymPlanRepository,
            ownerID: ownerID
        )
        let router = StrengthWorkoutEntryRouter(
            coordinator: coordinator,
            gymPlanRepository: gymPlanRepository,
            ownerID: ownerID,
            onPresentWorkout: onPresent
        )
        return (router, repository)
    }

    private func seedActiveUpperBody(in repository: MockWorkoutRepository) async throws -> StrengthWorkoutSession {
        let session = StrengthSessionBuilder.makeSession(
            plan: GymProgramTemplateLibrary.resolvableStarter(.upperBody),
            proposals: [],
            acceptedProposals: [:],
            historySessions: [],
            preFlightCompleted: true
        )
        try await repository.createSession(
            WorkoutSessionLog(
                id: session.sessionID,
                ownerID: ownerID,
                templateID: session.planReference.storageKey,
                title: session.title,
                statusRaw: GymWorkoutSessionStatus.inProgress.rawValue,
                activeSessionJSON: try StrengthSessionPersistence.encode(session)
            )
        )
        return session
    }

    func testHomeStartWhileStrengthSessionActivePresentsConflict() async throws {
        let (router, repository) = makeRouter()
        _ = try await seedActiveUpperBody(in: repository)

        await router.requestStart(
            target: GymPlanWorkoutTarget(reference: .starter(.lowerBody), sectionIndex: 0),
            source: .home
        )

        XCTAssertNotNil(router.pendingConflict)
        XCTAssertTrue(router.isConflictDialogPresented)
        XCTAssertEqual(router.pendingConflict?.requestedPlanReference, .starter(.lowerBody))
        XCTAssertEqual(router.pendingConflict?.entrySource, .home)
    }

    func testGymPlansStartWhileStrengthSessionActivePresentsConflict() async throws {
        let (router, repository) = makeRouter()
        _ = try await seedActiveUpperBody(in: repository)

        await router.requestStart(
            target: GymPlanWorkoutTarget(reference: .starter(.lowerBody), sectionIndex: 0),
            source: .gymPlans
        )

        XCTAssertEqual(router.pendingConflict?.entrySource, .gymPlans)
    }

    func testConversationStartWhileStrengthSessionActivePresentsConflict() async throws {
        let (router, repository) = makeRouter()
        _ = try await seedActiveUpperBody(in: repository)

        await router.requestStart(
            target: GymPlanWorkoutTarget(reference: .starter(.lowerBody), sectionIndex: 0),
            source: .conversation
        )

        XCTAssertEqual(router.pendingConflict?.entrySource, .conversation)
    }

    func testResumeOpensExistingStrengthSession() async throws {
        let repository = MockWorkoutRepository()
        var presented: StrengthWorkoutPresentation?
        let wired = StrengthWorkoutEntryRouter(
            coordinator: StrengthWorkoutCoordinator(
                workoutRepository: repository,
                gymPlanRepository: MockGymPlanRepository(),
                ownerID: ownerID
            ),
            gymPlanRepository: MockGymPlanRepository(),
            ownerID: ownerID,
            onPresentWorkout: { presented = $0 }
        )
        let session = try await seedActiveUpperBody(in: repository)

        await wired.requestResume(source: .home)

        XCTAssertEqual(presented?.resumeSession?.sessionID, session.sessionID)
    }

    func testCancelPreservesActiveSession() async throws {
        let (router, repository) = makeRouter()
        let session = try await seedActiveUpperBody(in: repository)

        await router.requestStart(
            target: GymPlanWorkoutTarget(reference: .starter(.lowerBody), sectionIndex: 0),
            source: .home
        )
        router.cancelConflict()

        XCTAssertNil(router.pendingConflict)
        let active = try await repository.fetchInProgressSession(ownerID: ownerID)
        XCTAssertEqual(active?.id, session.sessionID)
    }

    func testAbandonThenStartPresentsNewWorkout() async throws {
        let repository = MockWorkoutRepository()
        var presented: StrengthWorkoutPresentation?
        let wired = StrengthWorkoutEntryRouter(
            coordinator: StrengthWorkoutCoordinator(
                workoutRepository: repository,
                gymPlanRepository: MockGymPlanRepository(),
                ownerID: ownerID
            ),
            gymPlanRepository: MockGymPlanRepository(),
            ownerID: ownerID,
            onPresentWorkout: { presented = $0 }
        )
        _ = try await seedActiveUpperBody(in: repository)

        await wired.requestStart(
            target: GymPlanWorkoutTarget(reference: .starter(.lowerBody), sectionIndex: 0),
            source: .home
        )
        await wired.resolveConflict(.discardCurrentAndStartSelected)

        XCTAssertNil(wired.pendingConflict)
        XCTAssertEqual(presented?.plan.reference, .starter(.lowerBody))
        XCTAssertNil(presented?.resumeSession)
        let inProgress = try await repository.fetchInProgressSession(ownerID: ownerID)
        XCTAssertNil(inProgress)
    }

    func testFinishThenStartLeavesNoActiveSessionUntilFlowStarts() async throws {
        let repository = MockWorkoutRepository()
        var presented: StrengthWorkoutPresentation?
        let wired = StrengthWorkoutEntryRouter(
            coordinator: StrengthWorkoutCoordinator(
                workoutRepository: repository,
                gymPlanRepository: MockGymPlanRepository(),
                ownerID: ownerID
            ),
            gymPlanRepository: MockGymPlanRepository(),
            ownerID: ownerID,
            onPresentWorkout: { presented = $0 }
        )
        let upper = try await seedActiveUpperBody(in: repository)

        await wired.requestStart(
            target: GymPlanWorkoutTarget(reference: .starter(.lowerBody), sectionIndex: 0),
            source: .home
        )
        await wired.resolveConflict(.finishCurrentAndStartSelected)

        XCTAssertEqual(presented?.plan.reference, .starter(.lowerBody))
        let inProgress = try await repository.fetchInProgressSession(ownerID: ownerID)
        XCTAssertNil(inProgress)
        let completed = try await repository.fetchSessions(
            ownerID: ownerID,
            from: .distantPast,
            to: .distantFuture
        ).first { $0.id == upper.sessionID }
        XCTAssertEqual(completed?.status, .completed)
    }

    func testPendingRequestedWorkoutRetainedUntilResolution() async throws {
        let (router, repository) = makeRouter()
        _ = try await seedActiveUpperBody(in: repository)

        await router.requestStart(
            target: GymPlanWorkoutTarget(reference: .starter(.lowerBody), sectionIndex: 0),
            source: .home
        )
        router.requestAbandonConfirmation()

        XCTAssertEqual(router.pendingConflict?.requestedWorkoutTarget.sectionIndex, 0)
        XCTAssertTrue(router.isAbandonConfirmationPresented)
        XCTAssertFalse(router.isConflictDialogPresented)
    }

    func testLegacyActiveSessionConflictIsRecoverable() async throws {
        let repository = MockWorkoutRepository()
        let legacy = GymActiveSession(
            sessionID: UUID(),
            planReference: .starter(.upperBody),
            title: "Upper Body",
            exercises: GymProgramTemplateLibrary.upperBody.exercises,
            prescription: .default,
            currentExerciseIndex: 0,
            currentSetNumber: 1,
            startedAt: .now,
            status: .inProgress
        )
        try await repository.createSession(
            WorkoutSessionLog(
                id: legacy.sessionID,
                ownerID: ownerID,
                templateID: legacy.planReference.storageKey,
                title: legacy.title,
                statusRaw: GymWorkoutSessionStatus.inProgress.rawValue,
                activeSessionJSON: try StrengthSessionPersistence.encodeLegacy(legacy)
            )
        )

        let (router, _) = makeRouter(workoutRepository: repository)
        await router.requestStart(
            target: GymPlanWorkoutTarget(reference: .starter(.lowerBody), sectionIndex: 0),
            source: .conversation
        )

        XCTAssertNotNil(router.pendingConflict)
        XCTAssertNotNil(router.pendingConflict?.activeProgressSummary)
    }

    func testLaunchIntentStartWhileStrengthSessionActivePresentsConflict() async throws {
        let repository = MockWorkoutRepository()
        let gymPlanRepo = MockGymPlanRepository()
        let coordinator = StrengthWorkoutCoordinator(
            workoutRepository: repository,
            gymPlanRepository: gymPlanRepo,
            ownerID: ownerID
        )
        let router = StrengthWorkoutEntryRouter(
            coordinator: coordinator,
            gymPlanRepository: gymPlanRepo,
            ownerID: ownerID,
            onPresentWorkout: { _ in }
        )
        _ = try await seedActiveUpperBody(in: repository)

        await router.requestStart(
            target: GymPlanWorkoutTarget(reference: .starter(.lowerBody), sectionIndex: 0),
            source: .home
        )

        XCTAssertNotNil(router.pendingConflict)
        XCTAssertEqual(router.pendingConflict?.entrySource, .home)
    }

    func testCancelClearsPendingRequestedWorkout() async throws {
        let (router, repository) = makeRouter()
        _ = try await seedActiveUpperBody(in: repository)

        await router.requestStart(
            target: GymPlanWorkoutTarget(reference: .starter(.lowerBody), sectionIndex: 0),
            source: .gymPlans
        )
        router.cancelConflict()

        XCTAssertNil(router.pendingConflict)
        XCTAssertFalse(router.isConflictDialogPresented)
    }

    func testRepeatedConflictActionsCannotCreateDuplicateSessions() async throws {
        let repository = MockWorkoutRepository()
        var presented: [StrengthWorkoutPresentation] = []
        let router = StrengthWorkoutEntryRouter(
            coordinator: StrengthWorkoutCoordinator(
                workoutRepository: repository,
                gymPlanRepository: MockGymPlanRepository(),
                ownerID: ownerID
            ),
            gymPlanRepository: MockGymPlanRepository(),
            ownerID: ownerID,
            onPresentWorkout: { presented.append($0) }
        )
        _ = try await seedActiveUpperBody(in: repository)

        await router.requestStart(
            target: GymPlanWorkoutTarget(reference: .starter(.lowerBody), sectionIndex: 0),
            source: .home
        )
        await router.resolveConflict(.discardCurrentAndStartSelected)
        await router.resolveConflict(.discardCurrentAndStartSelected)

        XCTAssertEqual(presented.count, 1)
        let activeCount = try await repository.fetchSessions(
            ownerID: ownerID,
            from: .distantPast,
            to: .distantFuture
        ).filter { $0.status == .inProgress }.count
        XCTAssertEqual(activeCount, 0)
    }

    func testDuplicateStartRequestsAreIgnoredWhileInFlight() async {
        let repo = MockGymPlanRepository()
        repo.resolvePlanDelayNanoseconds = 200_000_000
        var presented: StrengthWorkoutPresentation?
        let router = StrengthWorkoutEntryRouter(
            coordinator: StrengthWorkoutCoordinator(
                workoutRepository: MockWorkoutRepository(),
                gymPlanRepository: repo,
                ownerID: ownerID
            ),
            gymPlanRepository: repo,
            ownerID: ownerID,
            onPresentWorkout: { presented = $0 }
        )

        async let first: Void = router.requestStart(
            target: GymPlanWorkoutTarget(reference: .starter(.upperBody), sectionIndex: 0),
            source: .home
        )
        async let second: Void = router.requestStart(
            target: GymPlanWorkoutTarget(reference: .starter(.lowerBody), sectionIndex: 0),
            source: .home
        )
        _ = await (first, second)
        try? await Task.sleep(nanoseconds: 450_000_000)

        XCTAssertEqual(presented?.plan.reference, .starter(.upperBody))
    }

    func testAbandonClearsActiveSessionBeforePresentingNewWorkout() async throws {
        let (router, repository) = makeRouter()
        _ = try await seedActiveUpperBody(in: repository)

        await router.requestStart(
            target: GymPlanWorkoutTarget(reference: .starter(.lowerBody), sectionIndex: 0),
            source: .home
        )
        await router.resolveConflict(.discardCurrentAndStartSelected)

        let activeCount = try await repository.fetchSessions(
            ownerID: ownerID,
            from: .distantPast,
            to: .distantFuture
        ).filter { $0.status == .inProgress }.count
        XCTAssertEqual(activeCount, 0)
    }
}
