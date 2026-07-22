import XCTest
@testable import TaiAssistant

@MainActor
final class GymWorkoutStartConflictTests: XCTestCase {
    override func setUp() {
        super.setUp()
        AIDataProcessingConsentStore.resetForTests()
        AIDataProcessingConsentStore.accept(version: AIDataProcessingConsentStore.gymPhotoVersion)
    }

    override func tearDown() {
        AIDataProcessingConsentStore.resetForTests()
        super.tearDown()
    }

    func testStartingSameActivePlanResumesWithoutConflict() async {
        let store = ConversationSessionStore()
        let (vm, _) = ConversationTestSupport.makeViewModel(store: store)
        vm.startIfNeeded()
        await vm.requestStartGymWorkout(target: GymPlanWorkoutTarget(reference: .starter(.upperBody), sectionIndex: 0))
        XCTAssertNotNil(vm.gym.session)
        XCTAssertNil(vm.pendingWorkoutStartConflict)
        XCTAssertFalse(vm.isWorkoutStartConflictDialogPresented)

        await vm.requestStartGymWorkout(target: GymPlanWorkoutTarget(reference: .starter(.upperBody), sectionIndex: 0))
        XCTAssertNil(vm.pendingWorkoutStartConflict)
        XCTAssertTrue(vm.gym.hasActiveSession)
    }

    func testStartingDifferentPlanWhileActivePresentsConflict() async {
        let store = ConversationSessionStore()
        let (vm, _) = ConversationTestSupport.makeViewModel(store: store)
        vm.startIfNeeded()
        await vm.requestStartGymWorkout(target: GymPlanWorkoutTarget(reference: .starter(.upperBody), sectionIndex: 0))

        await vm.requestStartGymWorkout(target: GymPlanWorkoutTarget(reference: .starter(.lowerBody), sectionIndex: 0))
        XCTAssertNotNil(vm.pendingWorkoutStartConflict)
        XCTAssertTrue(vm.isWorkoutStartConflictDialogPresented)
        XCTAssertEqual(vm.pendingWorkoutStartConflict?.requestedPlanReference, .starter(.lowerBody))
        XCTAssertEqual(vm.pendingWorkoutStartConflict?.requestedWorkoutTarget.sectionIndex, 0)
        XCTAssertEqual(vm.gym.session?.planReference, .starter(.upperBody))
    }

    func testDialogDismissPreservesConflictPayloadUntilResolve() async {
        let store = ConversationSessionStore()
        let (vm, _) = ConversationTestSupport.makeViewModel(store: store)
        vm.startIfNeeded()
        await vm.requestStartGymWorkout(target: GymPlanWorkoutTarget(reference: .starter(.upperBody), sectionIndex: 0))
        await vm.requestStartGymWorkout(target: GymPlanWorkoutTarget(reference: .starter(.lowerBody), sectionIndex: 0))

        vm.isWorkoutStartConflictDialogPresented = false
        XCTAssertNotNil(vm.pendingWorkoutStartConflict)

        await vm.resolveWorkoutStartConflict(.resumeCurrent)
        XCTAssertNil(vm.pendingWorkoutStartConflict)
        XCTAssertFalse(vm.isWorkoutStartConflictDialogPresented)
        XCTAssertEqual(vm.gym.session?.planReference, .starter(.upperBody))
    }

    func testResumeConflictKeepsCurrentSession() async {
        let store = ConversationSessionStore()
        let (vm, _) = ConversationTestSupport.makeViewModel(store: store)
        vm.startIfNeeded()
        await vm.requestStartGymWorkout(target: GymPlanWorkoutTarget(reference: .starter(.upperBody), sectionIndex: 0))
        let currentID = vm.gym.session?.sessionID

        await vm.requestStartGymWorkout(target: GymPlanWorkoutTarget(reference: .starter(.lowerBody), sectionIndex: 0))
        await vm.resolveWorkoutStartConflict(.resumeCurrent)

        XCTAssertEqual(vm.gym.session?.sessionID, currentID)
        XCTAssertNil(vm.pendingWorkoutStartConflict)
        XCTAssertFalse(vm.isWorkoutStartConflictDialogPresented)
    }

    func testCancelConflictLeavesCurrentSessionUnchanged() async {
        let store = ConversationSessionStore()
        let (vm, _) = ConversationTestSupport.makeViewModel(store: store)
        vm.startIfNeeded()
        await vm.requestStartGymWorkout(target: GymPlanWorkoutTarget(reference: .starter(.upperBody), sectionIndex: 0))
        let currentID = vm.gym.session?.sessionID

        await vm.requestStartGymWorkout(target: GymPlanWorkoutTarget(reference: .starter(.lowerBody), sectionIndex: 0))
        vm.cancelWorkoutStartConflict()

        XCTAssertEqual(vm.gym.session?.sessionID, currentID)
        XCTAssertNil(vm.pendingWorkoutStartConflict)
        XCTAssertFalse(vm.isWorkoutStartConflictDialogPresented)
    }

    func testFinishCurrentAndStartSelectedReplacesActiveSession() async throws {
        let workoutRepo = MockWorkoutRepository()
        let store = ConversationSessionStore()
        let (vm, _) = ConversationTestSupport.makeViewModel(store: store, workoutRepository: workoutRepo)
        vm.startIfNeeded()
        await vm.requestStartGymWorkout(target: GymPlanWorkoutTarget(reference: .starter(.upperBody), sectionIndex: 0))
        let finishedID = vm.gym.session?.sessionID

        await vm.requestStartGymWorkout(target: GymPlanWorkoutTarget(reference: .starter(.lowerBody), sectionIndex: 0))
        await vm.resolveWorkoutStartConflict(.finishCurrentAndStartSelected)

        XCTAssertNotEqual(vm.gym.session?.sessionID, finishedID)
        XCTAssertEqual(vm.gym.session?.planReference, .starter(.lowerBody))
        XCTAssertNil(vm.pendingWorkoutStartConflict)
        XCTAssertFalse(vm.isWorkoutStartConflictDialogPresented)
        let inProgress = try await workoutRepo.fetchInProgressSession(ownerID: "test.user")
        XCTAssertEqual(inProgress?.id, vm.gym.session?.sessionID)
        let completed = try await workoutRepo.fetchSessions(
            ownerID: "test.user",
            from: .distantPast,
            to: .distantFuture
        ).first { $0.id == finishedID }
        XCTAssertEqual(completed?.status, .completed)
    }

    func testDiscardCurrentAndStartSelectedAbandonsPreviousSession() async throws {
        let workoutRepo = MockWorkoutRepository()
        let store = ConversationSessionStore()
        let (vm, _) = ConversationTestSupport.makeViewModel(store: store, workoutRepository: workoutRepo)
        vm.startIfNeeded()
        await vm.requestStartGymWorkout(target: GymPlanWorkoutTarget(reference: .starter(.upperBody), sectionIndex: 0))
        let abandonedID = vm.gym.session?.sessionID

        await vm.requestStartGymWorkout(target: GymPlanWorkoutTarget(reference: .starter(.lowerBody), sectionIndex: 0))
        await vm.resolveWorkoutStartConflict(.discardCurrentAndStartSelected)

        XCTAssertEqual(vm.gym.session?.planReference, .starter(.lowerBody))
        XCTAssertNil(vm.pendingWorkoutStartConflict)
        XCTAssertFalse(vm.isWorkoutStartConflictDialogPresented)
        let abandoned = try await workoutRepo.fetchSessions(
            ownerID: "test.user",
            from: .distantPast,
            to: .distantFuture
        ).first { $0.id == abandonedID }
        XCTAssertNil(abandoned)
        let inProgress = try await workoutRepo.fetchInProgressSession(ownerID: "test.user")
        XCTAssertEqual(inProgress?.id, vm.gym.session?.sessionID)
    }

    func testOnlyOneActiveWorkoutAfterFinishAndStart() async throws {
        let workoutRepo = MockWorkoutRepository()
        let store = ConversationSessionStore()
        let (vm, _) = ConversationTestSupport.makeViewModel(store: store, workoutRepository: workoutRepo)
        vm.startIfNeeded()
        await vm.requestStartGymWorkout(target: GymPlanWorkoutTarget(reference: .starter(.upperBody), sectionIndex: 0))
        await vm.requestStartGymWorkout(target: GymPlanWorkoutTarget(reference: .starter(.lowerBody), sectionIndex: 0))
        await vm.resolveWorkoutStartConflict(.finishCurrentAndStartSelected)

        let inProgress = try await workoutRepo.fetchInProgressSession(ownerID: "test.user")
        XCTAssertNotNil(inProgress)
        XCTAssertEqual(inProgress?.id, vm.gym.session?.sessionID)
        let activeCount = try await workoutRepo.fetchSessions(
            ownerID: "test.user",
            from: .distantPast,
            to: .distantFuture
        ).filter { $0.status == .inProgress }.count
        XCTAssertEqual(activeCount, 1)
    }

    func testFailedFinishDoesNotCreateNewWorkout() async throws {
        let workoutRepo = FailingCompleteWorkoutRepository()
        let store = ConversationSessionStore()
        let (vm, _) = ConversationTestSupport.makeViewModel(store: store, workoutRepository: workoutRepo)
        vm.startIfNeeded()
        await vm.requestStartGymWorkout(target: GymPlanWorkoutTarget(reference: .starter(.upperBody), sectionIndex: 0))
        let originalID = vm.gym.session?.sessionID

        await vm.requestStartGymWorkout(target: GymPlanWorkoutTarget(reference: .starter(.lowerBody), sectionIndex: 0))
        await vm.resolveWorkoutStartConflict(.finishCurrentAndStartSelected)

        XCTAssertEqual(vm.gym.session?.sessionID, originalID)
        XCTAssertEqual(vm.gym.session?.planReference, .starter(.upperBody))
        XCTAssertNotNil(vm.errorMessage)
        let inProgress = try await workoutRepo.fetchInProgressSession(ownerID: "test.user")
        XCTAssertEqual(inProgress?.id, originalID)
    }

    func testFailedStartAfterFinishLeavesRecoverableState() async throws {
        let workoutRepo = MockWorkoutRepository()
        let gymPlanRepo = ThrowingResolveGymPlanRepository()
        let store = ConversationSessionStore()
        let (vm, _) = ConversationTestSupport.makeViewModel(
            store: store,
            workoutRepository: workoutRepo,
            gymPlanRepository: gymPlanRepo
        )
        vm.startIfNeeded()
        await vm.requestStartGymWorkout(target: GymPlanWorkoutTarget(reference: .starter(.upperBody), sectionIndex: 0))

        await vm.requestStartGymWorkout(target: GymPlanWorkoutTarget(reference: .starter(.lowerBody), sectionIndex: 0))
        await vm.resolveWorkoutStartConflict(.finishCurrentAndStartSelected)

        XCTAssertNil(vm.gym.session)
        XCTAssertNil(vm.pendingWorkoutStartConflict)
        XCTAssertFalse(vm.isWorkoutStartConflictDialogPresented)
        XCTAssertNotNil(vm.errorMessage)
        let inProgress = try await workoutRepo.fetchInProgressSession(ownerID: "test.user")
        XCTAssertNil(inProgress)
    }

    func testPendingSectionIndexIsRetainedWhileDialogShown() async {
        let store = ConversationSessionStore()
        let (vm, _) = ConversationTestSupport.makeViewModel(store: store)
        vm.startIfNeeded()
        await vm.requestStartGymWorkout(target: GymPlanWorkoutTarget(reference: .starter(.upperBody), sectionIndex: 0))

        await vm.requestStartGymWorkout(target: GymPlanWorkoutTarget(reference: .starter(.lowerBody), sectionIndex: 0))
        vm.requestWorkoutDiscardConfirmation()

        XCTAssertEqual(vm.pendingWorkoutStartConflict?.requestedWorkoutTarget.sectionIndex, 0)
        XCTAssertTrue(vm.pendingWorkoutDiscardConfirmation)
        XCTAssertFalse(vm.isWorkoutStartConflictDialogPresented)
    }

    func testDuplicateStartRequestsAreIgnoredWhileInFlight() async {
        let repo = MockGymPlanRepository()
        repo.resolvePlanDelayNanoseconds = 200_000_000
        let store = ConversationSessionStore()
        let (vm, _) = ConversationTestSupport.makeViewModel(store: store, gymPlanRepository: repo)
        vm.startIfNeeded()

        async let first: Void = vm.requestStartGymWorkout(target: GymPlanWorkoutTarget(reference: .starter(.upperBody), sectionIndex: 0))
        async let second: Void = vm.requestStartGymWorkout(target: GymPlanWorkoutTarget(reference: .starter(.lowerBody), sectionIndex: 0))
        _ = await (first, second)

        XCTAssertTrue(vm.gym.hasActiveSession)
        XCTAssertEqual(vm.gym.session?.planReference, .starter(.upperBody))
    }

    func testLaunchIntentRoutesThroughConflictFlow() async {
        let repo = InMemoryActiveConversationRepository()
        let session = ConversationTestSupport.makeSession(conversationRepository: repo)
        await session.ensureLoaded()
        guard let vm = session.viewModel else {
            return XCTFail("Expected view model")
        }

        await vm.requestStartGymWorkout(target: GymPlanWorkoutTarget(reference: .starter(.upperBody), sectionIndex: 0))
        session.deliver(TaiLaunchIntent(kind: .startGymWorkout(
            GymPlanWorkoutTarget(reference: .starter(.lowerBody), sectionIndex: 0)
        )))
        await waitForConflict(on: vm)
        XCTAssertNotNil(vm.pendingWorkoutStartConflict)
        XCTAssertTrue(vm.isWorkoutStartConflictDialogPresented)
    }

    func testQuickActionStartRoutesThroughConflictFlow() async {
        let store = ConversationSessionStore()
        let (vm, _) = ConversationTestSupport.makeViewModel(store: store)
        vm.startIfNeeded()
        await vm.requestStartGymWorkout(target: GymPlanWorkoutTarget(reference: .starter(.upperBody), sectionIndex: 0))

        vm.handleQuickAction(ConversationAllowedQuickAction.gymStartLowerBody.asConversationQuickAction())
        await waitForConflict(on: vm)

        XCTAssertNotNil(vm.pendingWorkoutStartConflict)
        XCTAssertTrue(vm.isWorkoutStartConflictDialogPresented)
    }

    private func waitForConflict(on vm: ConversationViewModel) async {
        for _ in 0..<50 {
            if vm.pendingWorkoutStartConflict != nil { return }
            await Task.yield()
        }
    }
}

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

    func completeSession(id: UUID, completedAt: Date) async throws {
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
