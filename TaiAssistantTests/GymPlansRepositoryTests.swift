import XCTest
@testable import TaiAssistant

@MainActor
final class GymPlansRepositoryTests: XCTestCase {
    func testTemplateSummariesAppearForBrowseOnly() async throws {
        let repo = MockGymPlanRepository()
        let templates = repo.fetchTemplateSummaries()
        XCTAssertEqual(templates.count, GymProgramTemplateID.allCases.count)
        let summaries = try await repo.fetchSummaries(ownerID: "plans.test")
        XCTAssertTrue(summaries.isEmpty)
    }

    func testEditStarterCreatesPersistedOverride() async throws {
        let repo = MockGymPlanRepository()
        var draft = try await repo.loadDraft(reference: .starter(.upperBody), ownerID: "plans.test")
        draft.title = "My Upper Body"
        draft.sections[0].exercises = Array(draft.sections[0].exercises.prefix(4))
        _ = try await repo.saveDraft(draft, ownerID: "plans.test")

        let loaded = try await repo.loadDraft(reference: .starter(.upperBody), ownerID: "plans.test")
        XCTAssertEqual(loaded.title, "My Upper Body")
        XCTAssertEqual(loaded.exercises.count, 4)
    }

    func testDuplicateCreatesCustomPlan() async throws {
        let repo = MockGymPlanRepository()
        let duplicate = try await repo.duplicatePlan(reference: .starter(.lowerBody), ownerID: "plans.test")
        guard case .custom = duplicate else {
            return XCTFail("Expected custom duplicate")
        }

        let summaries = try await repo.fetchSummaries(ownerID: "plans.test")
        XCTAssertEqual(summaries.count, 1)
        let copy = summaries.first { $0.reference == duplicate }
        XCTAssertEqual(copy?.title, "Copy of Lower Body")
        XCTAssertTrue(copy?.isCustom == true)
    }

    func testCustomPlanCanBeDeleted() async throws {
        let repo = MockGymPlanRepository()
        let duplicate = try await repo.duplicatePlan(reference: .starter(.upperBody), ownerID: "plans.test")
        try await repo.deletePlan(reference: duplicate, ownerID: "plans.test")
        let summaries = try await repo.fetchSummaries(ownerID: "plans.test")
        XCTAssertFalse(summaries.contains { $0.reference == duplicate })
    }

    func testResolveCustomPlanStartsWorkout() async throws {
        let repo = MockGymPlanRepository()
        let duplicate = try await repo.duplicatePlan(reference: .starter(.upperBody), ownerID: "plans.test")
        let resolved = try await repo.resolvePlan(reference: duplicate, sectionIndex: 0, ownerID: "plans.test")
        let gym = GymCapabilityController(
            workoutRepository: MockWorkoutRepository(),
            aiService: MockAIService(),
            ownerID: "plans.test"
        )
        let session = try await gym.startWorkout(plan: resolved)
        XCTAssertEqual(session.title, "Copy of Upper Body")
        XCTAssertEqual(session.planReference, duplicate)
    }

    func testReorderCustomPlanPersistsOrder() async throws {
        let repo = MockGymPlanRepository()
        let duplicate = try await repo.duplicatePlan(reference: .starter(.upperBody), ownerID: "plans.test")
        var draft = try await repo.loadDraft(reference: duplicate, ownerID: "plans.test")
        draft.moveExercises(from: IndexSet(integer: 0), to: 2)
        _ = try await repo.saveDraft(draft, ownerID: "plans.test")

        let resolved = try await repo.resolvePlan(reference: duplicate, sectionIndex: 0, ownerID: "plans.test")
        XCTAssertEqual(resolved.exercises.map(\.reference.stableID), draft.exercises.map(\.reference.stableID))
    }

    func testImportSaveAndActivateArchivesPreviousPlan() async throws {
        let repo = MockGymPlanRepository()
        var first = GymPlanDraft.blank()
        first.title = "Program A"
        first.sections[0].exercises = GymProgramTemplateLibrary.template(for: .upperBody).exercises
        first.importedAt = .now
        let refA = try await repo.saveDraft(first, ownerID: "plans.test", activation: .makeActive)

        var second = GymPlanDraft.blank()
        second.title = "Program B"
        second.sections[0].exercises = GymProgramTemplateLibrary.template(for: .lowerBody).exercises
        second.importedAt = .now
        _ = try await repo.saveDraft(second, ownerID: "plans.test", activation: .makeActive)

        let library = try await repo.fetchLibrary(ownerID: "plans.test")
        XCTAssertEqual(library.activePlan?.title, "Program B")
        XCTAssertTrue(library.previousPlans.contains { $0.reference == refA })
    }

    func testWorkoutStartsInSavedPlanOrder() async throws {
        let repo = MockGymPlanRepository()
        var draft = try await repo.loadDraft(reference: .starter(.upperBody), ownerID: "plans.test")
        draft.moveExercises(from: IndexSet(integer: 0), to: 2)
        _ = try await repo.saveDraft(draft, ownerID: "plans.test")

        let resolved = try await repo.resolvePlan(reference: .starter(.upperBody), sectionIndex: 0, ownerID: "plans.test")
        let gym = GymCapabilityController(
            workoutRepository: MockWorkoutRepository(),
            aiService: MockAIService(),
            ownerID: "plans.test"
        )
        let session = try await gym.startWorkout(plan: resolved)
        XCTAssertEqual(session.exercises.map(\.reference.stableID), resolved.exercises.map(\.reference.stableID))
    }

    func testEditingPlanDoesNotMutateActiveSession() async throws {
        let repo = MockGymPlanRepository()
        let gym = GymCapabilityController(
            workoutRepository: MockWorkoutRepository(),
            aiService: MockAIService(),
            ownerID: "plans.test"
        )
        let original = try await repo.resolvePlan(reference: .starter(.upperBody), sectionIndex: 0, ownerID: "plans.test")
        let session = try await gym.startWorkout(plan: original)
        let originalOrder = session.exercises.map(\.reference.stableID)

        var draft = try await repo.loadDraft(reference: .starter(.upperBody), ownerID: "plans.test")
        draft.moveExercises(from: IndexSet(integer: 0), to: draft.exercises.count)
        _ = try await repo.saveDraft(draft, ownerID: "plans.test")

        XCTAssertEqual(gym.session?.exercises.map(\.reference.stableID), originalOrder)
    }
}
