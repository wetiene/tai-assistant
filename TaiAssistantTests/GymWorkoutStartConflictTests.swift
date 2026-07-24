import XCTest
@testable import TaiAssistant

/// Conversational strength workout conflict integration tests.
/// Primary starts route through `ConversationViewModel.beginConversationalStrengthWorkout`;
/// conflict state lives on the view model. `StrengthWorkoutEntryRouter` remains for dedicated fallback only.
@MainActor
final class GymWorkoutStartConflictTests: XCTestCase {
    private let ownerID = "gym.conflict.shell"

    override func setUp() {
        super.setUp()
        AIDataProcessingConsentStore.resetForTests()
        AIDataProcessingConsentStore.accept(version: AIDataProcessingConsentStore.gymPhotoVersion)
    }

    override func tearDown() {
        AIDataProcessingConsentStore.resetForTests()
        super.tearDown()
    }

    // MARK: - Harness

    private final class PresentationCapture {
        var value: StrengthWorkoutPresentation?
    }

    private struct ShellRoutedContext {
        let viewModel: ConversationViewModel
        let router: StrengthWorkoutEntryRouter
        let repository: WorkoutRepository
        let presentation: PresentationCapture
    }

    private func makeShellRoutedContext(
        workoutRepository: WorkoutRepository = MockWorkoutRepository(),
        gymPlanRepository: GymPlanRepository = MockGymPlanRepository()
    ) -> ShellRoutedContext {
        let coordinator = StrengthWorkoutCoordinator(
            workoutRepository: workoutRepository,
            gymPlanRepository: gymPlanRepository,
            ownerID: ownerID
        )
        let presentation = PresentationCapture()
        let router = StrengthWorkoutEntryRouter(
            coordinator: coordinator,
            gymPlanRepository: gymPlanRepository,
            ownerID: ownerID,
            onPresentWorkout: { presentation.value = $0 }
        )
        let store = ConversationSessionStore()
        let (vm, _) = ConversationTestSupport.makeViewModel(
            store: store,
            workoutRepository: workoutRepository,
            gymPlanRepository: gymPlanRepository,
            ownerID: ownerID
        )
        vm.strengthWorkoutCoordinator = coordinator
        vm.onPresentStrengthWorkout = { presentation.value = $0 }
        return ShellRoutedContext(
            viewModel: vm,
            router: router,
            repository: workoutRepository,
            presentation: presentation
        )
    }

    private func seedActiveUpperBody(in repository: WorkoutRepository) async throws -> StrengthWorkoutSession {
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

    private func waitForConflict(on router: StrengthWorkoutEntryRouter) async {
        for _ in 0..<50 {
            if router.pendingConflict != nil { return }
            await Task.yield()
        }
    }

    private func waitForPresentation(_ capture: PresentationCapture) async {
        for _ in 0..<50 {
            if capture.value != nil { return }
            await Task.yield()
        }
    }

    private func waitForRouterSettlement(
        router: StrengthWorkoutEntryRouter,
        presentation: PresentationCapture
    ) async {
        for _ in 0..<50 {
            if router.pendingConflict != nil || presentation.value != nil || router.alertMessage != nil {
                return
            }
            await Task.yield()
        }
    }

    private func waitForVMConflict(on viewModel: ConversationViewModel) async {
        for _ in 0..<50 {
            if viewModel.pendingWorkoutStartConflict != nil { return }
            await Task.yield()
        }
    }

    private func waitForStartSettlement(context: ShellRoutedContext) async {
        for _ in 0..<50 {
            if context.viewModel.pendingWorkoutStartConflict != nil
                || context.viewModel.hasActiveStrengthConversation
                || context.presentation.value != nil
            {
                return
            }
            await Task.yield()
        }
    }

    private func requestStartAndWait(
        context: ShellRoutedContext,
        target: GymPlanWorkoutTarget
    ) async {
        await context.viewModel.requestStartGymWorkout(target: target)
        await waitForStartSettlement(context: context)
    }

    // MARK: - Shell routing

    func testStartingSameActivePlanResumesWithoutConflict() async throws {
        var context = makeShellRoutedContext()
        let session = try await seedActiveUpperBody(in: context.repository)

        context.viewModel.startIfNeeded()
        await requestStartAndWait(
            context: context,
            target: GymPlanWorkoutTarget(reference: .starter(.upperBody), sectionIndex: 0)
        )

        XCTAssertNil(context.viewModel.pendingWorkoutStartConflict)
        XCTAssertTrue(context.viewModel.hasActiveStrengthConversation)
        XCTAssertEqual(context.viewModel.strengthConversation.session?.sessionID, session.sessionID)
        XCTAssertNil(context.presentation.value)
    }

    func testStartingDifferentPlanWhileActivePresentsShellConflict() async throws {
        var context = makeShellRoutedContext()
        _ = try await seedActiveUpperBody(in: context.repository)

        context.viewModel.startIfNeeded()
        await requestStartAndWait(
            context: context,
            target: GymPlanWorkoutTarget(reference: .starter(.lowerBody), sectionIndex: 0)
        )

        XCTAssertNotNil(context.viewModel.pendingWorkoutStartConflict)
        XCTAssertTrue(context.viewModel.isWorkoutStartConflictDialogPresented)
        XCTAssertEqual(context.viewModel.pendingWorkoutStartConflict?.requestedPlanReference, .starter(.lowerBody))
        XCTAssertEqual(context.viewModel.pendingWorkoutStartConflict?.entrySource, .conversation)
        XCTAssertNil(context.router.pendingConflict)
    }

    func testDialogDismissPreservesConflictPayloadUntilResolve() async throws {
        var context = makeShellRoutedContext()
        _ = try await seedActiveUpperBody(in: context.repository)

        context.viewModel.startIfNeeded()
        await requestStartAndWait(
            context: context,
            target: GymPlanWorkoutTarget(reference: .starter(.lowerBody), sectionIndex: 0)
        )

        context.viewModel.isWorkoutStartConflictDialogPresented = false
        XCTAssertNotNil(context.viewModel.pendingWorkoutStartConflict)

        await context.viewModel.resolveWorkoutStartConflict(.resumeCurrent)
        XCTAssertNil(context.viewModel.pendingWorkoutStartConflict)
        XCTAssertFalse(context.viewModel.isWorkoutStartConflictDialogPresented)
    }

    func testResumeConflictKeepsCurrentSession() async throws {
        var context = makeShellRoutedContext()
        let session = try await seedActiveUpperBody(in: context.repository)

        context.viewModel.startIfNeeded()
        await requestStartAndWait(
            context: context,
            target: GymPlanWorkoutTarget(reference: .starter(.lowerBody), sectionIndex: 0)
        )
        await context.viewModel.resolveWorkoutStartConflict(.resumeCurrent)

        let active = try await context.repository.fetchInProgressSession(ownerID: ownerID)
        XCTAssertEqual(active?.id, session.sessionID)
        XCTAssertNil(context.viewModel.pendingWorkoutStartConflict)
        XCTAssertFalse(context.viewModel.isWorkoutStartConflictDialogPresented)
    }

    func testCancelConflictLeavesCurrentSessionUnchanged() async throws {
        var context = makeShellRoutedContext()
        let session = try await seedActiveUpperBody(in: context.repository)

        context.viewModel.startIfNeeded()
        await requestStartAndWait(
            context: context,
            target: GymPlanWorkoutTarget(reference: .starter(.lowerBody), sectionIndex: 0)
        )
        context.viewModel.cancelWorkoutStartConflict()

        let active = try await context.repository.fetchInProgressSession(ownerID: ownerID)
        XCTAssertEqual(active?.id, session.sessionID)
        XCTAssertNil(context.viewModel.pendingWorkoutStartConflict)
        XCTAssertFalse(context.viewModel.isWorkoutStartConflictDialogPresented)
    }

    func testFinishCurrentAndStartSelectedReplacesActiveSession() async throws {
        let workoutRepo = MockWorkoutRepository()
        var context = makeShellRoutedContext(workoutRepository: workoutRepo)
        let upper = try await seedActiveUpperBody(in: context.repository)

        context.viewModel.startIfNeeded()
        await requestStartAndWait(
            context: context,
            target: GymPlanWorkoutTarget(reference: .starter(.lowerBody), sectionIndex: 0)
        )
        await context.viewModel.resolveWorkoutStartConflict(.finishCurrentAndStartSelected)

        XCTAssertTrue(context.viewModel.hasActiveStrengthConversation)
        XCTAssertEqual(context.viewModel.strengthConversation.session?.planReference, .starter(.lowerBody))
        XCTAssertNil(context.viewModel.pendingWorkoutStartConflict)
        let completed = try await workoutRepo.fetchSessions(
            ownerID: ownerID,
            from: .distantPast,
            to: .distantFuture
        ).first { $0.id == upper.sessionID }
        XCTAssertEqual(completed?.status, .completed)
        let inProgress = try await workoutRepo.fetchInProgressSession(ownerID: ownerID)
        XCTAssertEqual(inProgress?.templateID, GymPlanReference.starter(.lowerBody).storageKey)
    }

    func testDiscardCurrentAndStartSelectedAbandonsPreviousSession() async throws {
        let workoutRepo = MockWorkoutRepository()
        var context = makeShellRoutedContext(workoutRepository: workoutRepo)
        let abandoned = try await seedActiveUpperBody(in: context.repository)

        context.viewModel.startIfNeeded()
        await requestStartAndWait(
            context: context,
            target: GymPlanWorkoutTarget(reference: .starter(.lowerBody), sectionIndex: 0)
        )
        await context.viewModel.resolveWorkoutStartConflict(.discardCurrentAndStartSelected)

        XCTAssertEqual(context.viewModel.strengthConversation.session?.planReference, .starter(.lowerBody))
        XCTAssertNil(context.viewModel.pendingWorkoutStartConflict)
        let abandonedLog = try await workoutRepo.fetchSessions(
            ownerID: ownerID,
            from: .distantPast,
            to: .distantFuture
        ).first { $0.id == abandoned.sessionID }
        XCTAssertNil(abandonedLog)
    }

    func testOnlyOneActiveWorkoutAfterFinishAndStart() async throws {
        let workoutRepo = MockWorkoutRepository()
        var context = makeShellRoutedContext(workoutRepository: workoutRepo)
        _ = try await seedActiveUpperBody(in: context.repository)

        context.viewModel.startIfNeeded()
        await requestStartAndWait(
            context: context,
            target: GymPlanWorkoutTarget(reference: .starter(.lowerBody), sectionIndex: 0)
        )
        await context.viewModel.resolveWorkoutStartConflict(.finishCurrentAndStartSelected)

        let activeCount = try await workoutRepo.fetchSessions(
            ownerID: ownerID,
            from: .distantPast,
            to: .distantFuture
        ).filter { $0.status == .inProgress }.count
        XCTAssertEqual(activeCount, 1)
    }

    func testFailedFinishDoesNotCreateNewWorkout() async throws {
        let workoutRepo = FailingCompleteWorkoutRepository()
        var context = makeShellRoutedContext(workoutRepository: workoutRepo)
        let session = try await seedActiveUpperBody(in: context.repository)

        context.viewModel.startIfNeeded()
        await requestStartAndWait(
            context: context,
            target: GymPlanWorkoutTarget(reference: .starter(.lowerBody), sectionIndex: 0)
        )
        await context.viewModel.resolveWorkoutStartConflict(.finishCurrentAndStartSelected)

        let active = try await workoutRepo.fetchInProgressSession(ownerID: ownerID)
        XCTAssertEqual(active?.id, session.sessionID)
        XCTAssertNotNil(context.viewModel.errorMessage)
        XCTAssertFalse(context.viewModel.hasActiveStrengthConversation)
    }

    func testFailedStartAfterFinishLeavesRecoverableState() async throws {
        let workoutRepo = MockWorkoutRepository()
        let gymPlanRepo = ThrowingResolveGymPlanRepository()
        var context = makeShellRoutedContext(
            workoutRepository: workoutRepo,
            gymPlanRepository: gymPlanRepo
        )
        _ = try await seedActiveUpperBody(in: context.repository)

        context.viewModel.startIfNeeded()
        await requestStartAndWait(
            context: context,
            target: GymPlanWorkoutTarget(reference: .starter(.lowerBody), sectionIndex: 0)
        )
        await context.viewModel.resolveWorkoutStartConflict(.finishCurrentAndStartSelected)

        XCTAssertNil(context.viewModel.pendingWorkoutStartConflict)
        XCTAssertNotNil(context.viewModel.errorMessage)
        let inProgress = try await workoutRepo.fetchInProgressSession(ownerID: ownerID)
        XCTAssertNil(inProgress)
    }

    func testPendingSectionIndexIsRetainedWhileAbandonConfirmationShown() async throws {
        var context = makeShellRoutedContext()
        _ = try await seedActiveUpperBody(in: context.repository)

        context.viewModel.startIfNeeded()
        await requestStartAndWait(
            context: context,
            target: GymPlanWorkoutTarget(reference: .starter(.lowerBody), sectionIndex: 0)
        )
        context.viewModel.requestWorkoutDiscardConfirmation()

        XCTAssertEqual(context.viewModel.pendingWorkoutStartConflict?.requestedWorkoutTarget.sectionIndex, 0)
        XCTAssertTrue(context.viewModel.pendingWorkoutDiscardConfirmation)
        XCTAssertFalse(context.viewModel.isWorkoutStartConflictDialogPresented)
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
        try? await Task.sleep(nanoseconds: 600_000_000)

        XCTAssertEqual(presented?.plan.reference, .starter(.upperBody))
    }

    func testLaunchIntentRoutesThroughShellConflictFlow() async throws {
        let repo = InMemoryActiveConversationRepository()
        let workoutRepo = MockWorkoutRepository()
        let gymPlanRepo = MockGymPlanRepository()
        let session = ConversationTestSupport.makeSession(
            conversationRepository: repo,
            workoutRepository: workoutRepo,
            gymPlanRepository: gymPlanRepo,
            ownerID: ownerID
        )
        var presented: StrengthWorkoutPresentation?
        let coordinator = StrengthWorkoutCoordinator(
            workoutRepository: workoutRepo,
            gymPlanRepository: gymPlanRepo,
            ownerID: ownerID
        )
        let router = StrengthWorkoutEntryRouter(
            coordinator: coordinator,
            gymPlanRepository: gymPlanRepo,
            ownerID: ownerID,
            onPresentWorkout: { presented = $0 }
        )
        session.updateStrengthWorkoutEntryRouting(
            coordinator: coordinator,
            router: router,
            onPresent: { presented = $0 }
        )
        await session.ensureLoaded()
        guard let vm = session.viewModel else {
            return XCTFail("Expected view model")
        }

        _ = try await seedActiveUpperBody(in: workoutRepo)
        session.deliver(TaiLaunchIntent(kind: .startGymWorkout(
            GymPlanWorkoutTarget(reference: .starter(.lowerBody), sectionIndex: 0)
        )))
        await waitForVMConflict(on: vm)

        XCTAssertNotNil(vm.pendingWorkoutStartConflict)
        XCTAssertTrue(vm.isWorkoutStartConflictDialogPresented)
        XCTAssertEqual(vm.pendingWorkoutStartConflict?.entrySource, .home)
        XCTAssertNil(router.pendingConflict)
        XCTAssertNil(presented)
    }

    func testQuickActionStartRoutesThroughShellConflictFlow() async throws {
        var context = makeShellRoutedContext()
        _ = try await seedActiveUpperBody(in: context.repository)
        context.viewModel.startIfNeeded()

        context.viewModel.handleQuickAction(
            ConversationAllowedQuickAction.gymStartLowerBody.asConversationQuickAction()
        )
        await waitForVMConflict(on: context.viewModel)

        XCTAssertNotNil(context.viewModel.pendingWorkoutStartConflict)
        XCTAssertTrue(context.viewModel.isWorkoutStartConflictDialogPresented)
        XCTAssertEqual(context.viewModel.pendingWorkoutStartConflict?.entrySource, .conversation)
    }
}

// MARK: - Test doubles

private final class FailingCompleteWorkoutRepository: WorkoutRepository {
    private let base = MockWorkoutRepository()

    func fetchSessions(ownerID: String, from startDate: Date, to endDate: Date) async throws -> [WorkoutSessionLog] {
        try await base.fetchSessions(ownerID: ownerID, from: startDate, to: endDate)
    }

    func fetchInProgressSession(ownerID: String) async throws -> WorkoutSessionLog? {
        try await base.fetchInProgressSession(ownerID: ownerID)
    }

    func createSession(_ session: WorkoutSessionLog) async throws {
        try await base.createSession(session)
    }

    func updateSession(_ session: WorkoutSessionLog) async throws {
        try await base.updateSession(session)
    }

    func appendSet(_ set: WorkoutSetLog, to sessionID: UUID) async throws {
        try await base.appendSet(set, to: sessionID)
    }

    func completeSession(id: UUID, completedAt: Date, debriefJSON: Data?) async throws {
        throw WorkoutRepositoryError.sessionNotFound(id: id)
    }

    func abandonSession(id: UUID) async throws {
        try await base.abandonSession(id: id)
    }
}

private final class ThrowingResolveGymPlanRepository: GymPlanRepository {
    private let base = MockGymPlanRepository()
    private var lowerBodyResolveAttempts = 0

    func fetchLibrary(ownerID: String) async throws -> GymPlanLibrarySnapshot {
        try await base.fetchLibrary(ownerID: ownerID)
    }

    func fetchTemplateSummaries() -> [GymPlanSummary] {
        base.fetchTemplateSummaries()
    }

    func fetchSummaries(ownerID: String) async throws -> [GymPlanSummary] {
        try await base.fetchSummaries(ownerID: ownerID)
    }

    func resolvePlan(reference: GymPlanReference, sectionIndex: Int, ownerID: String) async throws -> GymResolvablePlan {
        if reference == .starter(.lowerBody) {
            lowerBodyResolveAttempts += 1
            if lowerBodyResolveAttempts >= 2 {
                throw GymPlanRepositoryError.planNotFound
            }
        }
        return try await base.resolvePlan(reference: reference, sectionIndex: sectionIndex, ownerID: ownerID)
    }

    func loadDraft(reference: GymPlanReference, ownerID: String) async throws -> GymPlanDraft {
        try await base.loadDraft(reference: reference, ownerID: ownerID)
    }

    func saveDraft(_ draft: GymPlanDraft, ownerID: String, activation: GymPlanSaveActivation) async throws -> GymPlanReference {
        try await base.saveDraft(draft, ownerID: ownerID, activation: activation)
    }

    func duplicatePlan(reference: GymPlanReference, ownerID: String) async throws -> GymPlanReference {
        try await base.duplicatePlan(reference: reference, ownerID: ownerID)
    }

    func deletePlan(reference: GymPlanReference, ownerID: String) async throws {
        try await base.deletePlan(reference: reference, ownerID: ownerID)
    }

    func archivePlan(reference: GymPlanReference, ownerID: String) async throws {
        try await base.archivePlan(reference: reference, ownerID: ownerID)
    }

    func resetStarterPlan(templateID: GymProgramTemplateID, ownerID: String) async throws {
        try await base.resetStarterPlan(templateID: templateID, ownerID: ownerID)
    }
}
