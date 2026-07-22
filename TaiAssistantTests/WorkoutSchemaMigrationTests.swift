import XCTest
import SwiftData
@testable import TaiAssistant

@MainActor
final class WorkoutSchemaMigrationTests: XCTestCase {
    private let ownerID = "migration.test.user"

    func testAllSchemaVersionsHaveDistinctIdentifiers() {
        XCTAssertEqual(TaiAssistantSchemaV1.versionIdentifier, Schema.Version(1, 0, 0))
        XCTAssertEqual(TaiAssistantSchemaV2.versionIdentifier, Schema.Version(2, 0, 0))
        XCTAssertEqual(TaiAssistantSchemaV3.versionIdentifier, Schema.Version(3, 0, 0))
        XCTAssertEqual(TaiAssistantSchemaV4.versionIdentifier, Schema.Version(4, 0, 0))
        XCTAssertEqual(TaiAssistantSchema.currentVersionIdentifier, TaiAssistantSchemaV4.versionIdentifier)

        let identifiers = [
            TaiAssistantSchemaV1.versionIdentifier,
            TaiAssistantSchemaV2.versionIdentifier,
            TaiAssistantSchemaV3.versionIdentifier,
            TaiAssistantSchemaV4.versionIdentifier,
        ]
        XCTAssertEqual(Set(identifiers).count, identifiers.count)
    }

    func testFreshV4StoreBootstrapsWithProductionContainer() throws {
        let storeURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("tai-fresh-v4-\(UUID().uuidString).sqlite")
        defer {
            try? FileManager.default.removeItem(at: storeURL)
            try? FileManager.default.removeItem(at: storeURL.appendingPathExtension("wal"))
            try? FileManager.default.removeItem(at: storeURL.appendingPathExtension("shm"))
        }

        let container = AppModelContainerFactory.makeContainer(inMemory: false, storeURL: storeURL)
        let context = ModelContext(container)

        XCTAssertEqual(try context.fetch(FetchDescriptor<GymWorkoutPlan>()).count, 0)
        XCTAssertEqual(try context.fetch(FetchDescriptor<MealLog>()).count, 0)

        _ = AppModelContainerFactory.makeContainer(inMemory: false, storeURL: storeURL)
    }

    func testLegacyV3StoreUsesHistoricalGymWorkoutPlanEntityName() throws {
        let storeURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("tai-v3-entity-\(UUID().uuidString).sqlite")
        defer {
            try? FileManager.default.removeItem(at: storeURL)
            try? FileManager.default.removeItem(at: storeURL.appendingPathExtension("wal"))
            try? FileManager.default.removeItem(at: storeURL.appendingPathExtension("shm"))
        }

        let v3Container = try AppModelContainerFactory.makeLegacyV3Container(storeURL: storeURL)
        let v3Context = ModelContext(v3Container)
        v3Context.insert(
            GymWorkoutPlanV3(
                ownerID: ownerID,
                title: "Historical entity name",
                exercisesJSON: try GymPlanPersistenceCodec.encodeExercises([]),
                prescriptionJSON: try GymPlanPersistenceCodec.encodePrescription(.default)
            )
        )
        try v3Context.save()

        let entityNames = try SwiftDataStoreInspector.entityNames(at: storeURL)
        XCTAssertTrue(entityNames.contains("GymWorkoutPlan"))
        XCTAssertFalse(entityNames.contains("GymWorkoutPlanV3"))
    }

    func testDevelopmentStoreFixtureMigratesToV4() throws {
        let fixtureURL = URL(fileURLWithPath: "/Users/william/Projects/TaiAssistant/tmp-dev-store.sqlite")
        guard FileManager.default.fileExists(atPath: fixtureURL.path) else {
            throw XCTSkip("Local development-store fixture is unavailable in this environment.")
        }

        let storeURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("tai-dev-fixture-\(UUID().uuidString).sqlite")
        defer {
            try? FileManager.default.removeItem(at: storeURL)
            try? FileManager.default.removeItem(at: storeURL.appendingPathExtension("wal"))
            try? FileManager.default.removeItem(at: storeURL.appendingPathExtension("shm"))
        }

        try FileManager.default.copyItem(at: fixtureURL, to: storeURL)
        for suffix in ["-wal", "-shm"] {
            let source = URL(fileURLWithPath: fixtureURL.path + suffix)
            if FileManager.default.fileExists(atPath: source.path) {
                try FileManager.default.copyItem(at: source, to: URL(fileURLWithPath: storeURL.path + suffix))
            }
        }

        let metadata = try SwiftDataStoreInspector.metadata(at: storeURL)
        XCTAssertEqual(metadata.versionIdentifier, "3.0.0")
        XCTAssertTrue(metadata.entityNames.contains("GymWorkoutPlan"))

        let container = AppModelContainerFactory.makeContainer(inMemory: false, storeURL: storeURL)
        let context = ModelContext(container)
        XCTAssertGreaterThanOrEqual(try context.fetch(FetchDescriptor<MealLog>()).count, 0)
        XCTAssertGreaterThanOrEqual(try context.fetch(FetchDescriptor<GymWorkoutPlan>()).count, 0)

        _ = AppModelContainerFactory.makeContainer(inMemory: false, storeURL: storeURL)
    }

    func testV1StoreMigratesToV2PreservingMealsAndConversation() async throws {
        let storeURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("tai-migration-\(UUID().uuidString).sqlite")
        defer {
            try? FileManager.default.removeItem(at: storeURL)
            try? FileManager.default.removeItem(at: storeURL.appendingPathExtension("wal"))
            try? FileManager.default.removeItem(at: storeURL.appendingPathExtension("shm"))
        }

        let mealID = UUID()
        let conversationID = UUID()

        let v1Container = try AppModelContainerFactory.makeLegacyV1Container(storeURL: storeURL)
        let v1Context = ModelContext(v1Container)
        v1Context.insert(
            MealLog(
                id: mealID,
                ownerID: ownerID,
                eatenAt: .now,
                notes: "Pre-migration meal"
            )
        )
        v1Context.insert(
            PersistedConversation(
                id: conversationID,
                ownerID: ownerID,
                composerText: "Saved composer draft"
            )
        )
        try v1Context.save()

        let migratedContainer = AppModelContainerFactory.makeContainer(inMemory: false, storeURL: storeURL)
        let probe = ModelContext(migratedContainer)

        let meals = try probe.fetch(FetchDescriptor<MealLog>())
        XCTAssertEqual(meals.count, 1)
        XCTAssertEqual(meals.first?.id, mealID)
        XCTAssertEqual(meals.first?.notes, "Pre-migration meal")

        let conversations = try probe.fetch(FetchDescriptor<PersistedConversation>())
        XCTAssertEqual(conversations.count, 1)
        XCTAssertEqual(conversations.first?.id, conversationID)
        XCTAssertEqual(conversations.first?.composerText, "Saved composer draft")

        let workoutRepo = LocalSwiftDataWorkoutRepository(container: migratedContainer)
        let session = WorkoutSessionLog(
            ownerID: ownerID,
            templateID: GymProgramTemplateID.upperBody.rawValue,
            title: "Upper Body"
        )
        try await workoutRepo.createSession(session)

        let set = WorkoutSetLog(
            exerciseID: GymExerciseID.legPress.rawValue,
            exerciseName: GymExerciseID.legPress.displayName,
            setNumber: 1,
            weightValue: 80,
            weightUnit: "kg",
            repetitions: 10
        )
        try await workoutRepo.appendSet(set, to: session.id)

        let bounds = NutritionDay.today().queryBounds()
        let sessions = try await workoutRepo.fetchSessions(
            ownerID: ownerID,
            from: bounds.start,
            to: bounds.end
        )
        XCTAssertEqual(sessions.count, 1)
        XCTAssertEqual(sessions.first?.sets.count, 1)
        XCTAssertEqual(sessions.first?.sets.first?.exerciseID, GymExerciseID.legPress.rawValue)
    }

    func testMigratedStoreDoesNotDuplicateExistingRows() async throws {
        let storeURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("tai-migration-dup-\(UUID().uuidString).sqlite")
        defer {
            try? FileManager.default.removeItem(at: storeURL)
            try? FileManager.default.removeItem(at: storeURL.appendingPathExtension("wal"))
            try? FileManager.default.removeItem(at: storeURL.appendingPathExtension("shm"))
        }

        let v1Container = try AppModelContainerFactory.makeLegacyV1Container(storeURL: storeURL)
        let v1Context = ModelContext(v1Container)
        v1Context.insert(MealLog(ownerID: ownerID, eatenAt: .now, notes: "Only meal"))
        try v1Context.save()

        let migratedContainer = AppModelContainerFactory.makeContainer(inMemory: false, storeURL: storeURL)
        let probe = ModelContext(migratedContainer)
        let mealsAfterFirstOpen = try probe.fetch(FetchDescriptor<MealLog>())
        XCTAssertEqual(mealsAfterFirstOpen.count, 1)

        _ = AppModelContainerFactory.makeContainer(inMemory: false, storeURL: storeURL)
        let mealsAfterSecondOpen = try probe.fetch(FetchDescriptor<MealLog>())
        XCTAssertEqual(mealsAfterSecondOpen.count, 1)
    }

    func testV2StoreMigratesToV3PreservingDataAndEnablingGymPlans() async throws {
        let storeURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("tai-migration-v2v3-\(UUID().uuidString).sqlite")
        defer {
            try? FileManager.default.removeItem(at: storeURL)
            try? FileManager.default.removeItem(at: storeURL.appendingPathExtension("wal"))
            try? FileManager.default.removeItem(at: storeURL.appendingPathExtension("shm"))
        }

        let mealID = UUID()
        let conversationID = UUID()
        let completedSessionID = UUID()
        let activeSessionID = UUID()
        let ownerID = self.ownerID

        let v2Container = try AppModelContainerFactory.makeLegacyV2Container(storeURL: storeURL)
        let v2Context = ModelContext(v2Container)

        v2Context.insert(
            MealLog(
                id: mealID,
                ownerID: ownerID,
                eatenAt: .now,
                notes: "Pre-V3 meal"
            )
        )
        v2Context.insert(
            PersistedConversation(
                id: conversationID,
                ownerID: ownerID,
                composerText: "Saved composer draft"
            )
        )

        let completedSession = WorkoutSessionLog(
            id: completedSessionID,
            ownerID: ownerID,
            templateID: GymProgramTemplateID.upperBody.rawValue,
            title: "Upper Body",
            startedAt: .now.addingTimeInterval(-3600),
            completedAt: .now.addingTimeInterval(-1800),
            statusRaw: GymWorkoutSessionStatus.completed.rawValue,
            activeSessionJSON: nil
        )
        let completedSet = WorkoutSetLog(
            exerciseID: GymExerciseID.supineChestPress.rawValue,
            exerciseName: GymExerciseID.supineChestPress.displayName,
            setNumber: 1,
            weightValue: 60,
            weightUnit: "kg",
            repetitions: 10
        )
        completedSet.session = completedSession
        completedSession.sets = [completedSet]
        v2Context.insert(completedSession)

        let activePlan = GymProgramTemplateLibrary.resolvableStarter(.lowerBody)
        let activeSnapshot = GymActiveSession(
            sessionID: activeSessionID,
            planReference: .starter(.lowerBody),
            title: activePlan.title,
            exercises: activePlan.exercises,
            prescription: activePlan.prescription,
            currentExerciseIndex: 1,
            currentSetNumber: 2,
            startedAt: .now.addingTimeInterval(-600),
            status: .inProgress
        )
        let activeJSON = try JSONEncoder().encode(activeSnapshot)
        let activeSession = WorkoutSessionLog(
            id: activeSessionID,
            ownerID: ownerID,
            templateID: GymProgramTemplateID.lowerBody.rawValue,
            title: "Lower Body",
            startedAt: activeSnapshot.startedAt,
            statusRaw: GymWorkoutSessionStatus.inProgress.rawValue,
            activeSessionJSON: activeJSON
        )
        v2Context.insert(activeSession)
        try v2Context.save()

        let migratedContainer = AppModelContainerFactory.makeContainer(inMemory: false, storeURL: storeURL)
        let probe = ModelContext(migratedContainer)

        let meals = try probe.fetch(FetchDescriptor<MealLog>())
        XCTAssertEqual(meals.count, 1)
        XCTAssertEqual(meals.first?.id, mealID)
        XCTAssertEqual(meals.first?.notes, "Pre-V3 meal")

        let conversations = try probe.fetch(FetchDescriptor<PersistedConversation>())
        XCTAssertEqual(conversations.count, 1)
        XCTAssertEqual(conversations.first?.id, conversationID)

        let workoutRepo = LocalSwiftDataWorkoutRepository(container: migratedContainer)
        let bounds = NutritionDay.today().queryBounds()
        let sessions = try await workoutRepo.fetchSessions(
            ownerID: ownerID,
            from: bounds.start.addingTimeInterval(-7200),
            to: bounds.end
        )
        XCTAssertEqual(sessions.count, 2)

        let completed = sessions.first { $0.id == completedSessionID }
        XCTAssertEqual(completed?.status, .completed)
        XCTAssertEqual(completed?.sets.count, 1)
        XCTAssertEqual(completed?.sets.first?.exerciseID, GymExerciseID.supineChestPress.rawValue)
        XCTAssertEqual(GymPlanReference.decode(storageKey: completed?.templateID ?? ""), .starter(.upperBody))

        let inProgress = try await workoutRepo.fetchInProgressSession(ownerID: ownerID)
        XCTAssertEqual(inProgress?.id, activeSessionID)
        XCTAssertEqual(GymPlanReference.decode(storageKey: inProgress?.templateID ?? ""), .starter(.lowerBody))
        let decodedActive = try JSONDecoder().decode(GymActiveSession.self, from: inProgress!.activeSessionJSON!)
        XCTAssertEqual(decodedActive.planReference, .starter(.lowerBody))
        XCTAssertEqual(decodedActive.currentExerciseIndex, 1)

        let gymPlanRepo = LocalSwiftDataGymPlanRepository(container: migratedContainer)
        let summaries = try await gymPlanRepo.fetchSummaries(ownerID: ownerID)
        XCTAssertTrue(summaries.isEmpty)
        XCTAssertEqual(gymPlanRepo.fetchTemplateSummaries().count, GymProgramTemplateID.allCases.count)
        XCTAssertEqual(try probe.fetch(FetchDescriptor<GymWorkoutPlan>()).count, 0)

        var customDraft = GymPlanDraft.blank()
        customDraft.title = "Post-migration custom"
        customDraft.exercises = Array(GymProgramTemplateLibrary.template(for: .upperBody).exercises.prefix(3))
        let customReference = try await gymPlanRepo.saveDraft(customDraft, ownerID: ownerID)
        guard case .custom = customReference else {
            return XCTFail("Expected custom plan reference")
        }

        let summariesAfterCustom = try await gymPlanRepo.fetchSummaries(ownerID: ownerID)
        XCTAssertEqual(summariesAfterCustom.count, 1)

        _ = AppModelContainerFactory.makeContainer(inMemory: false, storeURL: storeURL)
        let mealsAfterReopen = try probe.fetch(FetchDescriptor<MealLog>())
        let plansAfterReopen = try probe.fetch(FetchDescriptor<GymWorkoutPlan>())
        let sessionsAfterReopen = try await workoutRepo.fetchSessions(
            ownerID: ownerID,
            from: bounds.start.addingTimeInterval(-7200),
            to: bounds.end
        )
        XCTAssertEqual(mealsAfterReopen.count, 1)
        XCTAssertEqual(plansAfterReopen.count, 1)
        XCTAssertEqual(sessionsAfterReopen.count, 2)
        let summariesAfterReopen = try await gymPlanRepo.fetchSummaries(ownerID: ownerID)
        XCTAssertEqual(summariesAfterReopen.count, 1)
    }

    func testV3AndV4SchemasHaveDistinctVersionIdentifiersAndModels() {
        XCTAssertNotEqual(
            TaiAssistantSchemaV3.versionIdentifier,
            TaiAssistantSchemaV4.versionIdentifier
        )
        XCTAssertTrue(TaiAssistantSchemaV3.models.contains { $0 == TaiAssistantSchemaV3.GymWorkoutPlan.self })
        XCTAssertTrue(TaiAssistantSchemaV4.models.contains { $0 == GymWorkoutPlan.self })
        XCTAssertFalse(TaiAssistantSchemaV3.models.contains { $0 == GymWorkoutPlan.self })
        XCTAssertFalse(TaiAssistantSchemaV4.models.contains { $0 == TaiAssistantSchemaV3.GymWorkoutPlan.self })
    }

    func testV3StoreMigratesToV4PreservingAllDataAndEnablingTrainerPlans() async throws {
        let ownerID = "migration.v3v4"
        let storeURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("tai-v3v4-\(UUID().uuidString).sqlite")
        defer {
            try? FileManager.default.removeItem(at: storeURL)
            try? FileManager.default.removeItem(at: storeURL.appendingPathExtension("wal"))
            try? FileManager.default.removeItem(at: storeURL.appendingPathExtension("shm"))
        }

        let mealID = UUID()
        let conversationID = UUID()
        let completedSessionID = UUID()
        let activeSessionID = UUID()
        let legacyPlanID = UUID()
        let starterOverrideID = UUID()

        let v3Container = try AppModelContainerFactory.makeLegacyV3Container(storeURL: storeURL)
        let v3Context = ModelContext(v3Container)

        v3Context.insert(
            MealLog(
                id: mealID,
                ownerID: ownerID,
                eatenAt: .now,
                notes: "Pre-V4 meal"
            )
        )
        v3Context.insert(
            PersistedConversation(
                id: conversationID,
                ownerID: ownerID,
                composerText: "Saved composer draft"
            )
        )

        let completedSession = WorkoutSessionLog(
            id: completedSessionID,
            ownerID: ownerID,
            templateID: GymProgramTemplateID.upperBody.rawValue,
            title: "Upper Body",
            startedAt: .now.addingTimeInterval(-3600),
            completedAt: .now.addingTimeInterval(-1800),
            statusRaw: GymWorkoutSessionStatus.completed.rawValue,
            activeSessionJSON: nil
        )
        let completedSet = WorkoutSetLog(
            exerciseID: GymExerciseID.supineChestPress.rawValue,
            exerciseName: GymExerciseID.supineChestPress.displayName,
            setNumber: 1,
            weightValue: 60,
            weightUnit: "kg",
            repetitions: 10
        )
        completedSet.session = completedSession
        completedSession.sets = [completedSet]
        v3Context.insert(completedSession)

        let activePlan = GymProgramTemplateLibrary.resolvableStarter(.lowerBody)
        let activeSnapshot = GymActiveSession(
            sessionID: activeSessionID,
            planReference: .starter(.lowerBody),
            title: activePlan.title,
            exercises: activePlan.exercises,
            prescription: activePlan.prescription,
            currentExerciseIndex: 1,
            currentSetNumber: 2,
            startedAt: .now.addingTimeInterval(-600),
            status: .inProgress
        )
        let activeJSON = try JSONEncoder().encode(activeSnapshot)
        let activeSession = WorkoutSessionLog(
            id: activeSessionID,
            ownerID: ownerID,
            templateID: GymProgramTemplateID.lowerBody.rawValue,
            title: "Lower Body",
            startedAt: activeSnapshot.startedAt,
            statusRaw: GymWorkoutSessionStatus.inProgress.rawValue,
            activeSessionJSON: activeJSON
        )
        v3Context.insert(activeSession)

        let legacyExercises = GymProgramTemplateLibrary.template(for: .upperBody).exercises
        let legacyPlan = GymWorkoutPlanV3(
            id: legacyPlanID,
            ownerID: ownerID,
            title: "Legacy custom plan",
            starterTemplateID: nil,
            exercisesJSON: try GymPlanPersistenceCodec.encodeExercises(legacyExercises),
            prescriptionJSON: try GymPlanPersistenceCodec.encodePrescription(.default)
        )
        v3Context.insert(legacyPlan)

        let starterOverrideExercises = Array(GymProgramTemplateLibrary.template(for: .lowerBody).exercises.prefix(4))
        let starterOverride = GymWorkoutPlanV3(
            id: starterOverrideID,
            ownerID: ownerID,
            title: "Edited Lower Body",
            starterTemplateID: GymProgramTemplateID.lowerBody.rawValue,
            exercisesJSON: try GymPlanPersistenceCodec.encodeExercises(starterOverrideExercises),
            prescriptionJSON: try GymPlanPersistenceCodec.encodePrescription(.default)
        )
        v3Context.insert(starterOverride)
        try v3Context.save()

        XCTAssertEqual(try v3Context.fetch(FetchDescriptor<GymWorkoutPlanV3>()).count, 2)
        let entityNames = try SwiftDataStoreInspector.entityNames(at: storeURL)
        XCTAssertTrue(entityNames.contains("GymWorkoutPlan"))
        XCTAssertFalse(entityNames.contains("GymWorkoutPlanV3"))

        let migratedContainer = AppModelContainerFactory.makeContainer(inMemory: false, storeURL: storeURL)
        let probe = ModelContext(migratedContainer)

        XCTAssertEqual(try probe.fetch(FetchDescriptor<MealLog>()).count, 1)
        XCTAssertEqual(try probe.fetch(FetchDescriptor<MealLog>()).first?.id, mealID)
        XCTAssertEqual(try probe.fetch(FetchDescriptor<PersistedConversation>()).count, 1)
        XCTAssertEqual(try probe.fetch(FetchDescriptor<PersistedConversation>()).first?.id, conversationID)

        let workoutRepo = LocalSwiftDataWorkoutRepository(container: migratedContainer)
        let bounds = NutritionDay.today().queryBounds()
        let sessions = try await workoutRepo.fetchSessions(
            ownerID: ownerID,
            from: bounds.start.addingTimeInterval(-7200),
            to: bounds.end
        )
        XCTAssertEqual(sessions.count, 2)
        let inProgress = try await workoutRepo.fetchInProgressSession(ownerID: ownerID)
        XCTAssertNotNil(inProgress)

        let gymPlanRepo = LocalSwiftDataGymPlanRepository(container: migratedContainer)
        XCTAssertEqual(gymPlanRepo.fetchTemplateSummaries().count, GymProgramTemplateID.allCases.count)

        let summaries = try await gymPlanRepo.fetchSummaries(ownerID: ownerID)
        XCTAssertEqual(summaries.count, 1)
        XCTAssertEqual(summaries.first { $0.reference == .custom(legacyPlanID) }?.title, "Legacy custom plan")

        let editedStarter = try await gymPlanRepo.loadDraft(reference: .starter(.lowerBody), ownerID: ownerID)
        XCTAssertEqual(editedStarter.title, "Edited Lower Body")
        XCTAssertEqual(editedStarter.exercises.count, 4)

        let legacyLoaded = try await gymPlanRepo.loadDraft(reference: .custom(legacyPlanID), ownerID: ownerID)
        XCTAssertEqual(legacyLoaded.exercises.count, legacyExercises.count)
        XCTAssertEqual(legacyLoaded.lifecycleStatus, .inactive)
        XCTAssertNil(legacyLoaded.importedAt)
        XCTAssertNil(legacyLoaded.sections.first?.prescription)

        let importDraft = try await GymPlanImportService.interpret(
            source: .pastedText(GymTrainerProgramFixture.pastedText),
            aiService: MockAIService()
        )
        var trainerDraft = importDraft.asPlanDraft()
        trainerDraft.importedAt = .now
        let importedReference = try await gymPlanRepo.saveDraft(
            trainerDraft,
            ownerID: ownerID,
            activation: .makeActive
        )

        let library = try await gymPlanRepo.fetchLibrary(ownerID: ownerID)
        XCTAssertEqual(library.activePlan?.reference, importedReference)
        XCTAssertTrue(library.previousPlans.contains { $0.reference == .custom(legacyPlanID) })
        let summaryCountAfterImport = try await gymPlanRepo.fetchSummaries(ownerID: ownerID).count
        XCTAssertEqual(summaryCountAfterImport, 2)

        let upperWorkout = try await gymPlanRepo.resolvePlan(
            reference: importedReference,
            sectionIndex: 0,
            ownerID: ownerID
        )
        XCTAssertEqual(upperWorkout.sectionName, "Upper Body")
        XCTAssertEqual(upperWorkout.exercises.first?.displayName, "Supine Chest Press")

        _ = AppModelContainerFactory.makeContainer(inMemory: false, storeURL: storeURL)
        XCTAssertEqual(try probe.fetch(FetchDescriptor<GymWorkoutPlan>()).count, 3)
        let summariesAfterReopen = try await gymPlanRepo.fetchSummaries(ownerID: ownerID)
        XCTAssertEqual(summariesAfterReopen.count, 2)
        let libraryAfterReopen = try await gymPlanRepo.fetchLibrary(ownerID: ownerID)
        XCTAssertEqual(libraryAfterReopen.activePlan?.reference, importedReference)
    }
}
