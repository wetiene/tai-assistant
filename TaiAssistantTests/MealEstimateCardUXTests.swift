import XCTest
@testable import TaiAssistant

@MainActor
final class MealEstimateCardUXTests: XCTestCase {
    private var calendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        return cal
    }

    private var locale: Locale {
        Locale(identifier: "en_GB")
    }

    private var july11Afternoon: Date {
        calendar.date(from: DateComponents(year: 2026, month: 7, day: 11, hour: 14))!
    }

    private var july10Morning: Date {
        calendar.date(from: DateComponents(year: 2026, month: 7, day: 10, hour: 9))!
    }

    private var july9Morning: Date {
        calendar.date(from: DateComponents(year: 2026, month: 7, day: 9, hour: 9))!
    }

    override func setUp() {
        super.setUp()
        ConversationAttachmentStore.shared = .makeEphemeralForTests()
        MealCardPayloadCache.resetForTests()
        AIDataProcessingConsentStore.resetForTests()
        AIDataProcessingConsentStore.accept(version: AIDataProcessingConsentStore.mealAndGoalVersion)
    }

    override func tearDown() {
        AIDataProcessingConsentStore.resetForTests()
        super.tearDown()
    }

    func testMealCardDisplaysTodayLoggingDateLabel() {
        let today = NutritionDay(containing: july11Afternoon, calendar: calendar)
        let label = MealEstimateCardFormatting.loggingDateLabel(
            for: today,
            calendar: calendar,
            now: july11Afternoon,
            locale: locale
        )

        XCTAssertTrue(label.hasPrefix("Today ·"))
        XCTAssertTrue(label.contains("Jul"))
    }

    func testMealCardDisplaysHistoricalLoggingDateLabel() {
        let yesterday = NutritionDay(containing: july10Morning, calendar: calendar)
        let label = MealEstimateCardFormatting.loggingDateLabel(
            for: yesterday,
            calendar: calendar,
            now: july11Afternoon,
            locale: locale
        )

        XCTAssertEqual(label, "Logging for Yesterday · 10 Jul")
    }

    func testChangingLoggingDayUpdatesOnlyTargetDraft() async {
        let calendar = Calendar.current
        let now = Date.now
        let dayA = NutritionDay(containing: calendar.date(byAdding: .day, value: -10, to: now)!)
        let dayB = NutritionDay(containing: calendar.date(byAdding: .day, value: -11, to: now)!)
        let meal = MealCapabilityController(
            mealRepository: MockMealRepository(),
            ownerID: "ux.test",
            interpreter: MockCheckInInterpreter()
        )
        let store = ConversationSessionStore()
        let vm = ConversationViewModel(
            store: store,
            meal: meal,
            gym: ConversationTestSupport.makeGym(),
            strengthConversation: ConversationTestSupport.makeStrengthConversation(ownerID: "ux.test"),
            liveTai: ConversationTestSupport.makeLiveTai(),
            gymPlanRepository: ConversationTestSupport.makeGymPlanRepository(),
            ownerID: "ux.test",
            assistantName: "Tai"
        )

        _ = await meal.interpret(userText: "dinner salmon", photoJPEG: nil, captureNutritionDay: dayA)
        _ = await meal.interpret(userText: "breakfast shake", photoJPEG: nil, captureNutritionDay: dayB)
        XCTAssertEqual(meal.currentDrafts.count, 2)

        let draftA = meal.currentDrafts.first { $0.nutritionDay == dayA }!
        let draftB = meal.currentDrafts.first { $0.nutritionDay == dayB }!

        let payloadA = MealEstimateCardPayload(
            draft: MealEstimateSnapshot(draft: draftA),
            refinementAccepted: false,
            isLogged: false
        )
        let payloadB = MealEstimateCardPayload(
            draft: MealEstimateSnapshot(draft: draftB),
            refinementAccepted: false,
            isLogged: false
        )
        let cardA = MealCardCodec.makeCard(payload: payloadA, interactive: true)
        let cardB = MealCardCodec.makeCard(payload: payloadB, interactive: true)
        store.append(ConversationMessage(actor: .assistant, card: cardA))
        store.append(ConversationMessage(actor: .assistant, card: cardB))

        let targetDate = calendar.date(byAdding: .day, value: -12, to: now)!
        let expectedDay = NutritionDay(containing: targetDate)
        vm.handleMealCardLoggingDayChange(cardID: cardA.id, selectedDate: targetDate)

        let updatedA = MealCardCodec.decode(
            store.active.messages.first { $0.card?.id == cardA.id }!.card!.payload
        )
        let unchangedB = MealCardCodec.decode(
            store.active.messages.first { $0.card?.id == cardB.id }!.card!.payload
        )

        XCTAssertEqual(updatedA?.draft.nutritionDay.start, expectedDay.start)
        XCTAssertEqual(unchangedB?.draft.nutritionDay, dayB)
    }

    func testFutureLoggingDayChangeIsRejected() {
        let today = NutritionDay.today()
        let meal = MealCapabilityController(
            mealRepository: MockMealRepository(),
            ownerID: "ux.test",
            interpreter: MockCheckInInterpreter()
        )
        let store = ConversationSessionStore()
        let vm = ConversationViewModel(
            store: store,
            meal: meal,
            gym: ConversationTestSupport.makeGym(),
            strengthConversation: ConversationTestSupport.makeStrengthConversation(ownerID: "ux.test"),
            liveTai: ConversationTestSupport.makeLiveTai(),
            gymPlanRepository: ConversationTestSupport.makeGymPlanRepository(),
            ownerID: "ux.test",
            assistantName: "Tai"
        )

        let draft = CheckInMealDraft(
            label: "Lunch",
            timing: .lunch,
            eatenAt: .now,
            nutritionDay: today,
            calories: 500,
            proteinGrams: 30,
            carbsGrams: 40,
            fatGrams: 10,
            confidence: 0.9,
            alternatives: [],
            items: [
                CheckInMealItemDraft(
                    id: UUID(),
                    name: "Bowl",
                    amount: 1,
                    unit: "serving",
                    calories: 500,
                    proteinGrams: 30,
                    carbsGrams: 40,
                    fatGrams: 10,
                    fiberGrams: 2
                )
            ]
        )
        meal.syncUnloggedDrafts(from: [
            MealEstimateCardPayload(
                draft: MealEstimateSnapshot(draft: draft),
                refinementAccepted: false,
                isLogged: false
            )
        ])

        let payload = MealEstimateCardPayload(
            draft: MealEstimateSnapshot(draft: draft),
            refinementAccepted: false,
            isLogged: false
        )
        let card = MealCardCodec.makeCard(payload: payload, interactive: true)
        store.append(ConversationMessage(actor: .assistant, card: card))

        let future = Calendar.current.date(byAdding: .day, value: 1, to: Date.now)!
        vm.handleMealCardLoggingDayChange(cardID: card.id, selectedDate: future)

        let decoded = MealCardCodec.decode(store.active.messages.first!.card!.payload)
        XCTAssertEqual(decoded?.draft.nutritionDay.start, today.start)
    }

    func testMultipleDraftsRetainIndependentLoggingDatesOnCards() async {
        let day10 = NutritionDay(containing: july10Morning, calendar: calendar)
        let day9 = NutritionDay(containing: july9Morning, calendar: calendar)
        let meal = MealCapabilityController(
            mealRepository: MockMealRepository(),
            ownerID: "ux.test",
            interpreter: MockCheckInInterpreter()
        )

        _ = await meal.interpret(userText: "dinner salmon", photoJPEG: nil, captureNutritionDay: day10)
        _ = await meal.interpret(userText: "breakfast shake", photoJPEG: nil, captureNutritionDay: day9)

        let labels = meal.currentDrafts.map {
            MealEstimateCardFormatting.loggingDateLabel(
                for: $0.nutritionDay,
                calendar: calendar,
                now: july11Afternoon,
                locale: locale
            )
        }

        XCTAssertEqual(Set(labels).count, 2)
        XCTAssertTrue(labels.contains("Logging for Yesterday · 10 Jul"))
        XCTAssertTrue(labels.contains { $0.contains("9 Jul") })
    }

    func testLooksRightDoesNotAppendDuplicateReadyToLogGuidance() async {
        let store = ConversationSessionStore()
        let meal = MealCapabilityController(
            mealRepository: MockMealRepository(),
            ownerID: "ux.test",
            interpreter: MockCheckInInterpreter()
        )
        let vm = ConversationViewModel(
            store: store,
            meal: meal,
            gym: ConversationTestSupport.makeGym(),
            strengthConversation: ConversationTestSupport.makeStrengthConversation(ownerID: "ux.test"),
            liveTai: ConversationTestSupport.makeLiveTai(),
            gymPlanRepository: ConversationTestSupport.makeGymPlanRepository(),
            ownerID: "ux.test",
            assistantName: "Tai"
        )

        await vm.sendComposerWithTestHooks(text: "lunch bowl", photo: nil)
        let cardID = store.active.messages.last { $0.card != nil }!.card!.id
        let beforeCount = store.active.messages.count

        vm.handleMealCardAction(.looksRight, cardID: cardID)
        vm.handleMealCardAction(.looksRight, cardID: cardID)

        XCTAssertEqual(store.active.messages.count, beforeCount)
        XCTAssertFalse(
            store.active.messages.contains {
                $0.text?.localizedCaseInsensitiveContains("tap Log Meal") == true
            }
        )
    }

    func testRefinementDoesNotRepeatAssistantEstimateMessage() async {
        let store = ConversationSessionStore()
        let meal = MealCapabilityController(
            mealRepository: MockMealRepository(),
            ownerID: "ux.test",
            interpreter: MockCheckInInterpreter()
        )
        let vm = ConversationViewModel(
            store: store,
            meal: meal,
            gym: ConversationTestSupport.makeGym(),
            strengthConversation: ConversationTestSupport.makeStrengthConversation(ownerID: "ux.test"),
            liveTai: ConversationTestSupport.makeLiveTai(),
            gymPlanRepository: ConversationTestSupport.makeGymPlanRepository(),
            ownerID: "ux.test",
            assistantName: "Tai"
        )

        await vm.sendComposerWithTestHooks(text: "dinner steak", photo: nil)
        let cardID = store.active.messages.last { $0.card != nil }!.card!.id
        let estimateMessagesBefore = estimateAssistantMessages(in: store).count

        vm.handleMealCardAction(.changeSomething, cardID: cardID)

        vm.updateComposerText("grilled not fried")
        await vm.sendComposer()

        let estimateMessagesAfter = estimateAssistantMessages(in: store).count
        XCTAssertEqual(estimateMessagesAfter, estimateMessagesBefore)
    }

    func testLogMealEmitsSingleConfirmationMessage() async {
        let repo = RecordingMealRepository()
        let store = ConversationSessionStore()
        let meal = MealCapabilityController(
            mealRepository: repo,
            ownerID: "ux.test",
            interpreter: MockCheckInInterpreter()
        )
        let vm = ConversationViewModel(
            store: store,
            meal: meal,
            gym: ConversationTestSupport.makeGym(),
            strengthConversation: ConversationTestSupport.makeStrengthConversation(ownerID: "ux.test"),
            liveTai: ConversationTestSupport.makeLiveTai(),
            gymPlanRepository: ConversationTestSupport.makeGymPlanRepository(),
            ownerID: "ux.test",
            assistantName: "Tai"
        )

        await vm.sendComposerWithTestHooks(text: "lunch bowl", photo: nil)
        let cardID = store.active.messages.last { $0.card != nil }!.card!.id
        vm.handleMealCardAction(.looksRight, cardID: cardID)
        await vm.confirmLogForTests(cardID: cardID)

        let confirmations = store.active.messages.filter {
            $0.actor == .assistant && $0.text?.localizedCaseInsensitiveContains("Logged") == true
        }
        XCTAssertEqual(confirmations.count, 1)
    }

    private func estimateAssistantMessages(in store: ConversationSessionStore) -> [ConversationMessage] {
        store.active.messages.filter {
            guard $0.actor == .assistant, let text = $0.text else { return false }
            return text.localizedCaseInsensitiveContains("estimate") || text.localizedCaseInsensitiveContains("look right")
        }
    }
}

@MainActor
private extension ConversationViewModel {
    func sendComposerWithTestHooks(text: String, photo: Data?) async {
        store.setActivity(.processing(reason: "interpreting_meal"))
        let outcome = await meal.interpret(userText: text, photoJPEG: photo)
        switch outcome {
        case .failure(let message):
            store.append(ConversationMessage(actor: .assistant, text: message))
        case .imageFailure(let failure):
            store.append(
                ConversationMessage(
                    actor: .assistant,
                    text: ImageInterpretationFailurePresentation.message(for: failure)
                )
            )
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
            store.setActivity(MealCapabilityActivityCodec.makeActivity(phase: .reviewing))
        }
    }

    func confirmLogForTests(cardID: UUID) async {
        guard let message = conversation.messages.first(where: { $0.card?.id == cardID }),
              let card = message.card,
              let payload = MealCardCodec.decode(card.payload)
        else { return }
        await logMealDraft(cardID: cardID, payload: payload)
    }
}
