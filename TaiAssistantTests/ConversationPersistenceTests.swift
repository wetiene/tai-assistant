import XCTest
import SwiftData
@testable import TaiAssistant

@MainActor
final class ConversationPersistenceTests: XCTestCase {
    private var ownerID: String { "test.user.conversation" }

    override func setUp() {
        super.setUp()
        ConversationAttachmentStore.shared = .makeEphemeralForTests()
    }

    // MARK: - Persistence & restoration

    func testSaveAndLoadPreservesMessagesCardsComposerAndQuickActions() throws {
        let repo = makeSwiftDataRepository()
        let card = MealCardCodec.makeCard(
            payload: MealEstimateCardPayload(
                draft: sampleSnapshot(label: "Oats"),
                refinementAccepted: true,
                isLogged: false
            ),
            interactive: true
        )
        var conversation = ActiveConversation(
            messages: [
                ConversationMessage(actor: .assistant, text: "Hi"),
                ConversationMessage(actor: .user, text: "Oatmeal"),
                ConversationMessage(actor: .assistant, card: card),
            ],
            composer: ConversationComposerState(text: "draft note", pendingPhotoJPEG: Data([0xFF, 0xD8])),
            activity: .capability(
                capabilityID: MealCapabilityID.capability,
                phaseID: MealCapabilityID.Phase.readyToLog.rawValue,
                payload: nil
            ),
            activeQuickActions: [],
            scrollAnchorMessageID: nil
        )
        conversation.scrollAnchorMessageID = conversation.messages.last?.id

        try repo.saveActive(conversation, ownerID: ownerID)
        let loaded = try repo.loadOrCreateActive(ownerID: ownerID)

        XCTAssertEqual(loaded.id, conversation.id)
        XCTAssertEqual(loaded.messages.count, 3)
        XCTAssertEqual(loaded.messages.map(\.id), conversation.messages.map(\.id))
        XCTAssertEqual(loaded.messages[1].text, "Oatmeal")
        XCTAssertEqual(loaded.messages[2].card?.typeID, MealCapabilityID.estimateCardType)
        XCTAssertEqual(loaded.messages[2].card?.isInteractive, true)
        XCTAssertEqual(loaded.composer.text, "draft note")
        XCTAssertEqual(loaded.composer.pendingPhotoJPEG, Data([0xFF, 0xD8]))
        XCTAssertEqual(loaded.activeQuickActions, [])
        XCTAssertEqual(loaded.scrollAnchorMessageID, conversation.messages.last?.id)
        if case let .capability(capabilityID, phaseID, _) = loaded.activity {
            XCTAssertEqual(capabilityID, MealCapabilityID.capability)
            XCTAssertEqual(phaseID, MealCapabilityID.Phase.readyToLog.rawValue)
        } else {
            XCTFail("Expected capability activity")
        }
    }

    func testRestorationDoesNotDuplicateMessages() throws {
        let repo = makeSwiftDataRepository()
        let conversation = ActiveConversation(
            messages: [
                ConversationMessage(actor: .assistant, text: "Hi"),
                ConversationMessage(actor: .user, text: "Hello"),
            ],
            activity: .awaitingUser,
            activeQuickActions: ConversationDefaults.mealQuickActions
        )
        try repo.saveActive(conversation, ownerID: ownerID)
        _ = try repo.loadOrCreateActive(ownerID: ownerID)
        let again = try repo.loadOrCreateActive(ownerID: ownerID)
        XCTAssertEqual(again.messages.count, 2)
        XCTAssertEqual(again.messages.map(\.id), conversation.messages.map(\.id))
    }

    // MARK: - Migration

    func testMigrationCreatesExactlyOneActiveConversationForExistingUser() throws {
        let container = AppModelContainerFactory.makeContainer(inMemory: true)
        // Simulate existing meal Artifact without Conversation.
        let mealContext = ModelContext(container)
        mealContext.insert(MealLog(ownerID: ownerID, eatenAt: .now, notes: "Prior meal"))
        try mealContext.save()

        let repo = LocalSwiftDataActiveConversationRepository(container: container)
        let first = try repo.loadOrCreateActive(ownerID: ownerID)
        let second = try repo.loadOrCreateActive(ownerID: ownerID)

        XCTAssertEqual(first.id, second.id)
        XCTAssertEqual(first.messages.count, 0)

        let probe = ModelContext(container)
        let rows = try probe.fetch(FetchDescriptor<PersistedConversation>())
            .filter { $0.ownerID == ownerID && $0.status == .active }
        XCTAssertEqual(rows.count, 1)
    }

    // MARK: - Interrupted work

    func testInterruptedInterpretationHealsHonestly() throws {
        let repo = InMemoryActiveConversationRepository()
        var conversation = ActiveConversation(
            messages: [
                ConversationMessage(actor: .user, text: "Chicken salad"),
            ],
            activity: .processing(reason: "interpreting_meal"),
            activeQuickActions: []
        )
        try repo.saveActive(conversation, ownerID: ownerID)

        let loaded = try repo.loadOrCreateActive(ownerID: ownerID)
        XCTAssertEqual(loaded.activity, .awaitingUser)
        XCTAssertEqual(loaded.messages.last?.text, ConversationRestoration.interruptedMealInterpretationMessage)
        XCTAssertEqual(loaded.activeQuickActions.count, 3)
        XCTAssertNil(loaded.composer.pendingPhotoJPEG)

        // Second load must not duplicate the interruption notice.
        let again = try repo.loadOrCreateActive(ownerID: ownerID)
        let notices = again.messages.filter {
            $0.text == ConversationRestoration.interruptedMealInterpretationMessage
        }
        XCTAssertEqual(notices.count, 1)
    }

    func testInterruptedSaveHealsWithDistinctCopy() {
        var conversation = ActiveConversation(
            messages: [ConversationMessage(actor: .assistant, text: "Ready to log")],
            activity: .processing(reason: "saving_meal")
        )
        let healed = ConversationRestoration.healInterruptedWork(conversation)
        XCTAssertTrue(healed.didHeal)
        XCTAssertEqual(healed.0.messages.last?.text, ConversationRestoration.interruptedMealSaveMessage)
        XCTAssertEqual(healed.0.activity, .awaitingUser)
    }

    // MARK: - Superseded cards

    func testSupersededCardsRemainInHistoryAcrossPersist() throws {
        let repo = makeSwiftDataRepository()
        let store = ConversationSessionStore()
        store.onPersist = { try? repo.saveActive($0, ownerID: self.ownerID) }

        let firstCard = MealCardCodec.makeCard(
            payload: MealEstimateCardPayload(
                draft: sampleSnapshot(label: "Old estimate"),
                refinementAccepted: false,
                isLogged: false
            ),
            interactive: true
        )
        store.append(ConversationMessage(actor: .assistant, card: firstCard))
        store.freezeInteractiveCards(typeID: MealCapabilityID.estimateCardType)

        let secondCard = MealCardCodec.makeCard(
            payload: MealEstimateCardPayload(
                draft: sampleSnapshot(label: "New estimate"),
                refinementAccepted: false,
                isLogged: false
            ),
            interactive: true
        )
        store.append(ConversationMessage(actor: .assistant, card: secondCard))

        let loaded = try repo.loadOrCreateActive(ownerID: ownerID)
        XCTAssertEqual(loaded.messages.count, 2)
        XCTAssertEqual(loaded.messages[0].card?.isInteractive, false)
        XCTAssertEqual(MealCardCodec.decode(loaded.messages[0].card!.payload)?.draft.label, "Old estimate")
        XCTAssertEqual(loaded.messages[1].card?.isInteractive, true)
        XCTAssertEqual(MealCardCodec.decode(loaded.messages[1].card!.payload)?.draft.label, "New estimate")
    }

    // MARK: - Quick Action state

    func testQuickActionStateSurvivesRestart() throws {
        let repo = makeSwiftDataRepository()
        let actions = ConversationDefaults.mealQuickActions.filter {
            $0.id == MealCapabilityID.QuickAction.takePhoto
                || $0.id == MealCapabilityID.QuickAction.describeMeal
        }
        let conversation = ActiveConversation(
            messages: [ConversationMessage(actor: .assistant, text: "Let’s log a meal.")],
            activity: .capability(
                capabilityID: MealCapabilityID.capability,
                phaseID: MealCapabilityID.Phase.collecting.rawValue,
                payload: nil
            ),
            activeQuickActions: actions
        )
        try repo.saveActive(conversation, ownerID: ownerID)
        let loaded = try repo.loadOrCreateActive(ownerID: ownerID)
        XCTAssertEqual(loaded.activeQuickActions.map(\.id), actions.map(\.id))
    }

    // MARK: - Meal capability restore

    func testMealCapabilityRestoresDraftsFromInteractiveCards() {
        let payload = MealEstimateCardPayload(
            draft: sampleSnapshot(label: "Sushi"),
            refinementAccepted: true,
            isLogged: false
        )
        let conversation = ActiveConversation(
            messages: [
                ConversationMessage(
                    actor: .assistant,
                    card: MealCardCodec.makeCard(payload: payload, interactive: true)
                ),
            ],
            activity: .capability(
                capabilityID: MealCapabilityID.capability,
                phaseID: MealCapabilityID.Phase.readyToLog.rawValue,
                payload: nil
            )
        )
        let meal = MealCapabilityController(
            mealRepository: MockMealRepository(),
            ownerID: ownerID,
            interpreter: MockCheckInInterpreter()
        )
        meal.restoreFromConversation(conversation)
        XCTAssertEqual(meal.phase, .readyToLog)
        XCTAssertEqual(meal.currentDrafts.count, 1)
        XCTAssertEqual(meal.currentDrafts.first?.label, "Sushi")
    }

    // MARK: - Archive-forward transition

    func testArchiveTransitionLeavesPriorThreadAndCreatesFreshActive() throws {
        let repo = InMemoryActiveConversationRepository()
        let original = ActiveConversation(
            messages: [ConversationMessage(actor: .user, text: "Old thread")],
            activity: .awaitingUser
        )
        try repo.saveActive(original, ownerID: ownerID)
        let fresh = try repo.beginArchiveTransition(ownerID: ownerID)
        XCTAssertNotEqual(fresh.id, original.id)
        XCTAssertTrue(fresh.messages.isEmpty)

        let active = try repo.loadOrCreateActive(ownerID: ownerID)
        XCTAssertEqual(active.id, fresh.id)
        XCTAssertTrue(active.messages.isEmpty)
    }

    func testArchiveTransitionOnSwiftDataMarksPriorArchived() throws {
        let container = AppModelContainerFactory.makeContainer(inMemory: true)
        let repo = LocalSwiftDataActiveConversationRepository(container: container)
        let original = ActiveConversation(
            messages: [ConversationMessage(actor: .user, text: "Archive me")],
            activity: .awaitingUser
        )
        try repo.saveActive(original, ownerID: ownerID)
        let fresh = try repo.beginArchiveTransition(ownerID: ownerID)

        let context = ModelContext(container)
        let all = try context.fetch(FetchDescriptor<PersistedConversation>())
            .filter { $0.ownerID == ownerID }
        let actives = all.filter { $0.status == .active }
        let archived = all.filter { $0.status == .archived }
        XCTAssertEqual(actives.count, 1)
        XCTAssertEqual(actives.first?.id, fresh.id)
        XCTAssertEqual(archived.count, 1)
        XCTAssertEqual(archived.first?.id, original.id)
    }

    // MARK: - Attachment externalisation

    func testPhotoAttachmentsAreStoredOutsideMessagesJSON() throws {
        let container = AppModelContainerFactory.makeContainer(inMemory: true)
        let store = ConversationAttachmentStore.makeEphemeralForTests()
        ConversationAttachmentStore.shared = store
        let repo = LocalSwiftDataActiveConversationRepository(container: container, attachmentStore: store)
        let photo = Data(repeating: 0xAB, count: 120_000)
        let attachmentID = UUID()
        let conversation = ActiveConversation(
            messages: [
                ConversationMessage(
                    actor: .user,
                    attachment: ConversationAttachment(id: attachmentID, kind: .photoJPEG(photo))
                )
            ],
            activity: .awaitingUser
        )
        try repo.saveActive(conversation, ownerID: ownerID)

        let loaded = try repo.loadOrCreateActive(ownerID: ownerID)
        XCTAssertEqual(loaded.messages.count, 1)
        guard let attachment = loaded.messages[0].attachment else {
            return XCTFail("Expected attachment")
        }
        guard case .photoJPEGFile = attachment.kind else {
            return XCTFail("Expected file-backed attachment after save/load")
        }
        XCTAssertEqual(attachment.id, attachmentID)
        XCTAssertEqual(try store.load(id: attachmentID)?.count, photo.count)
    }

    func testMessagesJSONDoesNotEmbedLargeJPEGPayload() throws {
        let container = AppModelContainerFactory.makeContainer(inMemory: true)
        let store = ConversationAttachmentStore.makeEphemeralForTests()
        ConversationAttachmentStore.shared = store
        let repo = LocalSwiftDataActiveConversationRepository(container: container, attachmentStore: store)
        let photo = Data(repeating: 0xCD, count: 280_000)
        let conversation = ActiveConversation(
            messages: [
                ConversationMessage(
                    actor: .user,
                    attachment: ConversationAttachment(kind: .photoJPEG(photo))
                )
            ],
            activity: .awaitingUser
        )
        try repo.saveActive(conversation, ownerID: ownerID)
        let row = try fetchActiveRow(container: container)
        XCTAssertLessThan(row.messagesJSON.count, 8_000, "messagesJSON must not embed photo bytes")
        XCTAssertFalse(
            (String(data: row.messagesJSON, encoding: .utf8) ?? "").contains("\"jpegData\"")
        )
        XCTAssertTrue(store.exists(conversation.messages[0].attachment!.id))
    }

    func testLegacyInlineJPEGMigratesToFileOnDecode() throws {
        let store = ConversationAttachmentStore.makeEphemeralForTests()
        let id = UUID()
        let inline = Data(repeating: 0x11, count: 4096)
        let legacyRecord = ConversationAttachmentRecord(
            id: id,
            kind: ConversationAttachmentRecord.photoJPEGKind,
            jpegData: inline,
            storage: nil
        )
        let message = ConversationMessageRecord(
            id: UUID(),
            actor: "user",
            createdAt: .now,
            text: nil,
            attachment: legacyRecord,
            card: nil,
            quickActions: nil
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode([message])

        let decoded = try ConversationSnapshotCodec.decodeMessages(data, attachmentStore: store)
        XCTAssertEqual(decoded.count, 1)
        guard let attachment = decoded[0].attachment else {
            return XCTFail("Expected migrated attachment")
        }
        if case .photoJPEGFile = attachment.kind {
            XCTAssertEqual(try store.load(id: id), inline)
        } else {
            XCTFail("Legacy inline JPEG should migrate to photoJPEGFile")
        }

        let reencoded = try ConversationSnapshotCodec.encodeMessages(decoded, attachmentStore: store)
        let reencodedText = String(data: reencoded, encoding: .utf8) ?? ""
        XCTAssertFalse(reencodedText.contains("\"jpegData\""))
        XCTAssertTrue(reencodedText.contains("\"storage\":\"file\""))
    }

    // MARK: - Regression

    func testComposerDraftSaveDoesNotRewriteMessagesJSON() throws {
        let container = AppModelContainerFactory.makeContainer(inMemory: true)
        let repo = LocalSwiftDataActiveConversationRepository(container: container)
        let conversation = makeConversationWithPhoto()
        try repo.saveActive(conversation, ownerID: ownerID)

        let before = try fetchActiveRow(container: container)
        let beforeMessages = before.messagesJSON

        try repo.saveComposerDraft(
            ConversationComposerState(text: "only-draft", pendingPhotoJPEG: nil),
            ownerID: ownerID
        )

        let after = try fetchActiveRow(container: container)
        XCTAssertEqual(after.messagesJSON, beforeMessages, "Composer-only save must not rewrite messagesJSON")
        XCTAssertEqual(after.composerText, "only-draft")
        XCTAssertNil(after.composerPendingPhotoJPEG)

        let loaded = try repo.loadOrCreateActive(ownerID: ownerID)
        XCTAssertEqual(loaded.composer.text, "only-draft")
        XCTAssertEqual(loaded.messages.count, conversation.messages.count)
    }

    func testPersistedGreetingStartIfNeededDoesNotReseed() throws {
        let repo = InMemoryActiveConversationRepository()
        let store = ConversationSessionStore()
        store.onPersist = { try? repo.saveActive($0, ownerID: self.ownerID) }
        let meal = MealCapabilityController(
            mealRepository: MockMealRepository(),
            ownerID: ownerID,
            interpreter: MockCheckInInterpreter()
        )
        let vm = ConversationViewModel(store: store, meal: meal, gym: ConversationTestSupport.makeGym(), liveTai: ConversationTestSupport.makeLiveTai(), gymPlanRepository: ConversationTestSupport.makeGymPlanRepository(), ownerID: "test.user", assistantName: "Tai")
        vm.startIfNeeded()
        let count = store.active.messages.count
        XCTAssertGreaterThan(count, 0)

        let restored = try repo.loadOrCreateActive(ownerID: ownerID)
        let store2 = ConversationSessionStore(seed: restored)
        let vm2 = ConversationViewModel(store: store2, meal: meal, gym: ConversationTestSupport.makeGym(), liveTai: ConversationTestSupport.makeLiveTai(), gymPlanRepository: ConversationTestSupport.makeGymPlanRepository(), ownerID: "test.user", assistantName: "Tai")
        vm2.startIfNeeded()
        XCTAssertEqual(store2.active.messages.count, count)
    }

    func testConfirmedMealArtifactsRemainIndependentOfConversationPersistence() async throws {
        let mealRepo = MockMealRepository()
        let mealLog = MealLog(ownerID: ownerID, eatenAt: .now, notes: "Confirmed independently")
        mealLog.items = [
            MealItem(
                name: "Eggs",
                amount: 2,
                unit: "each",
                calories: 140,
                proteinGrams: 12,
                carbsGrams: 1,
                fatGrams: 10,
                fiberGrams: 0
            )
        ]
        try await mealRepo.createMealLog(mealLog)

        let conversationRepo = InMemoryActiveConversationRepository()
        try conversationRepo.saveActive(ActiveConversation(), ownerID: ownerID)

        let bounds = Calendar.current.dateInterval(of: .day, for: .now)!
        let meals = try await mealRepo.fetchMealLogs(ownerID: ownerID, from: bounds.start, to: bounds.end)
        XCTAssertTrue(meals.contains(where: { $0.notes == "Confirmed independently" }))

        let conversation = try conversationRepo.loadOrCreateActive(ownerID: ownerID)
        XCTAssertTrue(conversation.messages.isEmpty)

        // Clearing conversation must not erase meal Artifacts.
        try conversationRepo.saveActive(ActiveConversation(), ownerID: ownerID)
        let mealsAfter = try await mealRepo.fetchMealLogs(ownerID: ownerID, from: bounds.start, to: bounds.end)
        XCTAssertTrue(mealsAfter.contains(where: { $0.notes == "Confirmed independently" }))
    }

    // MARK: - Helpers

    private func makeSwiftDataRepository() -> LocalSwiftDataActiveConversationRepository {
        let container = AppModelContainerFactory.makeContainer(inMemory: true)
        return LocalSwiftDataActiveConversationRepository(container: container)
    }

    private func makeConversationWithPhoto() -> ActiveConversation {
        ActiveConversation(
            messages: [
                ConversationMessage(actor: .assistant, text: "Hi"),
                ConversationMessage(
                    actor: .user,
                    attachment: ConversationAttachment(kind: .photoJPEG(Data(repeating: 0xFF, count: 2048)))
                ),
            ],
            activity: .awaitingUser
        )
    }

    private func fetchActiveRow(container: ModelContainer) throws -> PersistedConversation {
        let context = ModelContext(container)
        let rows = try context.fetch(FetchDescriptor<PersistedConversation>())
            .filter { $0.ownerID == ownerID && $0.status == .active }
        return try XCTUnwrap(rows.first)
    }

    private func sampleSnapshot(label: String) -> MealEstimateSnapshot {
        MealEstimateSnapshot(
            draft: CheckInMealDraft(
                id: UUID(),
                label: label,
                timing: .breakfast,
                eatenAt: .now,
                calories: 400,
                proteinGrams: 20,
                carbsGrams: 50,
                fatGrams: 10,
                confidence: 0.8,
                alternatives: [],
                items: []
            )
        )
    }
}
