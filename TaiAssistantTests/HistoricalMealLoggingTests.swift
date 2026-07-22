import XCTest
@testable import TaiAssistant

@MainActor
final class HistoricalMealLoggingTests: XCTestCase {
    private var calendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        return cal
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
        AIDataProcessingConsentStore.resetForTests()
        AIDataProcessingConsentStore.accept(version: AIDataProcessingConsentStore.mealAndGoalVersion)
    }

    override func tearDown() {
        AIDataProcessingConsentStore.resetForTests()
        super.tearDown()
    }

    func testMealCapabilityStampsHistoricalNutritionDayOnNewDraft() async {
        let pastDay = NutritionDay(containing: july10Morning, calendar: calendar)
        let meal = MealCapabilityController(
            mealRepository: MockMealRepository(),
            ownerID: "historical.log",
            interpreter: MockCheckInInterpreter()
        )

        let outcome = await meal.interpret(
            userText: "dinner salmon",
            photoJPEG: nil,
            captureNutritionDay: pastDay
        )
        guard case .success(let success) = outcome else {
            return XCTFail("Expected interpretation success")
        }

        XCTAssertEqual(success.drafts.count, 1)
        let draft = success.drafts[0]
        XCTAssertEqual(draft.nutritionDay, pastDay)
        XCTAssertTrue(pastDay.contains(draft.eatenAt, calendar: calendar))
        XCTAssertFalse(NutritionDay(containing: july11Afternoon, calendar: calendar).contains(draft.eatenAt, calendar: calendar))
    }

    func testHistoricalMealPersistUsesDraftNutritionDayAndAuditTimestamps() async throws {
        let repo = RecordingMealRepository()
        let pastDay = NutritionDay(containing: july10Morning, calendar: calendar)
        let meal = MealCapabilityController(
            mealRepository: repo,
            ownerID: "historical.log",
            interpreter: MockCheckInInterpreter()
        )

        let beforeSave = Date()
        let outcome = await meal.interpret(
            userText: "lunch bowl",
            photoJPEG: nil,
            captureNutritionDay: pastDay
        )
        guard case .success(let success) = outcome, let draft = success.drafts.first else {
            return XCTFail("Expected interpretation success")
        }

        meal.markReadyToLog()
        let payload = MealEstimateCardPayload(
            draft: MealEstimateSnapshot(draft: draft),
            refinementAccepted: true,
            isLogged: false
        )
        let result = await meal.confirmAndSaveDraft(draftID: draft.id, payload: payload)
        guard case .success = result else {
            return XCTFail("Expected save success")
        }

        XCTAssertEqual(repo.createdMeals.count, 1)
        let saved = try XCTUnwrap(repo.createdMeals.first)
        XCTAssertTrue(pastDay.contains(saved.eatenAt, calendar: calendar))
        XCTAssertGreaterThanOrEqual(saved.createdAt, beforeSave)
        XCTAssertGreaterThanOrEqual(saved.updatedAt, beforeSave)
        XCTAssertTrue(saved.wasRecordedAfterOccurrenceDay(calendar: calendar))
    }

    func testApplyMealIntentWithHistoricalDayContextStartsHistoricalCapturePrompt() {
        let store = ConversationSessionStore()
        let meal = MealCapabilityController(
            mealRepository: MockMealRepository(),
            ownerID: "historical.log",
            interpreter: MockCheckInInterpreter()
        )
        let vm = ConversationViewModel(
            store: store,
            meal: meal,
            liveTai: ConversationTestSupport.makeLiveTai(),
            assistantName: "Tai"
        )

        let pastDay = NutritionDay(containing: july10Morning, calendar: calendar)
        vm.applyMealIntent(dayContext: NutritionDayContext(day: pastDay))

        XCTAssertEqual(vm.nutritionDayContext?.day, pastDay)
        XCTAssertTrue(
            store.active.messages.contains {
                $0.text?.contains("Let’s log a meal for") == true
            }
        )
    }

    func testSessionControllerDeliversHistoricalMealIntentToViewModel() async {
        let repository = InMemoryActiveConversationRepository()
        let session = ConversationTestSupport.makeSession(
            conversationRepository: repository,
            ownerID: "historical.session"
        )
        await session.ensureLoaded()

        let pastDay = NutritionDay(containing: july10Morning, calendar: calendar)
        let intent = TaiLaunchIntent(
            kind: .startMealCapture,
            dayContext: NutritionDayContext(day: pastDay)
        )
        session.deliver(intent)

        XCTAssertEqual(session.viewModel?.nutritionDayContext?.day, pastDay)
    }

    func testMultiplePendingDraftsRetainDistinctNutritionDays() async throws {
        let repo = RecordingMealRepository()
        let day10 = NutritionDay(containing: july10Morning, calendar: calendar)
        let day9 = NutritionDay(containing: july9Morning, calendar: calendar)
        let meal = MealCapabilityController(
            mealRepository: repo,
            ownerID: "historical.log",
            interpreter: MockCheckInInterpreter()
        )

        let first = await meal.interpret(
            userText: "dinner salmon",
            photoJPEG: nil,
            captureNutritionDay: day10
        )
        guard case .success(let firstSuccess) = first, let draft10 = firstSuccess.drafts.first else {
            return XCTFail("Expected first draft")
        }

        let second = await meal.interpret(
            userText: "breakfast shake",
            photoJPEG: nil,
            captureNutritionDay: day9
        )
        guard case .success = second else {
            return XCTFail("Expected second interpretation")
        }
        XCTAssertEqual(meal.currentDrafts.count, 2)

        guard let draft9 = meal.currentDrafts.first(where: { $0.id != draft10.id }) else {
            return XCTFail("Expected second draft")
        }

        XCTAssertEqual(draft10.nutritionDay, day10)
        XCTAssertEqual(draft9.nutritionDay, day9)

        meal.markReadyToLog()
        for draft in [draft10, draft9] {
            let payload = MealEstimateCardPayload(
                draft: MealEstimateSnapshot(draft: draft),
                refinementAccepted: true,
                isLogged: false
            )
            let result = await meal.confirmAndSaveDraft(draftID: draft.id, payload: payload)
            guard case .success = result else {
                return XCTFail("Expected save for \(draft.label)")
            }
        }

        XCTAssertEqual(repo.createdMeals.count, 2)
        XCTAssertTrue(repo.createdMeals.contains { draft10.nutritionDay.contains($0.eatenAt) })
        XCTAssertTrue(repo.createdMeals.contains { draft9.nutritionDay.contains($0.eatenAt) })
    }

    func testRefinementPreservesDraftNutritionDayWhenCaptureDayChanges() async {
        let day10 = NutritionDay(containing: july10Morning, calendar: calendar)
        let day9 = NutritionDay(containing: july9Morning, calendar: calendar)
        let meal = MealCapabilityController(
            mealRepository: MockMealRepository(),
            ownerID: "historical.log",
            interpreter: MockCheckInInterpreter()
        )

        let initial = await meal.interpret(
            userText: "dinner salmon",
            photoJPEG: nil,
            captureNutritionDay: day10
        )
        guard case .success(let initialSuccess) = initial, let draft = initialSuccess.drafts.first else {
            return XCTFail("Expected initial draft")
        }

        let refined = await meal.interpret(
            userText: "grilled not fried",
            photoJPEG: nil,
            targetDraftID: draft.id,
            captureNutritionDay: day9
        )
        guard case .success(let refinedSuccess) = refined, let updated = refinedSuccess.drafts.first else {
            return XCTFail("Expected refined draft")
        }

        XCTAssertEqual(updated.id, draft.id)
        XCTAssertEqual(updated.nutritionDay, day10)
        XCTAssertTrue(day10.contains(updated.eatenAt, calendar: calendar))
    }

    func testHomeContextChangeDoesNotRetargetExistingCardOnConfirm() async throws {
        let repo = RecordingMealRepository()
        let day10 = NutritionDay(containing: july10Morning, calendar: calendar)
        let day9 = NutritionDay(containing: july9Morning, calendar: calendar)
        let meal = MealCapabilityController(
            mealRepository: repo,
            ownerID: "historical.log",
            interpreter: MockCheckInInterpreter()
        )
        let vm = ConversationViewModel(
            store: ConversationSessionStore(),
            meal: meal,
            liveTai: ConversationTestSupport.makeLiveTai(),
            assistantName: "Tai"
        )

        vm.setNutritionDayContext(NutritionDayContext(day: day10))
        let outcome = await meal.interpret(
            userText: "dinner salmon",
            photoJPEG: nil,
            captureNutritionDay: day10
        )
        guard case .success(let success) = outcome, let draft = success.drafts.first else {
            return XCTFail("Expected draft")
        }

        let payload = MealEstimateCardPayload(
            draft: MealEstimateSnapshot(draft: draft),
            refinementAccepted: true,
            isLogged: false
        )

        vm.setNutritionDayContext(NutritionDayContext(day: day9))
        let result = await meal.confirmAndSaveDraft(draftID: draft.id, payload: payload)
        guard case .success = result else {
            return XCTFail("Expected save success")
        }

        let saved = try XCTUnwrap(repo.createdMeals.first)
        XCTAssertTrue(day10.contains(saved.eatenAt, calendar: calendar))
        XCTAssertFalse(day9.contains(saved.eatenAt, calendar: calendar))
    }

    func testMealEstimateSnapshotRoundTripsNutritionDay() {
        let day = NutritionDay(containing: july10Morning, calendar: calendar)
        let draft = CheckInMealDraft(
            label: "Salmon",
            timing: .dinner,
            eatenAt: july10Morning,
            nutritionDay: day,
            calories: 520,
            proteinGrams: 42,
            carbsGrams: 0,
            fatGrams: 28,
            confidence: 0.9,
            alternatives: [],
            items: [
                CheckInMealItemDraft(
                    id: UUID(),
                    name: "Salmon",
                    amount: 1,
                    unit: "fillet",
                    calories: 520,
                    proteinGrams: 42,
                    carbsGrams: 0,
                    fatGrams: 28,
                    fiberGrams: 0
                )
            ]
        )

        let snapshot = MealEstimateSnapshot(draft: draft)
        XCTAssertEqual(snapshot.nutritionDay, day)

        let encoded = MealCardCodec.encode(
            MealEstimateCardPayload(draft: snapshot, refinementAccepted: false, isLogged: false)
        )
        let decoded = MealCardCodec.decode(encoded)
        XCTAssertEqual(decoded?.draft.nutritionDay, day)
        XCTAssertEqual(decoded?.draft.asCheckInDraft().nutritionDay, day)
    }
}
