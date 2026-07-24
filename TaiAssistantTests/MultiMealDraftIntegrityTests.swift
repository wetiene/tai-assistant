import XCTest
@testable import TaiAssistant

/// Records every `createMealLog` for multi-meal integrity assertions.
final class RecordingMealRepository: MealRepository {
    private(set) var createdMeals: [MealLog] = []
    var createCallCount: Int { createdMeals.count }

    func fetchMealLogs(ownerID: String, from startDate: Date, to endDate: Date) async throws -> [MealLog] {
        createdMeals.filter {
            $0.ownerID == ownerID && $0.eatenAt >= startDate && $0.eatenAt < endDate
        }
    }

    func createMealLog(_ meal: MealLog) async throws {
        if createdMeals.contains(where: { $0.id == meal.id }) {
            throw MealRepositoryError.mealLogAlreadyExists(id: meal.id)
        }
        createdMeals.append(meal)
    }

    func updateMealLog(_ meal: MealLog) async throws {
        guard let index = createdMeals.firstIndex(where: { $0.id == meal.id }) else {
            throw MealRepositoryError.mealLogNotFound(id: meal.id)
        }
        createdMeals[index] = meal
    }

    func duplicateMealLog(from source: MealLog, eatenAt: Date) -> MealLog {
        let copy = MealLog(
            ownerID: source.ownerID,
            eatenAt: eatenAt,
            timing: source.timing,
            notes: source.notes
        )
        copy.items = source.items.map {
            MealItem(
                name: $0.name,
                amount: $0.amount,
                unit: $0.unit,
                calories: $0.calories,
                proteinGrams: $0.proteinGrams,
                carbsGrams: $0.carbsGrams,
                fatGrams: $0.fatGrams,
                fiberGrams: $0.fiberGrams
            )
        }
        return copy
    }

    func duplicateMealLog(fromRecurringTemplate template: RecurringMeal, eatenAt: Date) -> MealLog {
        MealLog(ownerID: template.ownerID, eatenAt: eatenAt, notes: template.name)
    }

    func deleteMealLog(id: UUID) async throws {
        createdMeals.removeAll { $0.id == id }
    }
}

@MainActor
final class MultiMealDraftIntegrityTests: XCTestCase {
    override func setUp() {
        super.setUp()
        UserDefaults.standard.removeObject(forKey: "tai.aiDataProcessingConsent.accepted")
        AIDataProcessingConsentStore.accept()
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: "tai.aiDataProcessingConsent.accepted")
        super.tearDown()
    }

    func testLogFirstOfTwoDraftsPersistsOnlyA() async throws {
        let repo = RecordingMealRepository()
        let (store, meal, cardA, cardB, payloadA, _) = makeTwoReadyCards(repo: repo)

        await log(store: store, meal: meal, cardID: cardA, payload: payloadA)

        XCTAssertEqual(repo.createCallCount, 1)
        XCTAssertEqual(repo.createdMeals.first?.notes, "Oats A")
        XCTAssertEqual(itemCalories(repo.createdMeals[0]), 400)

        let cardAAfter = payload(in: store, cardID: cardA)
        let cardBAfter = payload(in: store, cardID: cardB)
        XCTAssertEqual(cardAAfter?.isLogged, true)
        XCTAssertEqual(cardAAfter?.draft.calories, 400)
        XCTAssertEqual(cardBAfter?.isLogged, false)
        XCTAssertEqual(cardBAfter?.draft.calories, 650)
        XCTAssertEqual(cardBAfter?.draft.proteinGrams, 40)
        XCTAssertEqual(cardBAfter?.refinementAccepted, true)
        XCTAssertEqual(cardBAfter?.showsLogMeal, true)

        let messageB = store.active.messages.first { $0.card?.id == cardB }
        XCTAssertEqual(messageB?.card?.isInteractive, true)
    }

    func testThenLogSecondPersistsOnlyBWithOriginalMacros() async throws {
        let repo = RecordingMealRepository()
        let (store, meal, cardA, cardB, payloadA, _) = makeTwoReadyCards(repo: repo)

        await log(store: store, meal: meal, cardID: cardA, payload: payloadA)
        let bPayload = payload(in: store, cardID: cardB)!
        await log(store: store, meal: meal, cardID: cardB, payload: bPayload)

        XCTAssertEqual(repo.createCallCount, 2)
        XCTAssertEqual(repo.createdMeals.map(\.notes), ["Oats A", "Chicken B"])
        XCTAssertEqual(itemCalories(repo.createdMeals[0]), 400)
        XCTAssertEqual(itemCalories(repo.createdMeals[1]), 650)
        XCTAssertFalse(repo.createdMeals.contains { itemCalories($0) == 0 })

        XCTAssertEqual(payload(in: store, cardID: cardA)?.isLogged, true)
        XCTAssertEqual(payload(in: store, cardID: cardB)?.isLogged, true)
    }

    func testLogBBeforeA() async throws {
        let repo = RecordingMealRepository()
        let (store, meal, cardA, cardB, _, payloadB) = makeTwoReadyCards(repo: repo)

        await log(store: store, meal: meal, cardID: cardB, payload: payloadB)
        XCTAssertEqual(repo.createCallCount, 1)
        XCTAssertEqual(repo.createdMeals.first?.notes, "Chicken B")
        XCTAssertEqual(payload(in: store, cardID: cardA)?.isLogged, false)
        XCTAssertEqual(payload(in: store, cardID: cardA)?.showsLogMeal, true)

        let aPayload = payload(in: store, cardID: cardA)!
        await log(store: store, meal: meal, cardID: cardA, payload: aPayload)
        XCTAssertEqual(repo.createCallCount, 2)
        XCTAssertEqual(repo.createdMeals.map(\.notes), ["Chicken B", "Oats A"])
    }

    func testDoubleTapOnACreatesOneArtifact() async {
        let repo = RecordingMealRepository()
        let (store, meal, cardA, _, payloadA, _) = makeTwoReadyCards(repo: repo)

        let vm = ConversationViewModel(store: store, meal: meal, gym: ConversationTestSupport.makeGym(), strengthConversation: ConversationTestSupport.makeStrengthConversation(), liveTai: ConversationTestSupport.makeLiveTai(), gymPlanRepository: ConversationTestSupport.makeGymPlanRepository(), ownerID: "test.user", assistantName: "Tai")
        async let first: Void = vm.logMealDraft(cardID: cardA, payload: payloadA)
        async let second: Void = vm.logMealDraft(cardID: cardA, payload: payloadA)
        _ = await (first, second)

        XCTAssertEqual(repo.createCallCount, 1)
    }

    func testInvalidZeroCaloriePayloadIsRejected() async {
        let repo = RecordingMealRepository()
        let meal = MealCapabilityController(
            mealRepository: repo,
            ownerID: "test.user",
            interpreter: MockCheckInInterpreter()
        )
        let bad = CheckInMealDraft(
            id: UUID(),
            label: "Broken",
            timing: .snack,
            eatenAt: .now,
            calories: 0,
            proteinGrams: 0,
            carbsGrams: 0,
            fatGrams: 0,
            confidence: 0.5,
            alternatives: [],
            items: []
        )
        let payload = MealEstimateCardPayload(
            draft: MealEstimateSnapshot(draft: bad),
            refinementAccepted: true,
            isLogged: false
        )
        let result = await meal.confirmAndSaveDraft(draftID: bad.id, payload: payload)
        guard case .failure(.validationFailed) = result else {
            return XCTFail("Expected validation failure")
        }
        XCTAssertEqual(repo.createCallCount, 0)
    }

    func testEmptyItemsWithNonZeroHeadlineCaloriesRejected() async {
        let repo = RecordingMealRepository()
        let meal = MealCapabilityController(
            mealRepository: repo,
            ownerID: "test.user",
            interpreter: MockCheckInInterpreter()
        )
        let bad = CheckInMealDraft(
            id: UUID(),
            label: "Headline only",
            timing: .lunch,
            eatenAt: .now,
            calories: 500,
            proteinGrams: 30,
            carbsGrams: 40,
            fatGrams: 10,
            confidence: 0.8,
            alternatives: [],
            items: []
        )
        let payload = MealEstimateCardPayload(
            draft: MealEstimateSnapshot(draft: bad),
            refinementAccepted: true,
            isLogged: false
        )
        let result = await meal.confirmAndSaveDraft(draftID: bad.id, payload: payload)
        guard case .failure(.validationFailed) = result else {
            return XCTFail("Expected validation failure for empty items")
        }
        XCTAssertEqual(repo.createCallCount, 0)
    }

    func testStaleDraftIDFailsSafely() async {
        let repo = RecordingMealRepository()
        let (store, meal, cardA, _, payloadA, _) = makeTwoReadyCards(repo: repo)
        let result = await meal.confirmAndSaveDraft(draftID: UUID(), payload: payloadA)
        guard case .failure(.draftMismatch) = result else {
            return XCTFail("Expected draftMismatch, got \(result)")
        }
        XCTAssertEqual(repo.createCallCount, 0)
        XCTAssertEqual(payload(in: store, cardID: cardA)?.isLogged, false)
    }

    func testRefiningOneDraftDoesNotAlterTheOther() {
        let repo = RecordingMealRepository()
        let (store, meal, cardA, cardB, _, payloadB) = makeTwoReadyCards(repo: repo)
        let vm = ConversationViewModel(store: store, meal: meal, gym: ConversationTestSupport.makeGym(), strengthConversation: ConversationTestSupport.makeStrengthConversation(), liveTai: ConversationTestSupport.makeLiveTai(), gymPlanRepository: ConversationTestSupport.makeGymPlanRepository(), ownerID: "test.user", assistantName: "Tai")

        vm.handleMealCardAction(.changeSomething, cardID: cardA)

        let a = payload(in: store, cardID: cardA)
        let b = payload(in: store, cardID: cardB)
        XCTAssertEqual(a?.refinementAccepted, false)
        XCTAssertEqual(b?.refinementAccepted, true)
        XCTAssertEqual(b?.draft.calories, payloadB.draft.calories)
        XCTAssertEqual(b?.draft.label, "Chicken B")
    }

    func testRestoreWithTwoPendingDraftsPreservesBoth() {
        let repo = RecordingMealRepository()
        let (store, meal, _, _, payloadA, payloadB) = makeTwoReadyCards(repo: repo)
        let restored = ActiveConversation(
            id: store.active.id,
            messages: store.active.messages,
            activity: store.active.activity,
            activeQuickActions: [],
            createdAt: store.active.createdAt
        )
        let meal2 = MealCapabilityController(
            mealRepository: repo,
            ownerID: "test.user",
            interpreter: MockCheckInInterpreter()
        )
        meal2.restoreFromConversation(restored)
        XCTAssertEqual(meal2.currentDrafts.count, 2)
        XCTAssertEqual(Set(meal2.currentDrafts.map(\.label)), Set(["Oats A", "Chicken B"]))
        XCTAssertEqual(meal2.currentDrafts.first { $0.label == "Oats A" }?.calories, payloadA.draft.calories)
        XCTAssertEqual(meal2.currentDrafts.first { $0.label == "Chicken B" }?.calories, payloadB.draft.calories)
        _ = meal
    }

    func testRestoreAfterALoggedLeavesBPending() async {
        let repo = RecordingMealRepository()
        let (store, meal, cardA, cardB, payloadA, _) = makeTwoReadyCards(repo: repo)
        await log(store: store, meal: meal, cardID: cardA, payload: payloadA)

        let meal2 = MealCapabilityController(
            mealRepository: RecordingMealRepository(),
            ownerID: "test.user",
            interpreter: MockCheckInInterpreter()
        )
        meal2.restoreFromConversation(store.active)
        XCTAssertEqual(meal2.currentDrafts.count, 1)
        XCTAssertEqual(meal2.currentDrafts.first?.label, "Chicken B")
        XCTAssertTrue(meal2.loggedDraftIDs.contains(payloadA.draft.id))
        XCTAssertEqual(payload(in: store, cardID: cardB)?.isLogged, false)
    }

    // MARK: - Helpers

    private func makeTwoReadyCards(
        repo: RecordingMealRepository
    ) -> (
        ConversationSessionStore,
        MealCapabilityController,
        UUID,
        UUID,
        MealEstimateCardPayload,
        MealEstimateCardPayload
    ) {
        let store = ConversationSessionStore()
        let meal = MealCapabilityController(
            mealRepository: repo,
            ownerID: "test.user",
            interpreter: MockCheckInInterpreter()
        )
        let draftA = makeDraft(
            label: "Oats A",
            calories: 400,
            protein: 20,
            carbs: 50,
            fat: 10,
            itemName: "Oats"
        )
        let draftB = makeDraft(
            label: "Chicken B",
            calories: 650,
            protein: 40,
            carbs: 30,
            fat: 20,
            itemName: "Chicken"
        )
        meal.syncUnloggedDrafts(from: [
            MealEstimateCardPayload(draft: MealEstimateSnapshot(draft: draftA), refinementAccepted: true, isLogged: false),
            MealEstimateCardPayload(draft: MealEstimateSnapshot(draft: draftB), refinementAccepted: true, isLogged: false),
        ])

        let payloadA = MealEstimateCardPayload(
            draft: MealEstimateSnapshot(draft: draftA),
            refinementAccepted: true,
            isLogged: false
        )
        let payloadB = MealEstimateCardPayload(
            draft: MealEstimateSnapshot(draft: draftB),
            refinementAccepted: true,
            isLogged: false
        )
        let cardA = MealCardCodec.makeCard(payload: payloadA, interactive: true)
        let cardB = MealCardCodec.makeCard(payload: payloadB, interactive: true)
        store.append(ConversationMessage(actor: .assistant, card: cardA))
        store.append(ConversationMessage(actor: .assistant, card: cardB))
        return (store, meal, cardA.id, cardB.id, payloadA, payloadB)
    }

    private func makeDraft(
        label: String,
        calories: Int,
        protein: Int,
        carbs: Int,
        fat: Int,
        itemName: String
    ) -> CheckInMealDraft {
        CheckInMealDraft(
            id: UUID(),
            label: label,
            timing: .lunch,
            eatenAt: .now,
            calories: calories,
            proteinGrams: protein,
            carbsGrams: carbs,
            fatGrams: fat,
            confidence: 0.9,
            alternatives: [],
            items: [
                CheckInMealItemDraft(
                    id: UUID(),
                    name: itemName,
                    amount: 1,
                    unit: "serving",
                    calories: calories,
                    proteinGrams: Double(protein),
                    carbsGrams: Double(carbs),
                    fatGrams: Double(fat),
                    fiberGrams: 2
                ),
            ]
        )
    }

    private func log(
        store: ConversationSessionStore,
        meal: MealCapabilityController,
        cardID: UUID,
        payload: MealEstimateCardPayload
    ) async {
        let vm = ConversationViewModel(store: store, meal: meal, gym: ConversationTestSupport.makeGym(), strengthConversation: ConversationTestSupport.makeStrengthConversation(), liveTai: ConversationTestSupport.makeLiveTai(), gymPlanRepository: ConversationTestSupport.makeGymPlanRepository(), ownerID: "test.user", assistantName: "Tai")
        await vm.logMealDraft(cardID: cardID, payload: payload)
    }

    private func payload(in store: ConversationSessionStore, cardID: UUID) -> MealEstimateCardPayload? {
        guard let card = store.active.messages.first(where: { $0.card?.id == cardID })?.card else {
            return nil
        }
        return MealCardCodec.decode(card.payload)
    }

    private func itemCalories(_ meal: MealLog) -> Int {
        meal.items.reduce(0) { $0 + $1.calories }
    }
}
