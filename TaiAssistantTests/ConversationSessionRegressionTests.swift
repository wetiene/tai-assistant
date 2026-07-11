import XCTest
@testable import TaiAssistant

@MainActor
final class ConversationSessionRegressionTests: XCTestCase {
    func testEnsureLoadedRunsOncePerSession() async {
        #if DEBUG
        ConversationStartupProbe.resetSession()
        #endif
        let repo = InMemoryActiveConversationRepository()
        let session = ActiveConversationSessionController(
            conversationRepository: repo,
            mealRepository: MockMealRepository(),
            aiService: MockAIService(),
            ownerID: "test.session",
            assistantName: "Tai"
        )

        await session.ensureLoaded()
        await session.ensureLoaded()
        await session.ensureLoaded()

        XCTAssertNotNil(session.viewModel)
        #if DEBUG
        XCTAssertEqual(ConversationStartupProbe.loadOrCreateCount, 1)
        XCTAssertEqual(ConversationStartupProbe.persistDuringBootstrapCount, 0)
        #endif
    }

    func testBootstrapDoesNotPersistOnEveryMutation() async {
        #if DEBUG
        ConversationStartupProbe.resetSession()
        #endif
        let repo = InMemoryActiveConversationRepository()
        try? repo.saveActive(
            ActiveConversation(
                messages: [ConversationMessage(actor: .assistant, text: "Existing")],
                activity: .awaitingUser
            ),
            ownerID: "test.session"
        )
        let session = ActiveConversationSessionController(
            conversationRepository: repo,
            mealRepository: MockMealRepository(),
            aiService: MockAIService(),
            ownerID: "test.session",
            assistantName: "Tai"
        )
        await session.ensureLoaded()

        #if DEBUG
        // Existing conversation: no greeting seed write required.
        XCTAssertEqual(ConversationStartupProbe.persistDuringBootstrapCount, 0)
        XCTAssertLessThanOrEqual(ConversationStartupProbe.persistCallbackCount, 1)
        #endif
        XCTAssertEqual(session.viewModel?.conversation.messages.count, 1)
    }

    func testReopeningSessionDoesNotCreateSecondConversationIdentity() async throws {
        let repo = InMemoryActiveConversationRepository()
        let session = ActiveConversationSessionController(
            conversationRepository: repo,
            mealRepository: MockMealRepository(),
            aiService: MockAIService(),
            ownerID: "test.session",
            assistantName: "Tai"
        )
        await session.ensureLoaded()
        let firstID = try XCTUnwrap(session.viewModel?.conversation.id)
        await session.ensureLoaded()
        XCTAssertEqual(session.viewModel?.conversation.id, firstID)
    }

    func testMealIntentDeliveredOnceDoesNotDuplicatePrompt() async {
        let repo = InMemoryActiveConversationRepository()
        let session = ActiveConversationSessionController(
            conversationRepository: repo,
            mealRepository: MockMealRepository(),
            aiService: MockAIService(),
            ownerID: "test.session",
            assistantName: "Tai"
        )
        await session.ensureLoaded()
        let before = session.viewModel?.conversation.messages.count ?? 0
        session.deliver(.startMealCapture)
        let afterFirst = session.viewModel?.conversation.messages.count ?? 0
        XCTAssertGreaterThan(afterFirst, before)

        // Second identical deliver is a product action; callers must consume intent once.
        // This asserts the session does not auto-replay on ensureLoaded.
        await session.ensureLoaded()
        XCTAssertEqual(session.viewModel?.conversation.messages.count, afterFirst)
    }

    func testComposerUpdateDoesNotSynchronouslyPersistEveryKeystroke() {
        let repo = InMemoryActiveConversationRepository()
        var persistCount = 0
        var composerPersistCount = 0
        let store = ConversationSessionStore()
        store.onPersist = { conversation in
            persistCount += 1
            try? repo.saveActive(conversation, ownerID: "test.session")
        }
        store.onPersistComposer = { draft in
            composerPersistCount += 1
            try? repo.saveComposerDraft(draft, ownerID: "test.session")
        }
        store.updateComposer { $0.text = "a" }
        store.updateComposer { $0.text = "ab" }
        store.updateComposer { $0.text = "abc" }
        XCTAssertEqual(persistCount, 0, "Composer should not trigger full snapshot writes")
        XCTAssertEqual(composerPersistCount, 0, "Composer should debounce disk writes")
        XCTAssertEqual(store.composerDraft.text, "abc")
        XCTAssertEqual(store.active.composer.text, "", "Keystrokes must not mutate active history snapshot")
    }

    func testComposerKeystrokesDoNotMutateActiveMessagesReference() {
        let store = ConversationSessionStore(
            seed: ActiveConversation(
                messages: [ConversationMessage(actor: .assistant, text: "Hi")],
                activity: .awaitingUser
            )
        )
        let beforeIDs = store.active.messages.map(\.id)
        store.updateComposer { $0.text = "typing" }
        XCTAssertEqual(store.active.messages.map(\.id), beforeIDs)
        XCTAssertEqual(store.composerDraft.text, "typing")
    }
}
