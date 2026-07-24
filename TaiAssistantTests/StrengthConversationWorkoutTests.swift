import XCTest
@testable import TaiAssistant

@MainActor
final class StrengthConversationWorkoutTests: XCTestCase {
    private let ownerID = "strength.conversation.test"

    override func setUp() {
        super.setUp()
        ConversationAttachmentStore.shared = .makeEphemeralForTests()
        AIDataProcessingConsentStore.resetForTests()
        AIDataProcessingConsentStore.accept(version: AIDataProcessingConsentStore.gymPhotoVersion)
    }

    override func tearDown() {
        AIDataProcessingConsentStore.resetForTests()
        super.tearDown()
    }

    func testArrivedAtGymIntentClassification() {
        XCTAssertEqual(
            ConversationGymIntentClassifier.classify("I've arrived at the gym"),
            .arrivedAtGym
        )
        XCTAssertEqual(
            ConversationGymIntentClassifier.classify("I'm at the gym"),
            .arrivedAtGym
        )
        XCTAssertEqual(
            ConversationGymIntentClassifier.classify("just got to the gym"),
            .arrivedAtGym
        )
        XCTAssertEqual(
            ConversationGymIntentClassifier.classify("I'm at the gym and only have 20 minutes"),
            .arrivedAtGym
        )
        XCTAssertEqual(
            ConversationGymIntentClassifier.classify("I'll be at the gym later"),
            .general
        )
        XCTAssertEqual(
            ConversationGymIntentClassifier.classify("I wasn't at the gym yesterday"),
            .general
        )
        XCTAssertEqual(
            ConversationGymIntentClassifier.classify("How often am I at the gym?"),
            .general
        )
        XCTAssertEqual(
            ConversationGymIntentClassifier.classify("What should I eat before I go to the gym?"),
            .general
        )
    }

    func testGymArrivalDoesNotAutoAcceptProgressions() async throws {
        let repository = MockWorkoutRepository()
        let strength = StrengthConversationController(
            workoutRepository: repository,
            gymPlanRepository: MockGymPlanRepository(),
            aiService: MockAIService(),
            ownerID: ownerID
        )

        let result = try await strength.startOrResumeFromGymArrival()
        guard case .started(let session) = result else {
            return XCTFail("Expected new session")
        }

        XCTAssertFalse(session.preFlightCompleted)
        XCTAssertTrue(session.acceptedProposals.isEmpty)
        XCTAssertFalse(strength.pendingProgressionProposals().isEmpty)
    }

    func testExplicitProgressionAcceptanceUpdatesPendingSets() async throws {
        let repository = MockWorkoutRepository()
        let strength = StrengthConversationController(
            workoutRepository: repository,
            gymPlanRepository: MockGymPlanRepository(),
            aiService: MockAIService(),
            ownerID: ownerID
        )
        _ = try await strength.startOrResumeFromGymArrival()
        guard let proposal = strength.pendingProgressionProposals().first else {
            return XCTFail("Missing proposal")
        }

        try await strength.acceptProgressionProposal(exerciseID: proposal.exerciseID)
        guard let session = strength.session,
              let exercise = session.exercises.first(where: { $0.exerciseID == proposal.exerciseID })
        else {
            return XCTFail("Missing exercise")
        }

        XCTAssertEqual(session.acceptedProposals[proposal.exerciseID]?.decision, .accepted)
        XCTAssertEqual(exercise.workingSets.first?.suggestedWeight, proposal.proposedWeight ?? proposal.currentWeight)
    }

    func testComposerFixtureBuildsMultiImageRequest() async throws {
        let ai = RecordingGymPhotoAIService()
        let repository = MockWorkoutRepository()
        let store = ConversationSessionStore()
        let (vm, _) = ConversationTestSupport.makeViewModel(
            store: store,
            workoutRepository: repository,
            aiService: ai,
            ownerID: ownerID
        )
        await vm.handleGymArrival()
        vm.appendPendingPhotos(StrengthConversationTestFixtures.multiPhotoEvidence)
        await vm.sendComposer()

        XCTAssertEqual(ai.lastImageCount, 2)
    }

    func testPhotoReviewStoresEvidenceAttachmentReferences() async throws {
        let repository = MockWorkoutRepository()
        let store = ConversationSessionStore()
        let (vm, _) = ConversationTestSupport.makeViewModel(
            store: store,
            workoutRepository: repository,
            ownerID: ownerID
        )
        await vm.handleGymArrival()
        vm.appendPendingPhotos(StrengthConversationTestFixtures.multiPhotoEvidence)
        await vm.sendComposer()

        guard let payload = store.active.messages.compactMap({
            $0.card.flatMap { StrengthPhotoReviewCardCodec.decode($0.payload) }
        }).last else {
            return XCTFail("Missing review payload")
        }

        XCTAssertEqual(payload.photoCount, 2)
        XCTAssertEqual(payload.evidenceAttachmentIDs.count, 2)
        XCTAssertTrue(payload.evidenceAttachmentIDs.allSatisfy {
            ConversationAttachmentStore.shared.exists($0)
        })
    }

    func testPersistenceRoundTripRestoresCardsAndConfirmedHistory() async throws {
        let workoutRepository = MockWorkoutRepository()
        let conversationRepository = InMemoryActiveConversationRepository(
            attachmentStore: ConversationAttachmentStore.shared
        )
        let owner = ownerID

        let sessionController1 = ConversationTestSupport.makeSession(
            conversationRepository: conversationRepository,
            workoutRepository: workoutRepository,
            ownerID: owner
        )
        await sessionController1.ensureLoaded()
        guard let vm1 = sessionController1.viewModel else {
            return XCTFail("Missing view model")
        }

        await vm1.handleGymArrival()
        guard let exerciseInstanceID = vm1.strengthConversation.session?.exercises.first?.id else {
            return XCTFail("Missing exercise")
        }
        try await vm1.strengthConversation.workoutController.selectExercise(
            exerciseInstanceID: exerciseInstanceID
        )
        try await vm1.strengthConversation.confirmSet(
            exerciseInstanceID: exerciseInstanceID,
            weight: 80,
            reps: 10
        )
        if let session = vm1.strengthConversation.session {
            vm1.store.append(
                ConversationMessage(
                    actor: .assistant,
                    card: StrengthExerciseWorkspaceCardCodec.makeCard(
                        payload: StrengthExerciseWorkspaceCardPayload(
                            sessionID: session.sessionID,
                            exerciseInstanceID: exerciseInstanceID
                        ),
                        interactive: true
                    )
                )
            )
        }
        try conversationRepository.saveActive(vm1.store.snapshotIncludingComposer, ownerID: owner)

        let sessionController2 = ConversationTestSupport.makeSession(
            conversationRepository: conversationRepository,
            workoutRepository: workoutRepository,
            ownerID: owner
        )
        await sessionController2.ensureLoaded()
        guard let vm2 = sessionController2.viewModel else {
            return XCTFail("Missing restored view model")
        }

        XCTAssertEqual(
            vm2.strengthConversation.session?.sessionID,
            vm1.strengthConversation.session?.sessionID
        )
        XCTAssertEqual(
            vm2.strengthConversation.session?.exercises.first?.confirmedWorkingSets.count,
            1
        )
        XCTAssertEqual(
            StrengthSessionNavigation.firstUnresolvedSet(
                in: vm2.strengthConversation.session!.exercises.first!
            )?.setNumber,
            2
        )
        XCTAssertTrue(
            vm2.store.active.messages.contains {
                $0.card?.typeID == StrengthConversationCapabilityID.workoutOverviewCardType
            }
        )
    }

    func testSwitchingExercisesDoesNotResolveFirstExercise() async throws {
        let controller = StrengthWorkoutController(
            workoutRepository: MockWorkoutRepository(),
            ownerID: ownerID
        )
        let prepared = controller.prepareSession(
            plan: GymProgramTemplateLibrary.resolvableStarter(.lowerBody),
            proposals: [],
            acceptedProposals: [:],
            historySessions: []
        )
        try await controller.startSession(prepared, activateFirstExercise: false)
        let first = prepared.exercises[0].id
        let second = prepared.exercises[1].id

        try await controller.selectExercise(exerciseInstanceID: first)
        try await controller.confirmCurrentSet(weight: 40, reps: 10)
        try await controller.selectExercise(exerciseInstanceID: second)

        let firstPending = controller.session?.exercises[0].sets.first { $0.status == .pending }
        XCTAssertEqual(firstPending?.setNumber, 2)
        XCTAssertNotEqual(controller.session?.exercises[0].status, .completed)
    }

    func testReturningToFirstExerciseRestoresUnresolvedSet() async throws {
        let controller = StrengthWorkoutController(
            workoutRepository: MockWorkoutRepository(),
            ownerID: ownerID
        )
        let prepared = controller.prepareSession(
            plan: GymProgramTemplateLibrary.resolvableStarter(.lowerBody),
            proposals: [],
            acceptedProposals: [:],
            historySessions: []
        )
        try await controller.startSession(prepared, activateFirstExercise: false)
        let first = prepared.exercises[0].id
        let second = prepared.exercises[1].id

        try await controller.selectExercise(exerciseInstanceID: first)
        try await controller.confirmCurrentSet(weight: 40, reps: 10)
        try await controller.selectExercise(exerciseInstanceID: second)
        try await controller.selectExercise(exerciseInstanceID: first)

        XCTAssertEqual(controller.session?.currentExerciseInstanceID, first)
        XCTAssertEqual(
            StrengthSessionNavigation.firstUnresolvedSet(in: controller.session!.exercises[0])?.setNumber,
            2
        )
    }

    func testDedicatedControllerChangesReflectInConversationSession() async throws {
        let repository = MockWorkoutRepository()
        let strength = StrengthConversationController(
            workoutRepository: repository,
            gymPlanRepository: MockGymPlanRepository(),
            aiService: MockAIService(),
            ownerID: ownerID
        )
        _ = try await strength.startOrResumeFromGymArrival()
        guard let exerciseInstanceID = strength.session?.exercises.first?.id else {
            return XCTFail("Missing exercise")
        }

        try await strength.workoutController.selectExercise(exerciseInstanceID: exerciseInstanceID)
        try await strength.workoutController.confirmCurrentSet(weight: 55, reps: 8)

        XCTAssertEqual(strength.session?.exercises.first?.confirmedWorkingSets.count, 1)
        XCTAssertEqual(
            StrengthSessionNavigation.firstUnresolvedSet(
                in: strength.session!.exercises.first!
            )?.setNumber,
            2
        )
    }

    func testMissingSessionReferenceFailsSafelyInRenderer() async {
        let repository = MockWorkoutRepository()
        let store = ConversationSessionStore()
        let (vm, _) = ConversationTestSupport.makeViewModel(
            store: store,
            workoutRepository: repository,
            ownerID: ownerID
        )
        await vm.handleGymArrival()
        guard let sessionID = vm.strengthConversation.session?.sessionID else {
            return XCTFail("Missing session")
        }

        store.append(
            ConversationMessage(
                actor: .assistant,
                card: StrengthWorkoutOverviewCardCodec.makeCard(
                    payload: StrengthWorkoutOverviewCardPayload(sessionID: UUID()),
                    interactive: true
                )
            )
        )
        try? await vm.strengthConversation.workoutController.abandonWorkout()

        XCTAssertNil(vm.strengthConversation.session)
        XCTAssertNotEqual(vm.strengthConversation.session?.sessionID, sessionID)
    }

    func testArrivedAtGymRoutesToConversationalStart() {
        let route = ConversationRouter.route(
            text: "I've arrived at the gym",
            hasPhoto: false,
            targetedMealDraftID: nil,
            hasActiveGymSession: false,
            hasActiveStrengthConversation: false
        )
        XCTAssertEqual(route, .gymArrivedAtGym)
    }

    func testGymArrivalStartsWorkoutOverviewCard() async {
        let repository = MockWorkoutRepository()
        let store = ConversationSessionStore()
        let (vm, _) = ConversationTestSupport.makeViewModel(
            store: store,
            workoutRepository: repository,
            ownerID: ownerID
        )

        await vm.handleGymArrival()

        XCTAssertTrue(vm.hasActiveStrengthConversation)
        XCTAssertTrue(
            store.active.messages.contains {
                $0.card?.typeID == StrengthConversationCapabilityID.workoutOverviewCardType
            }
        )
        let overviewPayload = store.active.messages.compactMap {
            $0.card.flatMap { StrengthWorkoutOverviewCardCodec.decode($0.payload) }
        }.first
        XCTAssertEqual(overviewPayload?.sessionID, vm.strengthConversation.session?.sessionID)
    }

    func testGymArrivalResumesExistingSessionWithoutDuplicate() async throws {
        let repository = MockWorkoutRepository()
        let controller = StrengthWorkoutController(workoutRepository: repository, ownerID: ownerID)
        let prepared = controller.prepareSession(
            plan: GymProgramTemplateLibrary.resolvableStarter(.upperBody),
            proposals: [],
            acceptedProposals: [:],
            historySessions: [],
            origin: .conversation,
            preFlightCompleted: true
        )
        try await controller.startSession(prepared, activateFirstExercise: false)

        let store = ConversationSessionStore()
        let (vm, _) = ConversationTestSupport.makeViewModel(
            store: store,
            workoutRepository: repository,
            ownerID: ownerID
        )

        await vm.handleGymArrival()

        let inProgress = try await repository.fetchInProgressSession(ownerID: ownerID)
        XCTAssertNotNil(inProgress)
        XCTAssertEqual(vm.strengthConversation.session?.sessionID, prepared.sessionID)
    }

    func testOverviewCardDoesNotAssignExerciseOrder() async {
        let repository = MockWorkoutRepository()
        let store = ConversationSessionStore()
        let (vm, _) = ConversationTestSupport.makeViewModel(
            store: store,
            workoutRepository: repository,
            ownerID: ownerID
        )

        await vm.handleGymArrival()
        guard let session = vm.strengthConversation.session else {
            return XCTFail("Missing session")
        }

        XCTAssertNil(session.currentExerciseInstanceID)
        XCTAssertNil(session.currentSetID)
        XCTAssertTrue(session.exercises.allSatisfy { $0.status == .pending })
    }

    func testMultiPhotoEvidenceReachesInterpretationService() async throws {
        let repository = MockWorkoutRepository()
        let ai = RecordingGymPhotoAIService()
        let store = ConversationSessionStore()
        let (vm, _) = ConversationTestSupport.makeViewModel(
            store: store,
            workoutRepository: repository,
            aiService: ai,
            ownerID: ownerID
        )
        await vm.handleGymArrival()
        vm.appendPendingPhotos([Data("photo-a".utf8), Data("photo-b".utf8)])
        await vm.sendComposer()

        XCTAssertEqual(ai.lastImageCount, 2)
    }

    func testSinglePhotoStillSupported() async throws {
        let ai = RecordingGymPhotoAIService()
        let strength = StrengthConversationController(
            workoutRepository: MockWorkoutRepository(),
            gymPlanRepository: MockGymPlanRepository(),
            aiService: ai,
            ownerID: ownerID
        )
        let session = StrengthSessionBuilder.makeSession(
            plan: GymProgramTemplateLibrary.resolvableStarter(.lowerBody),
            proposals: [],
            acceptedProposals: [:],
            historySessions: [],
            preFlightCompleted: true
        )
        strength.workoutController.loadSession(session)

        _ = try await strength.interpretPhotoEvidence([Data("one".utf8)])
        XCTAssertEqual(ai.lastImageCount, 1)
    }

    func testPhotoReviewDoesNotConfirmSet() async throws {
        let repository = MockWorkoutRepository()
        let ai = RecordingGymPhotoAIService()
        let store = ConversationSessionStore()
        let (vm, _) = ConversationTestSupport.makeViewModel(
            store: store,
            workoutRepository: repository,
            aiService: ai,
            ownerID: ownerID
        )
        await vm.handleGymArrival()

        let beforeSets = vm.strengthConversation.session?.completedWorkingSetCount ?? 0
        vm.appendPendingPhotos([Data("gym-photo".utf8)])
        await vm.sendComposer()

        let reviewCard = store.active.messages.last?.card
        XCTAssertEqual(reviewCard?.typeID, StrengthConversationCapabilityID.photoReviewCardType)
        XCTAssertEqual(vm.strengthConversation.session?.completedWorkingSetCount, beforeSets)
    }

    func testSubmitFixturePhotosForTestingOpensReviewCard() async {
        let repository = MockWorkoutRepository()
        let store = ConversationSessionStore()
        let (vm, _) = ConversationTestSupport.makeViewModel(
            store: store,
            workoutRepository: repository,
            ownerID: ownerID
        )
        await vm.handleGymArrival()
        await vm.submitStrengthFixturePhotosForTesting()

        XCTAssertTrue(
            store.active.messages.contains {
                $0.card?.typeID == StrengthConversationCapabilityID.photoReviewCardType
            }
        )
    }

    func testApplyingPhotoEvidenceOpensExerciseWorkspace() async throws {
        let repository = MockWorkoutRepository()
        let store = ConversationSessionStore()
        let (vm, _) = ConversationTestSupport.makeViewModel(
            store: store,
            workoutRepository: repository,
            ownerID: ownerID
        )
        await vm.beginConversationalStrengthWorkout(
            target: GymPlanWorkoutTarget(reference: .starter(.lowerBody), sectionIndex: 0)
        )
        vm.appendPendingPhotos([Data("gym-photo".utf8)])
        await vm.sendComposer()

        guard let card = store.active.messages.last?.card,
              let payload = StrengthPhotoReviewCardCodec.decode(card.payload)
        else {
            return XCTFail("Missing review card")
        }

        vm.handleStrengthPhotoReviewAction(.applyPhotoReview, cardID: card.id, payload: payload)
        for _ in 0..<30 {
            if store.active.messages.contains(where: {
                $0.card?.typeID == StrengthConversationCapabilityID.exerciseWorkspaceCardType
            }) { break }
            try await Task.sleep(nanoseconds: 50_000_000)
        }

        XCTAssertTrue(
            store.active.messages.contains {
                $0.card?.typeID == StrengthConversationCapabilityID.exerciseWorkspaceCardType
            }
        )
    }

    func testUnmatchedPhotoReviewCanBeDismissedToContinueTraining() async throws {
        let ai = ConfigurableGymPhotoAIService(
            response: AIInterpretGymPhotoResponse(
                schemaVersion: 1,
                exerciseCandidates: [
                    AIInterpretGymExerciseCandidate(
                        exerciseID: "notInTemplate",
                        confidence: 0.91,
                        reason: "Unknown machine label"
                    ),
                ],
                detectedWeight: nil,
                limitations: ["Could not match equipment to the planned workout."],
                requiresConfirmation: true,
                contentType: .gymEquipment,
                classificationConfidence: 0.55,
                classificationReason: "Possible gym equipment, but it does not match the planned workout.",
                containsFood: false,
                containsGymEquipment: true
            )
        )
        let repository = MockWorkoutRepository()
        let store = ConversationSessionStore()
        let (vm, _) = ConversationTestSupport.makeViewModel(
            store: store,
            workoutRepository: repository,
            aiService: ai,
            ownerID: ownerID
        )
        await vm.beginConversationalStrengthWorkout(
            target: GymPlanWorkoutTarget(reference: .starter(.upperBody), sectionIndex: 0)
        )
        vm.appendPendingPhotos([Data("gym-photo".utf8)])
        await vm.sendComposer()

        guard let card = store.active.messages.last(where: {
            $0.card?.typeID == StrengthConversationCapabilityID.photoReviewCardType
        })?.card,
              let payload = StrengthPhotoReviewCardCodec.decode(card.payload)
        else {
            return XCTFail("Missing review card")
        }

        XCTAssertNil(payload.detectedExerciseID, "Unmatched photo should not auto-select an exercise")
        XCTAssertTrue(
            store.active.messages.contains {
                $0.actor == .assistant
                    && ($0.text?.contains("couldn't match") == true
                        || $0.text?.contains("closest option") == true
                        || $0.text?.contains("choose") == true)
            },
            "Assistant should explain the unmatched photo"
        )

        vm.handleStrengthPhotoReviewAction(.dismissPhotoReview, cardID: card.id, payload: payload)

        XCTAssertTrue(vm.hasActiveStrengthConversation)
        XCTAssertTrue(
            store.active.messages.contains {
                $0.card?.typeID == StrengthConversationCapabilityID.workoutOverviewCardType
            },
            "Overview should remain after dismissing unmatched photo review"
        )
        XCTAssertFalse(
            store.active.messages.contains {
                $0.card?.typeID == StrengthConversationCapabilityID.exerciseWorkspaceCardType
            },
            "Dismiss should not open a workspace without a matched exercise"
        )
    }

    func testConfirmSetAdvancesSameWorkspaceCard() async throws {
        let repository = MockWorkoutRepository()
        let controller = StrengthConversationController(
            workoutRepository: repository,
            gymPlanRepository: MockGymPlanRepository(),
            aiService: MockAIService(),
            ownerID: ownerID
        )
        var session = StrengthSessionBuilder.makeSession(
            plan: GymProgramTemplateLibrary.resolvableStarter(.lowerBody),
            proposals: [],
            acceptedProposals: [:],
            historySessions: [],
            preFlightCompleted: true
        )
        let exerciseID = session.exercises[0].id
        try await controller.workoutController.startSession(session, activateFirstExercise: false)
        try await controller.workoutController.selectExercise(exerciseInstanceID: exerciseID)

        try await controller.confirmSet(exerciseInstanceID: exerciseID, weight: 90, reps: 12)
        guard let updated = controller.session,
              let exercise = updated.exercises.first(where: { $0.id == exerciseID })
        else {
            return XCTFail("Missing exercise")
        }

        XCTAssertEqual(exercise.confirmedWorkingSets.count, 1)
        XCTAssertEqual(exercise.workingSets.first?.confirmedWeight, 90)
        XCTAssertEqual(StrengthSessionNavigation.firstUnresolvedSet(in: exercise)?.setNumber, 2)
    }

    func testSetTwoInheritsSetOneValues() async throws {
        let controller = StrengthWorkoutController(
            workoutRepository: MockWorkoutRepository(),
            ownerID: ownerID
        )
        let prepared = controller.prepareSession(
            plan: GymProgramTemplateLibrary.resolvableStarter(.lowerBody),
            proposals: [],
            acceptedProposals: [:],
            historySessions: []
        )
        try await controller.startSession(prepared, activateFirstExercise: false)
        guard let exerciseID = controller.session?.exercises.first?.id else {
            return XCTFail("Missing exercise")
        }
        try await controller.selectExercise(exerciseInstanceID: exerciseID)
        try await controller.confirmCurrentSet(weight: 90, reps: 12)

        let next = controller.session?.exercises.first?.sets.first { $0.setNumber == 2 }
        XCTAssertEqual(next?.suggestedWeight, 90)
        XCTAssertEqual(next?.suggestedReps, 12)
    }

    func testEditingSetTwoDoesNotChangeSetOne() async throws {
        let controller = StrengthWorkoutController(
            workoutRepository: MockWorkoutRepository(),
            ownerID: ownerID
        )
        let prepared = controller.prepareSession(
            plan: GymProgramTemplateLibrary.resolvableStarter(.lowerBody),
            proposals: [],
            acceptedProposals: [:],
            historySessions: []
        )
        try await controller.startSession(prepared, activateFirstExercise: false)
        guard let exerciseID = controller.session?.exercises.first?.id else {
            return XCTFail("Missing exercise")
        }
        try await controller.selectExercise(exerciseInstanceID: exerciseID)
        try await controller.confirmCurrentSet(weight: 90, reps: 12)
        try await controller.applySuggestedValuesToCurrentSet(weight: 95, reps: 10)
        try await controller.confirmCurrentSet(weight: 95, reps: 10)

        let setOne = controller.session?.exercises.first?.sets.first { $0.setNumber == 1 }
        XCTAssertEqual(setOne?.confirmedWeight, 90)
        XCTAssertEqual(setOne?.confirmedReps, 12)
    }

    func testSwitchingExercisesPreservesPriorExerciseState() async throws {
        let controller = StrengthWorkoutController(
            workoutRepository: MockWorkoutRepository(),
            ownerID: ownerID
        )
        let prepared = controller.prepareSession(
            plan: GymProgramTemplateLibrary.resolvableStarter(.lowerBody),
            proposals: [],
            acceptedProposals: [:],
            historySessions: []
        )
        try await controller.startSession(prepared, activateFirstExercise: false)
        let first = prepared.exercises[0].id
        let second = prepared.exercises[1].id

        try await controller.selectExercise(exerciseInstanceID: first)
        try await controller.confirmCurrentSet(weight: 40, reps: 10)
        try await controller.selectExercise(exerciseInstanceID: second)
        try await controller.confirmCurrentSet(weight: 60, reps: 8)
        try await controller.selectExercise(exerciseInstanceID: first)

        let restoredSet = controller.session?.exercises.first?.sets.first { $0.status == .pending }
        XCTAssertEqual(restoredSet?.setNumber, 2)
        XCTAssertEqual(controller.session?.exercises[0].status, .active)
        XCTAssertTrue(
            controller.session?.exercises[1].status == .pending
                || controller.session?.exercises[1].status == .active
        )
    }

    func testFinishStrengthWorkoutCompletesSessionInConversation() async throws {
        let repository = MockWorkoutRepository()
        let store = ConversationSessionStore()
        let (vm, _) = ConversationTestSupport.makeViewModel(
            store: store,
            workoutRepository: repository,
            ownerID: ownerID
        )
        await vm.handleGymArrival()
        guard let sessionID = vm.strengthConversation.session?.sessionID else {
            return XCTFail("Missing session")
        }

        vm.requestStrengthFinish()
        if vm.isStrengthFinishConfirmationPresented {
            await vm.confirmStrengthFinish(skipRemaining: true)
        }
        try await Task.sleep(nanoseconds: 200_000_000)

        XCTAssertFalse(vm.hasActiveStrengthConversation)
        let sessions = try await repository.fetchSessions(
            ownerID: ownerID,
            from: .distantPast,
            to: .distantFuture
        )
        let stored = sessions.first { $0.id == sessionID }
        XCTAssertEqual(stored?.status, .completed)
        XCTAssertTrue(
            store.active.messages.contains { $0.text?.contains("Finished") == true }
        )
    }

    func testFinishWithUnresolvedWorkPromptsBeforeCompleting() async throws {
        let repository = MockWorkoutRepository()
        let store = ConversationSessionStore()
        let (vm, _) = ConversationTestSupport.makeViewModel(
            store: store,
            workoutRepository: repository,
            ownerID: ownerID
        )
        await vm.handleGymArrival()
        XCTAssertTrue(vm.strengthConversation.hasUnresolvedWork)

        vm.requestStrengthFinish()
        XCTAssertTrue(vm.isStrengthFinishConfirmationPresented)
        XCTAssertTrue(vm.hasActiveStrengthConversation)
    }

    func testUpgradeFromDedicatedActiveSessionResumesInConversationWithoutDuplicate() async throws {
        let repository = MockWorkoutRepository()
        var session = StrengthSessionBuilder.makeSession(
            plan: GymProgramTemplateLibrary.resolvableStarter(.upperBody),
            proposals: [],
            acceptedProposals: [:],
            historySessions: [],
            origin: .home,
            preFlightCompleted: true
        )
        session.exercises[0].sets[0].status = .confirmed
        session.exercises[0].sets[0].confirmedWeight = 42.5
        session.exercises[0].sets[0].confirmedReps = 10
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

        let store = ConversationSessionStore()
        let (vm, _) = ConversationTestSupport.makeViewModel(
            store: store,
            workoutRepository: repository,
            ownerID: ownerID
        )
        await vm.resumeConversationalStrengthFromHome()

        XCTAssertEqual(vm.strengthConversation.session?.sessionID, session.sessionID)
        XCTAssertEqual(vm.strengthConversation.session?.exercises[0].sets[0].confirmedWeight, 42.5)
        let inProgress = try await repository.fetchInProgressSession(ownerID: ownerID)
        XCTAssertEqual(inProgress?.id, session.sessionID)
    }

    func testCompletedWorkoutIsNotReopenedAsActive() async throws {
        let repository = MockWorkoutRepository()
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
                statusRaw: GymWorkoutSessionStatus.completed.rawValue,
                activeSessionJSON: nil
            )
        )

        let store = ConversationSessionStore()
        let (vm, _) = ConversationTestSupport.makeViewModel(
            store: store,
            workoutRepository: repository,
            ownerID: ownerID
        )
        await vm.resumeConversationalStrengthFromHome()

        XCTAssertFalse(vm.hasActiveStrengthConversation)
        let inProgress = try await repository.fetchInProgressSession(ownerID: ownerID)
        XCTAssertNil(inProgress)
    }

    func testSmokeHomeStartPathCreatesConversationalOverview() async throws {
        let config = RuntimeAppConfig.uiTestStrengthSmoke
        let container = AppModelContainerFactory.makeContainer(
            inMemory: true,
            includePreviewSeedData: false,
            ownerID: config.localOwnerID
        )
        try PreviewSeedData.seedIfNeeded(in: container, ownerID: config.localOwnerID)
        let dependencies = AppDependencies.live(modelContainer: container, config: config)
        await dependencies.conversationSession.ensureLoaded()

        let library = try await dependencies.gymPlanRepository.fetchLibrary(ownerID: config.localOwnerID)
        let plan = try await StrengthTrainingBriefingBuilder.resolvePlannedWorkout(
            library: library,
            gymPlanRepository: dependencies.gymPlanRepository,
            ownerID: config.localOwnerID
        )
        XCTAssertNotNil(plan)

        guard let viewModel = dependencies.conversationSession.viewModel else {
            return XCTFail("Missing conversation view model")
        }

        await viewModel.beginConversationalStrengthWorkout(
            target: GymPlanWorkoutTarget(reference: plan!.reference, sectionIndex: plan!.sectionIndex),
            entrySource: .home
        )

        XCTAssertTrue(viewModel.hasActiveStrengthConversation)
        XCTAssertTrue(
            viewModel.store.active.messages.contains {
                $0.card?.typeID == StrengthConversationCapabilityID.workoutOverviewCardType
            }
        )
    }

    // MARK: - Gym photo partial evidence

    func testGymPhotoMapperOmitsLowConfidenceWeightButKeepsExercise() {
        let response = AIInterpretGymPhotoResponse(
            schemaVersion: 1,
            exerciseCandidates: [
                AIInterpretGymExerciseCandidate(
                    exerciseID: GymExerciseID.legPress.rawValue,
                    confidence: 0.9,
                    reason: "Leg press stack visible"
                ),
            ],
            detectedWeight: AIInterpretGymDetectedWeight(
                value: 80,
                unit: "kg",
                confidence: 0.2,
                reason: "Pin position unclear"
            ),
            limitations: ["Weight label partially obscured"],
            requiresConfirmation: true
        )

        let interpretation = GymPhotoInterpretationMapper.map(
            response,
            allowedExerciseIDs: [GymExerciseID.legPress.rawValue]
        )
        let exercise = GymPhotoInterpretationMapper.resolveExerciseMatch(from: interpretation)
        let weight = GymPhotoInterpretationMapper.resolveSuggestedWeight(from: interpretation, fallbackUnit: "kg")

        XCTAssertEqual(exercise.detectedExerciseID, GymExerciseID.legPress.rawValue)
        XCTAssertNil(interpretation.detectedWeight)
        XCTAssertNil(weight.value)
    }

    func testGymPhotoMapperTreatsCloseCandidatesAsAmbiguous() {
        let response = AIInterpretGymPhotoResponse(
            schemaVersion: 1,
            exerciseCandidates: [
                AIInterpretGymExerciseCandidate(
                    exerciseID: GymExerciseID.legPress.rawValue,
                    confidence: 0.62,
                    reason: "Could be leg press"
                ),
                AIInterpretGymExerciseCandidate(
                    exerciseID: GymExerciseID.legExtension.rawValue,
                    confidence: 0.58,
                    reason: "Could be leg extension"
                ),
            ],
            detectedWeight: nil,
            limitations: [],
            requiresConfirmation: true
        )

        let interpretation = GymPhotoInterpretationMapper.map(
            response,
            allowedExerciseIDs: [
                GymExerciseID.legPress.rawValue,
                GymExerciseID.legExtension.rawValue,
            ]
        )
        let exercise = GymPhotoInterpretationMapper.resolveExerciseMatch(from: interpretation)

        XCTAssertNil(exercise.detectedExerciseID)
        XCTAssertTrue(exercise.requiresExerciseSelection)
        XCTAssertEqual(exercise.selectableCandidates.count, 2)
    }

    func testExerciseAndWeightIdentifiedOpensWorkspaceWithWeightEvidence() async throws {
        let ai = ConfigurableGymPhotoAIService(
            response: Self.gymPhotoResponse(
                exerciseID: GymExerciseID.legPress.rawValue,
                weight: 90,
                weightConfidence: 0.8
            )
        )
        let store = ConversationSessionStore()
        let (vm, _) = ConversationTestSupport.makeViewModel(
            store: store,
            workoutRepository: MockWorkoutRepository(),
            aiService: ai,
            ownerID: ownerID
        )
        await vm.beginConversationalStrengthWorkout(
            target: GymPlanWorkoutTarget(reference: .starter(.lowerBody), sectionIndex: 0)
        )
        vm.appendPendingPhotos([Data("gym-photo".utf8)])
        await vm.sendComposer()

        guard let card = store.active.messages.last?.card,
              let payload = StrengthPhotoReviewCardCodec.decode(card.payload)
        else {
            return XCTFail("Missing review card")
        }

        XCTAssertEqual(payload.detectedExerciseID, GymExerciseID.legPress.rawValue)
        XCTAssertEqual(payload.suggestedWeight, 90)

        vm.handleStrengthPhotoReviewAction(.applyPhotoReview, cardID: card.id, payload: payload)
        try await Task.sleep(nanoseconds: 200_000_000)

        let workspacePayload = store.active.messages.compactMap {
            $0.card.flatMap { StrengthExerciseWorkspaceCardCodec.decode($0.payload) }
        }.last
        XCTAssertNotNil(workspacePayload)
        let set = vm.strengthConversation.session?.exercises
            .first { $0.id == workspacePayload?.exerciseInstanceID }?
            .sets.first { $0.status == .pending }
        XCTAssertEqual(set?.suggestedWeight, 90)
        XCTAssertEqual(vm.strengthConversation.session?.completedWorkingSetCount, 0)
    }

    func testExerciseIdentifiedWithoutWeightIsNotFailureAndLeavesWeightUnresolved() async throws {
        let ai = ConfigurableGymPhotoAIService(
            response: Self.gymPhotoResponse(
                exerciseID: GymExerciseID.legPress.rawValue,
                weight: nil
            )
        )
        let store = ConversationSessionStore()
        let (vm, _) = ConversationTestSupport.makeViewModel(
            store: store,
            workoutRepository: MockWorkoutRepository(),
            aiService: ai,
            ownerID: ownerID
        )
        await vm.beginConversationalStrengthWorkout(
            target: GymPlanWorkoutTarget(reference: .starter(.lowerBody), sectionIndex: 0)
        )
        vm.appendPendingPhotos([Data("gym-photo".utf8)])
        await vm.sendComposer()

        XCTAssertFalse(
            store.active.messages.contains {
                $0.actor == .assistant && ($0.text?.contains("Could not read those photos") == true)
            }
        )

        guard let card = store.active.messages.last?.card,
              let payload = StrengthPhotoReviewCardCodec.decode(card.payload)
        else {
            return XCTFail("Missing review card")
        }

        XCTAssertEqual(payload.detectedExerciseID, GymExerciseID.legPress.rawValue)
        XCTAssertNil(payload.suggestedWeight)

        vm.handleStrengthPhotoReviewAction(.applyPhotoReview, cardID: card.id, payload: payload)
        try await Task.sleep(nanoseconds: 200_000_000)

        XCTAssertTrue(
            store.active.messages.contains {
                $0.card?.typeID == StrengthConversationCapabilityID.exerciseWorkspaceCardType
            }
        )
        let exercise = vm.strengthConversation.session?.exercises.first {
            $0.exerciseID == GymExerciseID.legPress.rawValue
        }
        let pendingSet = exercise?.sets.first { $0.status == .pending }
        XCTAssertNil(pendingSet?.confirmedWeight)
        XCTAssertNil(pendingSet?.suggestedWeight)
        XCTAssertEqual(vm.strengthConversation.session?.completedWorkingSetCount, 0)
    }

    func testAmbiguousMachineMatchRequiresExplicitExerciseSelection() async throws {
        let ai = ConfigurableGymPhotoAIService(
            response: Self.gymPhotoResponse(
                exerciseID: GymExerciseID.legPress.rawValue,
                alternateExerciseID: GymExerciseID.legExtension.rawValue,
                weight: nil
            )
        )
        let store = ConversationSessionStore()
        let (vm, _) = ConversationTestSupport.makeViewModel(
            store: store,
            workoutRepository: MockWorkoutRepository(),
            aiService: ai,
            ownerID: ownerID
        )
        await vm.beginConversationalStrengthWorkout(
            target: GymPlanWorkoutTarget(reference: .starter(.lowerBody), sectionIndex: 0)
        )
        vm.appendPendingPhotos([Data("gym-photo".utf8)])
        await vm.sendComposer()

        guard let card = store.active.messages.last?.card,
              var payload = StrengthPhotoReviewCardCodec.decode(card.payload)
        else {
            return XCTFail("Missing review card")
        }

        XCTAssertNil(payload.detectedExerciseID)
        XCTAssertEqual(payload.interpretation.exerciseCandidates.count, 2)

        payload.detectedExerciseID = GymExerciseID.legExtension.rawValue
        payload.detectedExerciseName = GymExerciseID.legExtension.displayName
        vm.handleStrengthPhotoReviewAction(.applyPhotoReview, cardID: card.id, payload: payload)
        try await Task.sleep(nanoseconds: 200_000_000)

        XCTAssertEqual(vm.strengthConversation.session?.currentExerciseInstance?.exerciseID, GymExerciseID.legExtension.rawValue)
    }

    func testPartialPhotoReviewRestoresWithoutInventingWeight() async throws {
        let ai = ConfigurableGymPhotoAIService(
            response: Self.gymPhotoResponse(
                exerciseID: GymExerciseID.legPress.rawValue,
                weight: nil
            )
        )
        let workoutRepository = MockWorkoutRepository()
        let conversationRepository = InMemoryActiveConversationRepository(
            attachmentStore: ConversationAttachmentStore.shared
        )
        let owner = ownerID

        let sessionController1 = ConversationTestSupport.makeSession(
            conversationRepository: conversationRepository,
            workoutRepository: workoutRepository,
            aiService: ai,
            ownerID: owner
        )
        await sessionController1.ensureLoaded()
        guard let vm1 = sessionController1.viewModel else {
            return XCTFail("Missing view model")
        }
        await vm1.beginConversationalStrengthWorkout(
            target: GymPlanWorkoutTarget(reference: .starter(.lowerBody), sectionIndex: 0)
        )
        vm1.appendPendingPhotos([Data("gym-photo".utf8)])
        await vm1.sendComposer()

        guard let card = vm1.store.active.messages.last?.card,
              let payload = StrengthPhotoReviewCardCodec.decode(card.payload)
        else {
            return XCTFail("Missing review card")
        }
        vm1.handleStrengthPhotoReviewAction(.applyPhotoReview, cardID: card.id, payload: payload)
        try await Task.sleep(nanoseconds: 200_000_000)
        try conversationRepository.saveActive(vm1.store.snapshotIncludingComposer, ownerID: owner)

        let sessionController2 = ConversationTestSupport.makeSession(
            conversationRepository: conversationRepository,
            workoutRepository: workoutRepository,
            aiService: ai,
            ownerID: owner
        )
        await sessionController2.ensureLoaded()
        guard let vm2 = sessionController2.viewModel else {
            return XCTFail("Missing restored view model")
        }

        let exercise = vm2.strengthConversation.session?.exercises.first {
            $0.exerciseID == GymExerciseID.legPress.rawValue
        }
        let pendingSet = exercise?.sets.first { $0.status == .pending }
        XCTAssertNil(pendingSet?.suggestedWeight)
        XCTAssertNil(pendingSet?.confirmedWeight)
    }

    private static func gymPhotoResponse(
        exerciseID: String,
        alternateExerciseID: String? = nil,
        weight: Double?,
        weightConfidence: Double = 0.8
    ) -> AIInterpretGymPhotoResponse {
        var candidates = [
            AIInterpretGymExerciseCandidate(
                exerciseID: exerciseID,
                confidence: alternateExerciseID == nil ? 0.9 : 0.62,
                reason: "Machine label matches \(exerciseID)"
            ),
        ]
        if let alternateExerciseID {
            candidates.append(
                AIInterpretGymExerciseCandidate(
                    exerciseID: alternateExerciseID,
                    confidence: 0.58,
                    reason: "Alternate machine label"
                )
            )
        }
        return AIInterpretGymPhotoResponse(
            schemaVersion: 1,
            exerciseCandidates: candidates,
            detectedWeight: weight.map {
                AIInterpretGymDetectedWeight(
                    value: $0,
                    unit: "kg",
                    confidence: weightConfidence,
                    reason: "Visible selector"
                )
            },
            limitations: weight == nil ? ["Weight label not visible"] : [],
            requiresConfirmation: true,
            contentType: .gymEquipment,
            classificationConfidence: 0.9,
            classificationReason: "Gym equipment visible in the image.",
            containsFood: false,
            containsGymEquipment: true
        )
    }
}

private final class RecordingGymPhotoAIService: AIService {
    var lastImageCount = 0
    private let base = MockAIService()

    func interpretGymPhoto(request: AIInterpretGymPhotoRequest) async throws -> AIInterpretGymPhotoResponse {
        lastImageCount = request.images?.count ?? (request.image != nil ? 1 : 0)
        return try await base.interpretGymPhoto(request: request)
    }

    func send(message: String, context: [String: String]) async throws -> String {
        try await base.send(message: message, context: context)
    }

    func interpretMeal(request: AIInterpretMealRequest) async throws -> AIInterpretMealResponse {
        try await base.interpretMeal(request: request)
    }

    func coach(request: AICoachRequest) async throws -> AICoachResponse {
        try await base.coach(request: request)
    }

    func interpretGoal(request: AIInterpretGoalRequest) async throws -> AIInterpretGoalResponse {
        try await base.interpretGoal(request: request)
    }

    func interpretWorkoutPlan(request: AIInterpretWorkoutPlanRequest) async throws -> AIInterpretWorkoutPlanResponse {
        try await base.interpretWorkoutPlan(request: request)
    }
}

private final class ConfigurableGymPhotoAIService: AIService {
    var response: AIInterpretGymPhotoResponse
    private let base = MockAIService()

    init(response: AIInterpretGymPhotoResponse) {
        self.response = response
    }

    func interpretGymPhoto(request: AIInterpretGymPhotoRequest) async throws -> AIInterpretGymPhotoResponse {
        response
    }

    func send(message: String, context: [String: String]) async throws -> String {
        try await base.send(message: message, context: context)
    }

    func interpretMeal(request: AIInterpretMealRequest) async throws -> AIInterpretMealResponse {
        try await base.interpretMeal(request: request)
    }

    func coach(request: AICoachRequest) async throws -> AICoachResponse {
        try await base.coach(request: request)
    }

    func interpretGoal(request: AIInterpretGoalRequest) async throws -> AIInterpretGoalResponse {
        try await base.interpretGoal(request: request)
    }

    func interpretWorkoutPlan(request: AIInterpretWorkoutPlanRequest) async throws -> AIInterpretWorkoutPlanResponse {
        try await base.interpretWorkoutPlan(request: request)
    }
}
