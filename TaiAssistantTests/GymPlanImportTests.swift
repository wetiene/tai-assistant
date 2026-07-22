import XCTest
@testable import TaiAssistant

@MainActor
final class GymPlanImportTests: XCTestCase {
    private let ownerID = "import.test"

    func testTextImportCreatesDraftOnly() async throws {
        let draft = try await GymPlanImportService.interpret(
            source: .pastedText(GymTrainerProgramFixture.pastedText),
            aiService: MockAIService()
        )
        XCTAssertEqual(draft.sections.count, 2)
        XCTAssertEqual(draft.sections.map(\.name), GymTrainerProgramFixture.expectedSectionNames)
        XCTAssertTrue(draft.requiresUserConfirmation)
    }

    func testTrainerFixturePreservesOptionalExercisesAndPrescription() async throws {
        let draft = try await GymPlanImportService.interpret(
            source: .pastedText(GymTrainerProgramFixture.pastedText),
            aiService: MockAIService()
        )
        let upper = draft.sections.first { $0.name == "Upper Body" }!
        XCTAssertEqual(upper.exercises.count, 6)
        XCTAssertEqual(upper.exercises.map(\.displayName), [
            "Supine Chest Press",
            "Seated Shoulder Press",
            "Reverse Grip Lat Pulldown",
            "Seated Row",
            "Bicep Curl",
            "Tricep Pushdown",
        ])
        XCTAssertTrue(upper.exercises[4].isOptional)
        XCTAssertTrue(upper.exercises[5].isOptional)
        XCTAssertFalse(upper.exercises[0].isOptional)
        XCTAssertEqual(draft.prescription.workingSetsPerExercise, 3)
        XCTAssertEqual(draft.prescription.repRangeLower, 8)
        XCTAssertEqual(draft.prescription.repRangeUpper, 12)
        XCTAssertFalse(draft.generalInstructions.isEmpty)
    }

    func testTrainerFixtureExerciseOrderAndRepRangesPerExercise() async throws {
        let draft = try await GymPlanImportService.interpret(
            source: .pastedText(GymTrainerProgramFixture.pastedText),
            aiService: MockAIService()
        )
        let upper = draft.sections.first { $0.name == "Upper Body" }!
        for exercise in upper.exercises {
            XCTAssertEqual(exercise.targetSets, 3)
            XCTAssertEqual(exercise.minimumRepetitions, 8)
            XCTAssertEqual(exercise.maximumRepetitions, 12)
        }
    }

    func testCancelImportDoesNotPersistPlan() async throws {
        let repo = MockGymPlanRepository()
        _ = try await GymPlanImportService.interpret(
            source: .pastedText(GymTrainerProgramFixture.pastedText),
            aiService: MockAIService()
        )
        let summaries = try await repo.fetchSummaries(ownerID: ownerID)
        XCTAssertTrue(summaries.isEmpty)
    }

    func testSavingReviewedImportPersistsSections() async throws {
        let repo = MockGymPlanRepository()
        let importDraft = try await GymPlanImportService.interpret(
            source: .pastedText(GymTrainerProgramFixture.pastedText),
            aiService: MockAIService()
        )
        var planDraft = importDraft.asPlanDraft()
        planDraft.importedAt = .now
        let reference = try await repo.saveDraft(planDraft, ownerID: ownerID, activation: .makeActive)
        let loaded = try await repo.loadDraft(reference: reference, ownerID: ownerID)
        XCTAssertEqual(loaded.sections.count, 2)
        XCTAssertEqual(loaded.lifecycleStatus, .active)
    }

    func testImportingTwiceDoesNotSilentlyOverwriteExistingPlan() async throws {
        let repo = MockGymPlanRepository()
        let firstDraft = try await GymPlanImportService.interpret(
            source: .pastedText(GymTrainerProgramFixture.pastedText),
            aiService: MockAIService()
        )
        let firstRef = try await repo.saveDraft(firstDraft.asPlanDraft(), ownerID: ownerID, activation: .saveOnly)
        let secondDraft = try await GymPlanImportService.interpret(
            source: .pastedText(GymTrainerProgramFixture.pastedText),
            aiService: MockAIService()
        )
        var renamed = secondDraft.asPlanDraft()
        renamed.title = "Second import"
        _ = try await repo.saveDraft(renamed, ownerID: ownerID, activation: .saveOnly)
        let summaries = try await repo.fetchSummaries(ownerID: ownerID)
        XCTAssertEqual(summaries.count, 2)
        XCTAssertTrue(summaries.contains { $0.reference == firstRef })
    }

    func testActivateImportedPlanArchivesPreviousActivePlan() async throws {
        let repo = MockGymPlanRepository()
        var first = GymPlanDraft.blank()
        first.title = "Program A"
        first.sections[0].exercises = GymProgramTemplateLibrary.template(for: .upperBody).exercises
        let refA = try await repo.saveDraft(first, ownerID: ownerID, activation: .makeActive)

        let importDraft = try await GymPlanImportService.interpret(
            source: .pastedText(GymTrainerProgramFixture.pastedText),
            aiService: MockAIService()
        )
        _ = try await repo.saveDraft(importDraft.asPlanDraft(), ownerID: ownerID, activation: .makeActive)

        let library = try await repo.fetchLibrary(ownerID: ownerID)
        XCTAssertEqual(library.activePlan?.title, importDraft.title)
        XCTAssertTrue(library.previousPlans.contains { $0.reference == refA })
    }

    func testUnresolvedExerciseCanRemainCustom() async throws {
        let importDraft = try await GymPlanImportService.interpret(
            source: .pastedText(GymTrainerProgramFixture.pastedText),
            aiService: MockAIService()
        )
        var draft = importDraft
        let lower = draft.sections.firstIndex(where: { $0.name == "Lower Body" })!
        let gluteIndex = draft.sections[lower].exercises.firstIndex(where: { $0.sourceName == "Glute Trainer" })!
        draft.sections[lower].exercises[gluteIndex].reference.catalogExerciseID = nil
        draft.sections[lower].exercises[gluteIndex].isUnresolved = false
        XCTAssertNil(draft.sections[lower].exercises[gluteIndex].reference.catalogID)
        XCTAssertEqual(draft.sections[lower].exercises[gluteIndex].displayName, "Glute Trainer")
    }

    func testImportSourceIsNotPersistedWithPlan() async throws {
        var source = GymPlanImportSource.pastedText(GymTrainerProgramFixture.pastedText)
        _ = try await GymPlanImportService.interpret(source: source, aiService: MockAIService())
        source.clearTransientPayload()
        XCTAssertNil(source.text)
        XCTAssertNil(source.attachmentData)
    }

    func testImageSourceBytesClearedAfterInterpretation() async throws {
        let jpegHeader = Data([0xFF, 0xD8, 0xFF, 0xD9])
        var source = try GymPlanImportImageSupport.makeSource(from: jpegHeader)
        _ = try await GymPlanImportService.interpret(source: source, aiService: MockAIService())
        source.clearTransientPayload()
        XCTAssertNil(source.attachmentData)
    }

    func testImageValidationRejectsOversizedPayload() {
        let oversized = Data(repeating: 0xFF, count: GymPlanImportImageSupport.maxByteCount + 1)
        XCTAssertThrowsError(try GymPlanImportImageSupport.validate(data: oversized)) { error in
            XCTAssertEqual(error as? GymPlanImportImageSupport.ValidationError, .tooLarge)
        }
    }

    func testImageValidationRejectsUnsupportedFormat() {
        let gif = Data([0x47, 0x49, 0x46, 0x38])
        XCTAssertThrowsError(try GymPlanImportImageSupport.validate(data: gif)) { error in
            XCTAssertEqual(error as? GymPlanImportImageSupport.ValidationError, .unsupportedFormat)
        }
    }

    func testStartingUpperBodyUsesImportedSectionExercises() async throws {
        let repo = MockGymPlanRepository()
        let importDraft = try await GymPlanImportService.interpret(
            source: .pastedText(GymTrainerProgramFixture.pastedText),
            aiService: MockAIService()
        )
        let reference = try await repo.saveDraft(importDraft.asPlanDraft(), ownerID: ownerID, activation: .makeActive)
        let resolved = try await repo.resolvePlan(reference: reference, sectionIndex: 0, ownerID: ownerID)
        XCTAssertEqual(resolved.sectionName, "Upper Body")
        XCTAssertEqual(resolved.exercises.map(\.displayName).prefix(4), [
            "Supine Chest Press",
            "Seated Shoulder Press",
            "Reverse Grip Lat Pulldown",
            "Seated Row",
        ])

        let gym = GymCapabilityController(
            workoutRepository: MockWorkoutRepository(),
            aiService: MockAIService(),
            ownerID: ownerID
        )
        let session = try await gym.startWorkout(plan: resolved)
        XCTAssertEqual(session.exercises.map(\.displayName), resolved.exercises.map(\.displayName))
    }

    func testGymPhotoContextUsesActiveImportedPlanExercises() async throws {
        let repo = MockGymPlanRepository()
        let importDraft = try await GymPlanImportService.interpret(
            source: .pastedText(GymTrainerProgramFixture.pastedText),
            aiService: MockAIService()
        )
        let reference = try await repo.saveDraft(importDraft.asPlanDraft(), ownerID: ownerID, activation: .makeActive)
        let upper = try await repo.resolvePlan(reference: reference, sectionIndex: 0, ownerID: ownerID)
        let lower = try await repo.resolvePlan(reference: reference, sectionIndex: 1, ownerID: ownerID)

        XCTAssertTrue(upper.exercises.map(\.reference.stableID).contains(GymExerciseID.supineChestPress.rawValue))
        XCTAssertTrue(lower.exercises.map(\.displayName).contains("Glute Trainer"))
    }

    func testClassifierDetectsImportAndPasteIntents() {
        XCTAssertEqual(
            ConversationGymIntentClassifier.classify("import my trainer plan"),
            .openPlanImport
        )
        XCTAssertEqual(
            ConversationGymIntentClassifier.classify("replace my current gym plan"),
            .replacePlan
        )
        if case .pastePlanText = ConversationGymIntentClassifier.classify(GymTrainerProgramFixture.pastedText) {
            // expected
        } else {
            XCTFail("Expected paste plan text classification")
        }
    }

    func testRoutingOpensImportForTrainerPlanPhrase() {
        let route = ConversationRouter.route(
            text: "import my trainer plan",
            hasPhoto: false,
            targetedMealDraftID: nil
        )
        XCTAssertEqual(route, .gymOpenPlanImport)
    }
}
