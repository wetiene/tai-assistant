import XCTest
import SwiftData
@testable import TaiAssistant

@MainActor
final class LiveTaiRoutingTests: XCTestCase {
    override func setUp() {
        super.setUp()
        ConversationAttachmentStore.shared = .makeEphemeralForTests()
        AIDataProcessingConsentStore.resetForTests()
        AIDataProcessingConsentStore.accept(version: AIDataProcessingConsentStore.liveTaiVersion)
    }

    override func tearDown() {
        AIDataProcessingConsentStore.resetForTests()
        super.tearDown()
    }

    func testRouterSendsOrdinaryTextToLiveTaiEvenWithPendingMealCards() {
        let draftID = UUID()
        let route = ConversationRouter.route(
            text: "Can I have dessert tonight?",
            hasPhoto: false,
            targetedMealDraftID: nil,
            isExplicitMealCaptureIntent: false
        )
        XCTAssertEqual(route, .liveTai)
        _ = draftID
    }

    func testRouterUsesExplicitTargetOnly() {
        let draftID = UUID()
        let route = ConversationRouter.route(
            text: "It was a small pizza",
            hasPhoto: false,
            targetedMealDraftID: draftID
        )
        XCTAssertEqual(route, .mealRefine(draftID: draftID))
    }

    func testRouterMealCollectingRoutesToMealInterpret() {
        let route = ConversationRouter.route(
            text: "chicken bowl",
            hasPhoto: false,
            targetedMealDraftID: nil,
            isExplicitMealCaptureIntent: true
        )
        XCTAssertEqual(route, .mealInterpret)
    }

    func testChangeSomethingPersistsTargetedDraftIDAcrossRestore() throws {
        let draftID = UUID()
        let draft = sampleDraft(id: draftID, label: "Oats")
        let card = MealCardCodec.makeCard(
            payload: MealEstimateCardPayload(
                draft: MealEstimateSnapshot(draft: draft),
                refinementAccepted: false,
                isLogged: false
            ),
            interactive: true
        )
        let activity = MealCapabilityActivityCodec.makeActivity(
            phase: .reviewing,
            targetedDraftID: draftID
        )
        let conversation = ActiveConversation(
            messages: [
                ConversationMessage(actor: .assistant, text: "Estimate"),
                ConversationMessage(actor: .assistant, card: card),
            ],
            activity: activity
        )

        let repo = InMemoryActiveConversationRepository()
        try repo.saveActive(conversation, ownerID: "test.user")
        let loaded = try repo.loadOrCreateActive(ownerID: "test.user")

        XCTAssertEqual(
            MealCapabilityActivityCodec.targetedDraftID(from: loaded.activity),
            draftID
        )
        // Restoration must not clear reviewing + target.
        let healed = ConversationRestoration.healInterruptedWork(loaded)
        XCTAssertFalse(healed.didHeal)
        XCTAssertEqual(
            MealCapabilityActivityCodec.targetedDraftID(from: healed.0.activity),
            draftID
        )
    }

    func testOrdinaryQuestionWithPendingCardsRoutesToLiveTaiNotMeal() async {
        let mealRepo = MockMealRepository()
        let store = ConversationSessionStore()
        let (vm, _) = ConversationTestSupport.makeViewModel(
            store: store,
            mealRepository: mealRepo
        )

        // Seed two pending meal cards without a refine target.
        let draftA = sampleDraft(id: UUID(), label: "A")
        let draftB = sampleDraft(id: UUID(), label: "B")
        for draft in [draftA, draftB] {
            store.append(
                ConversationMessage(
                    actor: .assistant,
                    card: MealCardCodec.makeCard(
                        payload: MealEstimateCardPayload(
                            draft: MealEstimateSnapshot(draft: draft),
                            refinementAccepted: false,
                            isLogged: false
                        ),
                        interactive: true
                    )
                )
            )
        }
        store.setActivity(MealCapabilityActivityCodec.makeActivity(phase: .reviewing))
        XCTAssertNil(vm.targetedMealDraftID)

        vm.updateComposerText("How much protein do I have left?")
        await vm.sendComposer()

        // Live Tai path — no new meal estimate cards from this ask.
        let mealCardsAfter = store.active.messages.filter {
            $0.card?.typeID == MealCapabilityID.estimateCardType
        }
        XCTAssertEqual(mealCardsAfter.count, 2)
        XCTAssertTrue(store.active.messages.contains {
            $0.actor == .user && $0.text?.contains("protein") == true
        })
        XCTAssertTrue(store.active.messages.contains {
            $0.actor == .assistant && ($0.text?.isEmpty == false) && $0.card?.typeID != MealCapabilityID.estimateCardType
        })
    }

    func testLiveTaiDoesNotWriteMealArtifacts() async throws {
        let mealRepo = RecordingMealRepository()
        let store = ConversationSessionStore()
        let (vm, _) = ConversationTestSupport.makeViewModel(
            store: store,
            mealRepository: mealRepo
        )
        vm.startIfNeeded()
        vm.updateComposerText("What should I eat for dinner?")
        await vm.sendComposer()

        XCTAssertEqual(mealRepo.createCallCount, 0)
        let bounds = Calendar.current.dateInterval(of: .day, for: .now)!
        let logs = try await mealRepo.fetchMealLogs(ownerID: "test.user", from: bounds.start, to: bounds.end)
        XCTAssertTrue(logs.isEmpty)
    }

    func testRequiresUserDecisionDoesNotMutateArtifacts() async {
        let mealRepo = RecordingMealRepository()
        let ai = ScriptedCoachAIService(
            response: AICoachResponse(
                assistantText: "Consider logging a higher-protein dinner.",
                recommendation: AICoachRecommendation(title: "Log dinner", detail: nil),
                evidence: [],
                confidence: "medium",
                limitations: [],
                quickActions: [],
                requiresUserDecision: true,
                safety: AICoachSafety(state: "ok", reason: nil)
            )
        )
        let store = ConversationSessionStore()
        let (vm, _) = ConversationTestSupport.makeViewModel(
            store: store,
            mealRepository: mealRepo,
            aiService: ai
        )
        vm.updateComposerText("Should I change my dinner?")
        await vm.sendComposer()
        XCTAssertEqual(mealRepo.createCallCount, 0)
        // Disclaimer must not appear in prose; flag may still be in Why payload.
        XCTAssertFalse(store.active.messages.contains {
            $0.text?.localizedCaseInsensitiveContains("won't update your saved data") == true
                || $0.text?.localizedCaseInsensitiveContains("won’t update your saved data") == true
        })
        XCTAssertEqual(vm.latestLiveTaiEvidence?.requiresUserDecision, true)
    }

    func testAssistantTextHygieneStripsInternalAnnotations() {
        let cleaned = LiveTaiResponsePresentation.assistantText(
            from: AICoachResponse(
                assistantText: "[Confirmed today’s totals] You can have pizza. [Meal Memory unavailable; Location context unavailable] I don’t have meal memory, location, or a photo here.",
                limitations: ["Meal Memory unavailable", "No protein target is set yet"],
                requiresUserDecision: true
            )
        )
        XCTAssertFalse(cleaned.contains("["))
        XCTAssertFalse(cleaned.contains("Meal Memory"))
        XCTAssertFalse(cleaned.contains("Location"))
        XCTAssertFalse(cleaned.contains("Confirmed"))
        XCTAssertTrue(cleaned.localizedCaseInsensitiveContains("pizza"))
        let evidence = LiveTaiResponsePresentation.evidencePayload(
            from: AICoachResponse(
                assistantText: "Clean",
                evidence: [AICoachEvidenceItem(kind: "day_progress", label: "Protein", detail: "40g")],
                limitations: ["Meal Memory unavailable", "No protein target is set yet"]
            )
        )
        XCTAssertEqual(evidence?.limitationsShown, ["No protein target is set yet"])
    }

    func testConsentV2RequiredForLiveTaiWhileV1StillAllowsMeal() async {
        AIDataProcessingConsentStore.resetForTests()
        AIDataProcessingConsentStore.accept(version: 1)
        XCTAssertTrue(AIDataProcessingConsentStore.hasAccepted(version: 1))
        XCTAssertFalse(AIDataProcessingConsentStore.hasAccepted(version: 2))

        let store = ConversationSessionStore()
        let (vm, _) = ConversationTestSupport.makeViewModel(store: store)
        vm.updateComposerText("How am I doing today?")
        await vm.sendComposer()
        XCTAssertTrue(vm.needsAIConsent)
        XCTAssertEqual(vm.pendingConsentKind, .liveTai)
        // User message must not be sent until consent accepted.
        XCTAssertFalse(store.active.messages.contains { $0.text == "How am I doing today?" })
    }

    func testLegacyBooleanConsentMigratesToVersion1() {
        AIDataProcessingConsentStore.resetForTests()
        UserDefaults.standard.set(true, forKey: "tai.aiDataProcessingConsent.accepted")
        XCTAssertEqual(AIDataProcessingConsentStore.acceptedVersion, 1)
        XCTAssertFalse(AIDataProcessingConsentStore.hasAccepted(version: 2))
    }

    func testQuickActionAllowlistDropsUnknownIds() {
        let mapped = ConversationQuickActionAllowlist.mapProxyActions([
            AICoachQuickAction(id: "liveTai.why", title: "Why?"),
            AICoachQuickAction(id: "evil.deleteAll", title: "Delete everything"),
            AICoachQuickAction(id: "meal.takePhoto", title: "Hack title"),
        ])
        XCTAssertEqual(mapped.map(\.id), ["liveTai.why", "meal.takePhoto"])
        XCTAssertEqual(mapped.last?.title, "Take Photo")
        let suggestions = ConversationQuickActionAllowlist.nonInteractiveSuggestions(from: [
            AICoachQuickAction(id: "evil.deleteAll", title: "Delete everything"),
        ])
        XCTAssertEqual(suggestions, ["Delete everything"])
    }

    func testLimitationsShownOnlyWhenMaterial() {
        // Limitations must not be concatenated into assistant prose.
        let withMaterial = LiveTaiResponsePresentation.assistantText(
            from: AICoachResponse(
                assistantText: "Protein looks open.",
                limitations: ["No protein target is set yet"]
            )
        )
        XCTAssertEqual(withMaterial, "Protein looks open.")
        XCTAssertFalse(withMaterial.contains("No protein target"))

        let without = LiveTaiResponsePresentation.assistantText(
            from: AICoachResponse(assistantText: "Looks good.", limitations: [])
        )
        XCTAssertFalse(without.contains("HealthKit"))
        XCTAssertFalse(without.contains("Workout"))
    }

    func testAssemblerRunsOffMainActorWithSendableSnapshot() async {
        let snapshot = LiveTaiContextSnapshot(
            capturedAt: .now,
            localeIdentifier: "en_AU",
            timeZoneIdentifier: "Australia/Sydney",
            userAsk: "Protein left?",
            recentTurns: [LiveTaiTurnSnippet(role: .user, text: "Hi")],
            dayNutrition: LiveTaiDayNutritionSnapshot(
                mealCount: 1,
                calories: 500,
                proteinGrams: 40,
                carbsGrams: 40,
                fatGrams: 20,
                calorieTarget: 2000,
                proteinTarget: 160,
                carbsTarget: 200,
                fatTarget: 60
            ),
            mealsToday: [
                LiveTaiMealSnapshot(
                    label: "Lunch",
                    eatenAt: .now,
                    calories: 500,
                    proteinGrams: 40,
                    carbsGrams: 40,
                    fatGrams: 20
                ),
            ],
            goal: LiveTaiGoalSnapshot(
                title: "Recomp",
                calorieTarget: 2000,
                proteinTarget: 160,
                carbsTarget: 200,
                fatTarget: 60
            ),
            capabilityFlags: .p0Defaults,
            knownLimitations: LiveTaiKnownLimitations.defaults
        )
        let assembler = LiveTaiContextAssembler()
        let request = await assembler.assemble(snapshot: snapshot)
        XCTAssertEqual(request.message, "Protein left?")
        XCTAssertEqual(request.context?.limitations.count, LiveTaiKnownLimitations.defaults.count)
        XCTAssertEqual(request.context?.mealsToday.count, 1)
        XCTAssertEqual(request.context?.capabilityFlags?.hasHealthKit, false)
        XCTAssertEqual(request.context?.dayNutrition?.proteinTarget, 160)
    }

    private func sampleDraft(id: UUID, label: String) -> CheckInMealDraft {
        CheckInMealDraft(
            id: id,
            label: label,
            timing: .lunch,
            eatenAt: .now,
            calories: 400,
            proteinGrams: 30,
            carbsGrams: 40,
            fatGrams: 10,
            confidence: 0.8,
            alternatives: [],
            items: [
                CheckInMealItemDraft(
                    id: UUID(),
                    name: "Item",
                    amount: 1,
                    unit: "serving",
                    calories: 400,
                    proteinGrams: 30,
                    carbsGrams: 40,
                    fatGrams: 10,
                    fiberGrams: 2
                ),
            ]
        )
    }
}

/// AI service that returns a scripted coach response; meal/goal still use MockAIService behaviour via forwarding.
private struct ScriptedCoachAIService: AIService {
    let response: AICoachResponse
    private let base = MockAIService()

    func send(message: String, context: [String: String]) async throws -> String {
        try await base.send(message: message, context: context)
    }

    func interpretMeal(request: AIInterpretMealRequest) async throws -> AIInterpretMealResponse {
        try await base.interpretMeal(request: request)
    }

    func interpretGoal(request: AIInterpretGoalRequest) async throws -> AIInterpretGoalResponse {
        try await base.interpretGoal(request: request)
    }

    func interpretGymPhoto(request: AIInterpretGymPhotoRequest) async throws -> AIInterpretGymPhotoResponse {
        try await base.interpretGymPhoto(request: request)
    }

    func interpretWorkoutPlan(request: AIInterpretWorkoutPlanRequest) async throws -> AIInterpretWorkoutPlanResponse {
        try await base.interpretWorkoutPlan(request: request)
    }

    func coach(request: AICoachRequest) async throws -> AICoachResponse {
        response
    }
}
