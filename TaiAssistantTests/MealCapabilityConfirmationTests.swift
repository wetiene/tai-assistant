import XCTest
@testable import TaiAssistant

@MainActor
final class MealCapabilityConfirmationTests: XCTestCase {
    override func setUp() {
        super.setUp()
        UserDefaults.standard.removeObject(forKey: "tai.aiDataProcessingConsent.accepted")
        AIDataProcessingConsentStore.accept()
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: "tai.aiDataProcessingConsent.accepted")
        super.tearDown()
    }

    func testConfirmAndSavePersistsViaMealRepository() async throws {
        let repo = MockMealRepository()
        let meal = MealCapabilityController(
            mealRepository: repo,
            ownerID: "test.user",
            interpreter: MockCheckInInterpreter()
        )

        let outcome = await meal.interpret(userText: "lunch chicken rice", photoJPEG: nil)
        guard case .success(let success) = outcome else {
            return XCTFail("Expected interpretation success")
        }
        XCTAssertFalse(success.drafts.isEmpty)
        XCTAssertEqual(meal.phase, .reviewing)

        meal.markReadyToLog()
        XCTAssertEqual(meal.phase, .readyToLog)

        let result = await meal.confirmAndSave()
        guard case .success(let saved) = result else {
            return XCTFail("Expected save success")
        }
        XCTAssertEqual(saved.count, success.drafts.count)
        XCTAssertEqual(meal.phase, .completed)

        let bounds = Calendar.current.dateInterval(of: .day, for: .now)!
        let logs = try await repo.fetchMealLogs(ownerID: "test.user", from: bounds.start, to: bounds.end)
        XCTAssertEqual(logs.count, saved.count)
        XCTAssertEqual(logs.first?.notes, saved.first?.label)
    }

    func testLooksRightThenLogMealFlowInConversation() async {
        let repo = MockMealRepository()
        let store = ConversationSessionStore()
        let meal = MealCapabilityController(
            mealRepository: repo,
            ownerID: "test.user",
            interpreter: MockCheckInInterpreter()
        )
        let vm = ConversationViewModel(store: store, meal: meal, assistantName: "Tai")
        vm.startIfNeeded()
        await vm.sendComposerWithTestHooks(text: "lunch bowl", photo: nil)

        let cardMessage = store.active.messages.last { $0.card?.typeID == MealCapabilityID.estimateCardType }
        XCTAssertNotNil(cardMessage)
        let cardID = cardMessage!.card!.id

        vm.handleMealCardAction(.looksRight, cardID: cardID)
        let afterLooksRight = MealCardCodec.decode(
            store.active.messages.first { $0.card?.id == cardID }!.card!.payload
        )
        XCTAssertEqual(afterLooksRight?.refinementAccepted, true)
        XCTAssertEqual(afterLooksRight?.showsLogMeal, true)

        await vm.confirmLogForTests(cardID: cardID)

        XCTAssertTrue(store.active.messages.contains { $0.text?.contains("Logged") == true })
        let frozen = store.active.messages.first { $0.card?.id == cardID }
        XCTAssertEqual(frozen?.card?.isInteractive, false)
        XCTAssertEqual(MealCardCodec.decode(frozen!.card!.payload)?.isLogged, true)
    }

    func testChangeSomethingKeepsPriorCardAndDoesNotEnableLogYet() async {
        let store = ConversationSessionStore()
        let meal = MealCapabilityController(
            mealRepository: MockMealRepository(),
            ownerID: "test.user",
            interpreter: MockCheckInInterpreter()
        )
        let vm = ConversationViewModel(store: store, meal: meal, assistantName: "Tai")
        vm.startIfNeeded()
        await vm.sendComposerWithTestHooks(text: "dinner steak", photo: nil)

        let cardID = store.active.messages.last { $0.card != nil }!.card!.id
        vm.handleMealCardAction(.changeSomething, cardID: cardID)

        let payload = MealCardCodec.decode(
            store.active.messages.first { $0.card?.id == cardID }!.card!.payload
        )
        XCTAssertEqual(payload?.refinementAccepted, false)
        XCTAssertEqual(payload?.showsLogMeal, false)
        XCTAssertTrue(store.active.messages.contains { $0.text?.contains("what to change") == true })
    }
}

@MainActor
private extension ConversationViewModel {
    func confirmLogForTests(cardID: UUID) async {
        guard let message = conversation.messages.first(where: { $0.card?.id == cardID }),
              let card = message.card,
              let payload = MealCardCodec.decode(card.payload)
        else { return }
        await confirmLog(cardID: cardID, payload: payload)
    }

    /// Test helper that bypasses the consent sheet and drives send directly.
    func sendComposerWithTestHooks(text: String, photo: Data?) async {
        updateComposerText(text)
        if let photo {
            store.updateComposer { $0.pendingPhotoJPEG = photo }
        }
        // Force consent accepted path via performSend by temporarily setting accepted.
        store.updateComposer {
            $0.text = text
            $0.pendingPhotoJPEG = photo
        }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        store.updateComposer {
            $0.text = ""
            $0.pendingPhotoJPEG = nil
        }
        if let photo {
            store.append(
                ConversationMessage(
                    actor: .user,
                    text: trimmed.isEmpty ? nil : trimmed,
                    attachment: ConversationAttachment(kind: .photoJPEG(photo))
                )
            )
        } else if !trimmed.isEmpty {
            store.append(ConversationMessage(actor: .user, text: trimmed))
        }
        // Use meal controller directly then mirror card append like runInterpretation.
        store.setActivity(.processing(reason: "interpreting_meal"))
        let outcome = await meal.interpret(userText: trimmed, photoJPEG: photo)
        switch outcome {
        case .failure(let message):
            store.append(ConversationMessage(actor: .assistant, text: message))
        case .success(let success):
            store.freezeInteractiveCards(typeID: MealCapabilityID.estimateCardType)
            if let note = success.assistantNote {
                store.append(ConversationMessage(actor: .assistant, text: note))
            }
            for draft in success.drafts {
                let payload = MealEstimateCardPayload(
                    draft: MealEstimateSnapshot(draft: draft),
                    refinementAccepted: false,
                    isLogged: false
                )
                store.append(
                    ConversationMessage(
                        actor: .assistant,
                        card: MealCardCodec.makeCard(payload: payload, interactive: true)
                    )
                )
            }
            store.setActivity(.capability(
                capabilityID: MealCapabilityID.capability,
                phaseID: MealCapabilityID.Phase.reviewing.rawValue,
                payload: nil
            ))
        }
    }
}
