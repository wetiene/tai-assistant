import Foundation
import Observation
import PhotosUI
import SwiftUI
import UIKit

@MainActor
@Observable
final class ConversationViewModel {
    let store: ConversationSessionStore
    let meal: MealCapabilityController
    let gym: GymCapabilityController
    let strengthConversation: StrengthConversationController
    let liveTai: LiveTaiCapabilityController
    let gymPlanRepository: GymPlanRepository
    let aiService: AIService
    let ownerID: String
    let assistantName: String
    var onMealSaved: (() -> Void)?
    var onWorkoutSaved: (() -> Void)?
    var onManageGymPlans: (() -> Void)?
    var onPresentGymPlanImportReview: ((GymPlanImportDraft, String?) -> Void)?
    var onPresentStrengthWorkout: ((StrengthWorkoutPresentation) -> Void)?
    var strengthWorkoutCoordinator: StrengthWorkoutCoordinator?
    var onRequestStrengthWorkoutStart: ((GymPlanWorkoutTarget, StrengthWorkoutEntrySource) -> Void)?
    var onRequestStrengthWorkoutResume: ((StrengthWorkoutEntrySource) -> Void)?

    var usesShellWorkoutEntryRouting: Bool {
        strengthWorkoutCoordinator != nil && onRequestStrengthWorkoutStart != nil
    }

    private(set) var needsCamera = false
    private(set) var needsGymCamera = false
    private(set) var needsAIConsent = false
    private(set) var pendingConsentKind: AIDataProcessingConsentKind = .mealAndGoal
    private var pendingAfterConsent: (() -> Void)?

    /// Last Live Tai ask retained for Retry without duplicating the user turn.
    private(set) var pendingLiveTaiRetryAsk: String?
    /// Selected nutrition day for historical meal logging (from Home launch context).
    private(set) var nutritionDayContext: NutritionDayContext?
    /// Original text awaiting clarify → Log meal / Ask about it (no duplicate user turn).
    private(set) var pendingClarificationText: String?
    /// Evidence for the most recent Live Tai reply (Why sheet).
    private(set) var latestLiveTaiEvidence: LiveTaiEvidencePayload?
    var showLiveTaiWhy = false
    var pendingWorkoutStartConflict: GymWorkoutStartConflict?
    var isWorkoutStartConflictDialogPresented = false
    var pendingWorkoutDiscardConfirmation = false
    private(set) var isResolvingWorkoutStartConflict = false
    var isStrengthFinishConfirmationPresented = false
    private(set) var isFinishingStrengthWorkout = false

    private var isStartingWorkout = false
    private var isHandlingGymArrival = false

    var strengthFinishConfirmationMessage: String {
        let pending = strengthConversation.unresolvedSetCount
        if pending == 1 {
            return "1 set is still unresolved. You can keep training or finish and mark the remaining work as skipped."
        }
        return "\(pending) sets are still unresolved. You can keep training or finish and mark the remaining work as skipped."
    }

    var conversation: ActiveConversation { store.snapshotIncludingComposer }
    var composer: ConversationComposerState { store.composerDraft }
    var errorMessage: String?
    var isProcessing: Bool {
        if case .processing = store.active.activity { return true }
        return meal.isBusy || gym.isBusy || strengthConversation.isBusy
    }

    var hasActiveStrengthConversation: Bool {
        strengthConversation.hasActiveSession
    }

    /// Durable targeted meal refinement draft ID (restored from activity payload).
    var targetedMealDraftID: UUID? {
        MealCapabilityActivityCodec.targetedDraftID(from: store.active.activity)
    }

    static let defaultQuickActions: [ConversationQuickAction] = ConversationDefaults.mealQuickActions

    init(
        store: ConversationSessionStore,
        meal: MealCapabilityController,
        gym: GymCapabilityController,
        strengthConversation: StrengthConversationController,
        liveTai: LiveTaiCapabilityController,
        gymPlanRepository: GymPlanRepository,
        aiService: AIService = MockAIService(),
        ownerID: String,
        assistantName: String,
        onMealSaved: (() -> Void)? = nil,
        onWorkoutSaved: (() -> Void)? = nil,
        onManageGymPlans: (() -> Void)? = nil,
        onPresentGymPlanImportReview: ((GymPlanImportDraft, String?) -> Void)? = nil,
        onPresentStrengthWorkout: ((StrengthWorkoutPresentation) -> Void)? = nil,
        strengthWorkoutCoordinator: StrengthWorkoutCoordinator? = nil
    ) {
        self.store = store
        self.meal = meal
        self.gym = gym
        self.strengthConversation = strengthConversation
        self.liveTai = liveTai
        self.gymPlanRepository = gymPlanRepository
        self.aiService = aiService
        self.ownerID = ownerID
        self.assistantName = assistantName
        self.onMealSaved = onMealSaved
        self.onWorkoutSaved = onWorkoutSaved
        self.onManageGymPlans = onManageGymPlans
        self.onPresentGymPlanImportReview = onPresentGymPlanImportReview
        self.onPresentStrengthWorkout = onPresentStrengthWorkout
        self.strengthWorkoutCoordinator = strengthWorkoutCoordinator
    }

    func startIfNeeded() {
        guard store.active.messages.isEmpty else { return }
        seedGreeting()
    }

    func setNutritionDayContext(_ context: NutritionDayContext?) {
        nutritionDayContext = context
    }

    /// Deep-link from Home: open Tai ready for meal logging.
    func applyMealIntent(dayContext: NutritionDayContext? = nil) {
        if let dayContext {
            setNutritionDayContext(dayContext)
        }
        startIfNeeded()
        clearTargetedMealRefinement()
        meal.beginCollecting()
        store.setActivity(MealCapabilityActivityCodec.makeActivity(phase: .collecting))
        store.append(
            ConversationMessage(
                actor: .assistant,
                text: Self.mealCapturePrompt(for: nutritionDayContext)
            )
        )
        store.setQuickActions(Self.defaultQuickActions.filter {
            $0.id == MealCapabilityID.QuickAction.takePhoto
                || $0.id == MealCapabilityID.QuickAction.describeMeal
        })
    }

    func applyGymIntent(
        planReference: GymPlanReference? = nil,
        workoutTarget: GymPlanWorkoutTarget? = nil,
        resume: Bool = false,
        openImport: Bool = false
    ) {
        startIfNeeded()
        if openImport {
            onManageGymPlans?()
            store.append(
                ConversationMessage(
                    actor: .assistant,
                    text: "Open Gym Plans and choose Import Trainer Plan to paste or upload your program. Nothing is saved until you review and tap Save Plan."
                )
            )
            return
        }
        if resume {
            Task { await resumeStrengthWorkoutFromConversation() }
            return
        }
        if let workoutTarget {
            Task { await requestStartGymWorkout(target: workoutTarget) }
        } else if let planReference {
            Task {
                await requestStartGymWorkout(
                    target: GymPlanWorkoutTarget(reference: planReference, sectionIndex: 0)
                )
            }
        } else {
            store.append(
                ConversationMessage(
                    actor: .assistant,
                    text: "Import your trainer’s program from Gym Plans, or paste it here for review. Nothing is saved until you tap Save Plan.",
                    quickActions: ConversationDefaults.gymStartQuickActions
                )
            )
            store.setQuickActions(ConversationDefaults.gymStartQuickActions)
        }
    }

    func handleQuickAction(_ action: ConversationQuickAction) {
        if action.id == "strength.uitest.fixturePhotos" {
            Task { await submitStrengthFixturePhotosForTesting() }
            return
        }

        guard let allowed = ConversationAllowedQuickAction.resolve(action.id) else {
            // Unknown / non-allowlisted ids never drive behaviour.
            return
        }

        switch allowed {
        case .mealTakePhoto:
            requestConsent(.mealAndGoal) {
                self.clearTargetedMealRefinement()
                self.meal.beginCollecting()
                self.needsCamera = true
            }
        case .mealDescribeMeal:
            clearTargetedMealRefinement()
            meal.beginCollecting()
            store.setActivity(MealCapabilityActivityCodec.makeActivity(phase: .collecting))
            store.append(
                ConversationMessage(
                    actor: .assistant,
                    text: "What did you have? A short description is enough."
                )
            )
            store.setQuickActions([])
        case .mealAskTai:
            store.append(ConversationMessage(actor: .user, text: "Ask Tai"))
            store.append(
                ConversationMessage(
                    actor: .assistant,
                    text: "Ask me anything about today’s meals or goals — for example protein left, dinner ideas, or how today compares."
                )
            )
            store.setQuickActions(Self.defaultQuickActions)
        case .mealCancelRefine:
            cancelTargetedMealRefinement()
        case .mealLogIt:
            Task { await resolveClarificationLogMeal() }
        case .liveTaiAskAboutIt:
            Task { await resolveClarificationAskAboutIt() }
        case .liveTaiRetry:
            Task { await retryLiveTai() }
        case .liveTaiWhy:
            if latestLiveTaiEvidence != nil {
                showLiveTaiWhy = true
            }
        case .gymStartUpperBody:
            Task { await requestStartGymWorkout(planReference: .starter(.upperBody)) }
        case .gymStartLowerBody:
            Task { await requestStartGymWorkout(planReference: .starter(.lowerBody)) }
        case .gymManagePlans:
            onManageGymPlans?()
        case .gymTakeSetPhoto:
            requestConsent(.gymPhoto) {
                self.needsGymCamera = true
            }
        case .gymFinishWorkout:
            requestStrengthFinish()
        case .gymResumeWorkout:
            Task { await resumeConversationalStrengthInThread() }
        }
    }

    func dismissGymCameraRequest() {
        needsGymCamera = false
    }

    func dismissCameraRequest() {
        needsCamera = false
    }

    func handleCapturedPhoto(_ jpeg: Data) {
        needsCamera = false
        requestConsent(.mealAndGoal) {
            Task { await self.sendPhotoAndInterpret(jpeg) }
        }
    }

    func handleGymCapturedPhoto(_ jpeg: Data) {
        needsGymCamera = false
        requestConsent(.gymPhoto) {
            if self.hasActiveStrengthConversation {
                self.appendPendingPhotos([jpeg])
            } else {
                Task { await self.interpretGymSetPhoto(jpeg) }
            }
        }
    }

    func updateComposerText(_ text: String) {
        store.updateComposer { $0.text = text }
    }

    func clearPendingPhoto() {
        store.updateComposer {
            $0.pendingPhotoJPEG = nil
            $0.pendingPhotoJPEGs = []
        }
    }

    func removePendingPhoto(at index: Int) {
        store.updateComposer { composer in
            if !composer.pendingPhotoJPEGs.isEmpty {
                guard composer.pendingPhotoJPEGs.indices.contains(index) else { return }
                composer.pendingPhotoJPEGs.remove(at: index)
            } else if index == 0 {
                composer.pendingPhotoJPEG = nil
            }
        }
    }

    func appendPendingPhotos(_ photos: [Data]) {
        guard !photos.isEmpty else { return }
        store.updateComposer { composer in
            if composer.pendingPhotoJPEGs.isEmpty, let single = composer.pendingPhotoJPEG {
                composer.pendingPhotoJPEGs = [single]
                composer.pendingPhotoJPEG = nil
            }
            composer.pendingPhotoJPEGs.append(contentsOf: photos)
        }
    }

    func importLibraryPhotos(_ items: [PhotosPickerItem]) async {
        var photos: [Data] = []
        for item in items {
            if let data = try? await item.loadTransferable(type: Data.self),
               let prepared = CheckInPhotoUploadPreprocessor.prepareMealUploadJPEG(from: UIImage(data: data) ?? UIImage()) {
                photos.append(prepared)
            }
        }
        guard !photos.isEmpty else {
            errorMessage = "Could not load selected photos."
            return
        }
        appendPendingPhotos(photos)
    }

    func sendComposer() async {
        let text = store.composerDraft.text.trimmingCharacters(in: .whitespacesAndNewlines)
        let photos = store.composerDraft.resolvedPendingPhotos
        let hasPhoto = !photos.isEmpty
        guard !text.isEmpty || hasPhoto else { return }

        if !hasPhoto,
           let correction = ImageDomainCorrectionClassifier.detect(in: text)
        {
            store.append(ConversationMessage(actor: .user, text: text))
            store.updateComposer { $0.text = "" }
            await handleImageDomainCorrection(correction)
            return
        }

        let route = ConversationRouter.route(
            text: text,
            hasPhoto: hasPhoto,
            targetedMealDraftID: targetedMealDraftID,
            isExplicitMealCaptureIntent: ConversationRouter.isMealCollecting(store.active.activity),
            hasActiveGymSession: gym.hasActiveSession && !hasActiveStrengthConversation,
            hasActiveStrengthConversation: hasActiveStrengthConversation
        )

        switch route {
        case .clarifyMealOrAsk:
            presentMealOrAskClarification(originalText: text)
            return
        case .gymStart(let templateID):
            guard AIDataProcessingConsentStore.hasAccepted(version: AIDataProcessingConsentStore.gymPhotoVersion) else {
                pendingConsentKind = .gymPhoto
                pendingAfterConsent = { Task { await self.requestStartGymWorkout(planReference: .starter(templateID)) } }
                needsAIConsent = true
                return
            }
            if !text.isEmpty {
                store.append(ConversationMessage(actor: .user, text: text))
                store.updateComposer { $0.text = "" }
            }
            await requestStartGymWorkout(planReference: .starter(templateID))
            return
        case .gymFinish:
            if !text.isEmpty {
                store.append(ConversationMessage(actor: .user, text: text))
                store.updateComposer { $0.text = "" }
            }
            requestStrengthFinish()
            return
        case .gymOpenPlanImport:
            if !text.isEmpty {
                store.append(ConversationMessage(actor: .user, text: text))
                store.updateComposer { $0.text = "" }
            }
            applyGymIntent(openImport: true)
            return
        case .gymImportPasteText(let planText):
            if !text.isEmpty {
                store.append(ConversationMessage(actor: .user, text: text))
                store.updateComposer { $0.text = "" }
            }
            await interpretPastedWorkoutPlan(planText)
            return
        case .gymArrivedAtGym:
            if !text.isEmpty {
                store.append(ConversationMessage(actor: .user, text: text))
                store.updateComposer { $0.text = "" }
            }
            guard AIDataProcessingConsentStore.hasAccepted(version: AIDataProcessingConsentStore.gymPhotoVersion) else {
                pendingConsentKind = .gymPhoto
                pendingAfterConsent = { Task { await self.handleGymArrival() } }
                needsAIConsent = true
                return
            }
            await handleGymArrival()
            return
        case .gymStrengthPhotoEvidence:
            guard AIDataProcessingConsentStore.hasAccepted(version: AIDataProcessingConsentStore.gymPhotoVersion) else {
                pendingConsentKind = .gymPhoto
                pendingAfterConsent = { Task { await self.sendComposer() } }
                needsAIConsent = true
                return
            }
            await performStrengthPhotoSend(text: text, photos: photos)
            return
        case .gymShowCurrentProgram:
            if !text.isEmpty {
                store.append(ConversationMessage(actor: .user, text: text))
                store.updateComposer { $0.text = "" }
            }
            await showCurrentGymProgram()
            return
        case .gymSetPhoto:
            guard AIDataProcessingConsentStore.hasAccepted(version: AIDataProcessingConsentStore.gymPhotoVersion) else {
                pendingConsentKind = .gymPhoto
                pendingAfterConsent = { Task { await self.sendComposer() } }
                needsAIConsent = true
                return
            }
            await performGymPhotoSend(text: text, photo: photos.first)
            return
        case .liveTai:
            guard AIDataProcessingConsentStore.hasAccepted(version: AIDataProcessingConsentStore.liveTaiVersion) else {
                pendingConsentKind = .liveTai
                pendingAfterConsent = { Task { await self.sendComposer() } }
                needsAIConsent = true
                return
            }
            await performLiveTaiSend(text: text)
        case .mealInterpret, .mealRefine:
            guard AIDataProcessingConsentStore.hasAccepted(version: AIDataProcessingConsentStore.mealAndGoalVersion) else {
                pendingConsentKind = .mealAndGoal
                pendingAfterConsent = { Task { await self.sendComposer() } }
                needsAIConsent = true
                return
            }
            await performMealSend(text: text, photo: photos.first, route: route)
        }
    }

    func handleMealCardAction(_ action: MealCapabilityID.CardAction, cardID: UUID) {
        guard let message = store.active.messages.first(where: { $0.card?.id == cardID }),
              let card = message.card,
              card.isInteractive,
              var payload = MealCardCodec.decode(card.payload),
              !payload.isLogged
        else { return }

        switch action {
        case .looksRight:
            guard !payload.refinementAccepted else { return }
            payload.refinementAccepted = true
            meal.markReadyToLog()
            replaceCardPayload(cardID: cardID, payload: payload, interactive: true)
            // Accepting an estimate ends targeted refinement for that draft.
            if targetedMealDraftID == payload.draft.id {
                clearTargetedMealRefinementKeepingPhase(.readyToLog)
            } else {
                store.setActivity(MealCapabilityActivityCodec.makeActivity(
                    phase: .readyToLog,
                    targetedDraftID: targetedMealDraftID
                ))
            }
            store.setQuickActions([])

        case .changeSomething:
            payload.refinementAccepted = false
            meal.markReviewing()
            replaceCardPayload(cardID: cardID, payload: payload, interactive: true)
            store.setActivity(MealCapabilityActivityCodec.makeActivity(
                phase: .reviewing,
                targetedDraftID: payload.draft.id
            ))
            store.append(
                ConversationMessage(
                    actor: .assistant,
                    text: "No problem — tell me what to change for this meal. For example: “it was grilled chicken,” “much smaller,” or “no cheese.”"
                )
            )
            store.setQuickActions([
                ConversationAllowedQuickAction.mealCancelRefine.asConversationQuickAction()
            ])

        case .logMeal:
            guard payload.refinementAccepted else { return }
            Task { await logMealDraft(cardID: cardID, payload: payload) }
        }
    }

    func handleMealCardLoggingDayChange(cardID: UUID, selectedDate: Date) {
        guard let message = store.active.messages.first(where: { $0.card?.id == cardID }),
              let card = message.card,
              card.isInteractive,
              var payload = MealCardCodec.decode(card.payload),
              !payload.isLogged
        else { return }

        let candidateDay = NutritionDay(containing: selectedDate)
        guard !candidateDay.isAfterToday() else { return }

        let updatedDraft = meal.applyLoggingDayChange(draftID: payload.draft.id, to: candidateDay)
            ?? MealCapabilityController.draft(payload.draft.asCheckInDraft(), retargetedTo: candidateDay)

        payload.draft = MealEstimateSnapshot(draft: updatedDraft)
        replaceCardPayload(cardID: cardID, payload: payload, interactive: true)

        let remaining = ConversationRestoration.interactiveUnloggedMealPayloads(in: store.active)
        meal.syncUnloggedDrafts(from: remaining)
    }

    func consumeConsentRequest() {
        needsAIConsent = false
    }

    func acceptConsent() {
        needsAIConsent = false
        let action = pendingAfterConsent
        pendingAfterConsent = nil
        action?()
    }

    func declineConsent() {
        needsAIConsent = false
        pendingAfterConsent = nil
        // Declining v2 must not revoke v1 meal/goal consent.
    }

    func dismissLiveTaiWhy() {
        showLiveTaiWhy = false
    }

    /// Test hook — resolves clarification Log meal without going through sync quick-action Task.
    func resolveClarificationLogMealForTests() async {
        await resolveClarificationLogMeal()
    }

    /// Test hook — resolves clarification Ask about it without going through sync quick-action Task.
    func resolveClarificationAskAboutItForTests() async {
        await resolveClarificationAskAboutIt()
    }

    // MARK: - Private

    private func seedGreeting() {
        let greeting = ConversationMessage(
            actor: .assistant,
            text: "Hi! What can I help you with today?"
        )
        let actionsMessage = ConversationMessage(
            actor: .assistant,
            text: nil,
            quickActions: Self.defaultQuickActions
        )
        store.mutate {
            $0.messages = [greeting, actionsMessage]
            $0.activeQuickActions = Self.defaultQuickActions
            $0.activity = .awaitingUser
        }
    }

    private func requestConsent(_ kind: AIDataProcessingConsentKind, _ action: @escaping () -> Void) {
        if AIDataProcessingConsentStore.hasAccepted(version: kind.requiredVersion) {
            action()
        } else {
            pendingConsentKind = kind
            pendingAfterConsent = action
            needsAIConsent = true
        }
    }

    private func performMealSend(text: String, photo: Data?, route: ConversationInputRoute) async {
        store.updateComposer {
            $0.text = ""
            $0.pendingPhotoJPEG = nil
        }

        if let photo {
            let attachment: ConversationAttachment
            if let stored = try? ConversationAttachment.storedPhotoJPEG(photo) {
                attachment = stored
            } else {
                attachment = ConversationAttachment(kind: .photoJPEG(photo))
            }
            store.append(
                ConversationMessage(
                    actor: .user,
                    text: text.isEmpty ? nil : text,
                    attachment: attachment
                )
            )
        } else if !text.isEmpty {
            store.append(ConversationMessage(actor: .user, text: text))
        }

        switch route {
        case .mealRefine(let draftID):
            await runTargetedRefinement(userText: text, draftID: draftID)
        case .mealInterpret:
            await runInterpretation(userText: text, photoJPEG: photo)
        case .liveTai, .clarifyMealOrAsk, .gymStart, .gymFinish, .gymSetPhoto, .gymOpenPlanImport, .gymImportPasteText, .gymShowCurrentProgram, .gymArrivedAtGym, .gymStrengthPhotoEvidence:
            break
        }
    }

    private func presentMealOrAskClarification(originalText: String) {
        let trimmed = originalText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        store.updateComposer {
            $0.text = ""
            $0.pendingPhotoJPEG = nil
        }
        // Append the user turn once; clarifying actions reuse this text.
        store.append(ConversationMessage(actor: .user, text: trimmed))
        pendingClarificationText = trimmed
        store.append(
            ConversationMessage(
                actor: .assistant,
                text: "Would you like me to log that as a meal?",
                quickActions: [
                    ConversationAllowedQuickAction.mealLogIt.asConversationQuickAction(),
                    ConversationAllowedQuickAction.liveTaiAskAboutIt.asConversationQuickAction(),
                ]
            )
        )
        store.setActivity(.awaitingUser)
        store.setQuickActions([
            ConversationAllowedQuickAction.mealLogIt.asConversationQuickAction(),
            ConversationAllowedQuickAction.liveTaiAskAboutIt.asConversationQuickAction(),
        ])
    }

    private func resolveClarificationLogMeal() async {
        guard let text = pendingClarificationText else { return }
        pendingClarificationText = nil
        store.setQuickActions([])

        guard AIDataProcessingConsentStore.hasAccepted(version: AIDataProcessingConsentStore.mealAndGoalVersion) else {
            pendingClarificationText = text
            pendingConsentKind = .mealAndGoal
            pendingAfterConsent = { Task { await self.resolveClarificationLogMeal() } }
            needsAIConsent = true
            return
        }

        // Do not re-append the user message — it was already posted at clarification.
        await runInterpretation(userText: text, photoJPEG: nil)
    }

    private func resolveClarificationAskAboutIt() async {
        guard let text = pendingClarificationText else { return }
        pendingClarificationText = nil
        store.setQuickActions([])

        guard AIDataProcessingConsentStore.hasAccepted(version: AIDataProcessingConsentStore.liveTaiVersion) else {
            pendingClarificationText = text
            pendingConsentKind = .liveTai
            pendingAfterConsent = { Task { await self.resolveClarificationAskAboutIt() } }
            needsAIConsent = true
            return
        }

        // Do not re-append the user message.
        await runLiveTai(ask: text, isRetry: true)
    }

    private func performLiveTaiSend(text: String) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if case .processing(let reason) = store.active.activity,
           reason == LiveTaiCapabilityController.processingReason
        {
            return
        }

        store.updateComposer {
            $0.text = ""
            $0.pendingPhotoJPEG = nil
        }
        store.append(ConversationMessage(actor: .user, text: trimmed))
        await runLiveTai(ask: trimmed, isRetry: false)
    }

    private func retryLiveTai() async {
        guard let ask = pendingLiveTaiRetryAsk else { return }
        await runLiveTai(ask: ask, isRetry: true)
    }

    private func runLiveTai(ask: String, isRetry: Bool) async {
        store.setActivity(.processing(reason: LiveTaiCapabilityController.processingReason))
        store.setQuickActions([])

        // Exclude the just-appended user ask from "recent" duplication by using messages before this turn's reply.
        let outcome = await liveTai.ask(userAsk: ask, conversationMessages: store.active.messages)
        switch outcome {
        case .failure(let message):
            pendingLiveTaiRetryAsk = ask
            errorMessage = message
            store.append(ConversationMessage(actor: .assistant, text: message))
            store.setActivity(.awaitingUser)
            store.setQuickActions([
                ConversationAllowedQuickAction.liveTaiRetry.asConversationQuickAction()
            ] + Self.defaultQuickActions)

        case .success(let response):
            pendingLiveTaiRetryAsk = nil
            let text = LiveTaiResponsePresentation.assistantText(from: response)
            let evidence = LiveTaiResponsePresentation.evidencePayload(from: response)
            latestLiveTaiEvidence = evidence

            var suggestionsNote: String?
            let unknown = ConversationQuickActionAllowlist.nonInteractiveSuggestions(from: response.quickActions)
            if !unknown.isEmpty {
                suggestionsNote = "Suggestions: " + unknown.joined(separator: " · ")
            }

            let body = [text, suggestionsNote].compactMap { $0 }.joined(separator: "\n\n")
            store.append(
                ConversationMessage(
                    actor: .assistant,
                    text: body,
                    card: evidence.map { LiveTaiEvidenceCodec.makeCard(payload: $0) },
                    quickActions: LiveTaiResponsePresentation.quickActions(from: response)
                )
            )
            store.setActivity(.awaitingUser)
            store.setQuickActions(Self.defaultQuickActions)
            // requiresUserDecision is advisory only — never mutates Artifacts here.
            _ = response.requiresUserDecision
            _ = isRetry
        }
    }

    private func sendPhotoAndInterpret(_ jpeg: Data) async {
        clearTargetedMealRefinement()
        let attachment: ConversationAttachment
        if let stored = try? ConversationAttachment.storedPhotoJPEG(jpeg) {
            attachment = stored
        } else {
            attachment = ConversationAttachment(kind: .photoJPEG(jpeg))
        }
        store.append(
            ConversationMessage(
                actor: .user,
                attachment: attachment
            )
        )
        await runInterpretation(userText: "", photoJPEG: jpeg)
    }

    private func runInterpretation(userText: String, photoJPEG: Data?) async {
        store.setActivity(.processing(reason: "interpreting_meal"))
        store.setQuickActions([])

        let outcome = await meal.interpret(
            userText: userText,
            photoJPEG: photoJPEG,
            targetDraftID: nil,
            captureNutritionDay: captureNutritionDayForNewDrafts()
        )
        switch outcome {
        case .failure(let message):
            errorMessage = message
            store.append(ConversationMessage(actor: .assistant, text: message))
            store.setActivity(.awaitingUser)
            store.setQuickActions(Self.defaultQuickActions)

        case .imageFailure(let failure):
            await handleImageInterpretationFailure(
                failure,
                photos: photoJPEG.map { [$0] } ?? [],
                submittedViaGymRoute: false
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
                    isLogged: false,
                    imageClassification: success.imageClassification
                )
                store.append(
                    ConversationMessage(
                        actor: .assistant,
                        card: MealCardCodec.makeCard(payload: payload, interactive: true)
                    )
                )
            }
            store.setActivity(MealCapabilityActivityCodec.makeActivity(phase: .reviewing))
            store.setQuickActions([])
        }
    }

    private func runTargetedRefinement(userText: String, draftID: UUID) async {
        store.setActivity(.processing(reason: "interpreting_meal"))
        store.setQuickActions([])

        let outcome = await meal.interpret(
            userText: userText,
            photoJPEG: nil,
            targetDraftID: draftID,
            captureNutritionDay: captureNutritionDayForNewDrafts()
        )
        switch outcome {
        case .failure(let message):
            errorMessage = message
            store.append(ConversationMessage(actor: .assistant, text: message))
            // Keep target so the user can retry refinement for the same draft.
            store.setActivity(MealCapabilityActivityCodec.makeActivity(
                phase: .reviewing,
                targetedDraftID: draftID
            ))
            store.setQuickActions([
                ConversationAllowedQuickAction.mealCancelRefine.asConversationQuickAction()
            ])

        case .imageFailure(let failure):
            await handleImageInterpretationFailure(
                failure,
                photos: [],
                submittedViaGymRoute: false
            )

        case .success(let success):
            guard let updated = success.drafts.first(where: { $0.id == draftID }) ?? success.drafts.first else {
                store.setActivity(MealCapabilityActivityCodec.makeActivity(
                    phase: .reviewing,
                    targetedDraftID: draftID
                ))
                return
            }
            replaceInteractiveCard(forDraftID: draftID, draft: updated)
            // Successful refinement clears the target; other pending cards stay unchanged.
            store.setActivity(MealCapabilityActivityCodec.makeActivity(phase: .reviewing))
            store.setQuickActions([])
        }
    }

    /// Logs exactly one draft addressed by `payload.draft.id` / `cardID`.
    func logMealDraft(cardID: UUID, payload: MealEstimateCardPayload) async {
        let draftID = payload.draft.id
        if targetedMealDraftID == draftID {
            clearTargetedMealRefinementKeepingPhase(.saving)
        }
        store.setActivity(.processing(reason: "saving_meal"))
        let result = await meal.confirmAndSaveDraft(draftID: draftID, payload: payload)
        switch result {
        case .failure(let saveError):
            let message: String
            switch saveError {
            case .nothingToLog, .draftNotFound:
                message = "Nothing to log yet."
            case .alreadyLogged:
                message = "That meal is already logged."
            case .draftMismatch:
                message = "That meal card is out of date. Please try again."
            case .validationFailed(let reason):
                message = reason
            case .persistenceFailed:
                message = meal.lastError ?? "Could not save this meal. Please try again."
            }
            errorMessage = message
            store.append(ConversationMessage(actor: .assistant, text: message))
            restoreActivityAfterPartialMealState()

        case .success(let draft):
            var logged = payload
            logged.isLogged = true
            logged.refinementAccepted = true
            replaceCardPayload(cardID: cardID, payload: logged, interactive: false)

            store.append(
                ConversationMessage(
                    actor: .assistant,
                    text: Self.loggedMealConfirmation(label: draft.label, nutritionDay: draft.nutritionDay)
                )
            )

            let remaining = ConversationRestoration.interactiveUnloggedMealPayloads(in: store.active)
            meal.syncUnloggedDrafts(from: remaining)
            if remaining.isEmpty {
                meal.resetAfterCompletion()
                store.setActivity(.awaitingUser)
                store.setQuickActions(Self.defaultQuickActions)
            } else {
                let ready = remaining.contains(where: \.refinementAccepted)
                store.setActivity(MealCapabilityActivityCodec.makeActivity(
                    phase: ready ? .readyToLog : .reviewing
                ))
                store.setQuickActions([])
            }
            onMealSaved?()
        }
    }

    /// - Warning: Prefer `logMealDraft`. Kept for existing tests that call `confirmLog`.
    func confirmLog(cardID: UUID, payload: MealEstimateCardPayload) async {
        await logMealDraft(cardID: cardID, payload: payload)
    }

    private func cancelTargetedMealRefinement() {
        guard targetedMealDraftID != nil else { return }
        clearTargetedMealRefinementKeepingPhase(.reviewing)
        store.append(
            ConversationMessage(
                actor: .assistant,
                text: "Okay — I won’t change that meal estimate. Ask me a question, or tap Change something on a meal when you want to refine it."
            )
        )
        store.setQuickActions(Self.defaultQuickActions)
    }

    private func clearTargetedMealRefinement() {
        if targetedMealDraftID != nil {
            let remaining = ConversationRestoration.interactiveUnloggedMealPayloads(in: store.active)
            if remaining.isEmpty {
                store.setActivity(.awaitingUser)
            } else {
                let ready = remaining.contains(where: \.refinementAccepted)
                store.setActivity(MealCapabilityActivityCodec.makeActivity(
                    phase: ready ? .readyToLog : .reviewing
                ))
            }
        }
    }

    private func clearTargetedMealRefinementKeepingPhase(_ phase: MealCapabilityID.Phase) {
        store.setActivity(MealCapabilityActivityCodec.makeActivity(phase: phase))
    }

    private func restoreActivityAfterPartialMealState() {
        let remaining = ConversationRestoration.interactiveUnloggedMealPayloads(in: store.active)
        meal.syncUnloggedDrafts(from: remaining)
        let target = targetedMealDraftID
        if remaining.isEmpty {
            store.setActivity(.awaitingUser)
            store.setQuickActions(Self.defaultQuickActions)
        } else {
            let ready = remaining.contains(where: \.refinementAccepted)
            store.setActivity(MealCapabilityActivityCodec.makeActivity(
                phase: ready ? .readyToLog : .reviewing,
                targetedDraftID: target.flatMap { id in remaining.contains(where: { $0.draft.id == id }) ? id : nil }
            ))
        }
    }

    private func replaceInteractiveCard(forDraftID draftID: UUID, draft: CheckInMealDraft) {
        let newPayload = MealEstimateCardPayload(
            draft: MealEstimateSnapshot(draft: draft),
            refinementAccepted: false,
            isLogged: false
        )
        store.mutate { conversation in
            conversation.messages = conversation.messages.map { message in
                guard let card = message.card,
                      card.typeID == MealCapabilityID.estimateCardType,
                      card.isInteractive,
                      let existing = MealCardCodec.decode(card.payload),
                      existing.draft.id == draftID
                else { return message }
                let updated = MealCardCodec.makeCard(payload: newPayload, interactive: true)
                return ConversationMessage(
                    id: message.id,
                    actor: message.actor,
                    createdAt: message.createdAt,
                    text: message.text,
                    attachment: message.attachment,
                    card: ConversationCard(
                        id: card.id,
                        typeID: updated.typeID,
                        payload: updated.payload,
                        isInteractive: true
                    ),
                    quickActions: message.quickActions
                )
            }
        }
    }

    private func replaceCardPayload(cardID: UUID, payload: MealEstimateCardPayload, interactive: Bool) {
        store.mutate { conversation in
            conversation.messages = conversation.messages.map { message in
                guard let card = message.card, card.id == cardID else { return message }
                let updated = MealCardCodec.makeCard(payload: payload, interactive: interactive)
                return ConversationMessage(
                    id: message.id,
                    actor: message.actor,
                    createdAt: message.createdAt,
                    text: message.text,
                    attachment: message.attachment,
                    card: ConversationCard(
                        id: card.id,
                        typeID: updated.typeID,
                        payload: updated.payload,
                        isInteractive: interactive
                    ),
                    quickActions: message.quickActions
                )
            }
        }
    }

    private static func mealCapturePrompt(for context: NutritionDayContext?) -> String {
        guard let day = context?.day, !day.isToday() else {
            return "Let’s log a meal. Take a photo or describe what you ate."
        }
        let label = HomeNutritionDayFormatting.navigationTitle(for: day)
        return "Let’s log a meal for \(label). Take a photo or describe what you ate."
    }

    private func captureNutritionDayForNewDrafts() -> NutritionDay {
        nutritionDayContext?.day ?? .today()
    }

    private static func loggedMealConfirmation(label: String, nutritionDay: NutritionDay) -> String {
        if !nutritionDay.isToday() {
            let dayLabel = HomeNutritionDayFormatting.navigationTitle(for: nutritionDay)
            return "Logged \(label) for \(dayLabel). Nice work — anything else I can help with?"
        }
        return "Logged \(label). Nice work — anything else I can help with?"
    }

    // MARK: - Gym

    func handleGymPlanCardTakePhoto() {
        handleQuickAction(ConversationAllowedQuickAction.gymTakeSetPhoto.asConversationQuickAction())
    }

    func handleGymPlanCardFinish() {
        requestStrengthFinish()
    }

    func handleGymSetCardAction(_ action: GymCapabilityID.CardAction, cardID: UUID, payload: GymSetConfirmationCardPayload) {
        guard let message = store.active.messages.first(where: { $0.card?.id == cardID }),
              let card = message.card,
              card.isInteractive,
              !payload.isSaved
        else { return }

        switch action {
        case .saveSet:
            Task { await saveGymSet(cardID: cardID, payload: payload) }
        case .retakePhoto:
            cancelGymSetCard(cardID: cardID, payload: payload)
            handleGymPlanCardTakePhoto()
        case .cancelSet:
            cancelGymSetCard(cardID: cardID, payload: payload)
            if let session = gym.session {
                store.setActivity(GymCapabilityActivityCodec.makeActivity(phase: .active, session: session))
                store.setQuickActions(ConversationDefaults.gymActiveQuickActions)
            }
            store.append(
                ConversationMessage(
                    actor: .assistant,
                    text: "Set discarded. Tap Take Photo when you’re ready to try again."
                )
            )
        }
    }

    func handleGymSetDraftChange(cardID: UUID, payload: GymSetConfirmationCardPayload) {
        replaceGymSetCardPayload(cardID: cardID, payload: payload, interactive: true)
    }

    func cancelWorkoutStartConflict() {
        pendingWorkoutStartConflict = nil
        pendingWorkoutDiscardConfirmation = false
        isWorkoutStartConflictDialogPresented = false
        logWorkoutStartConflictEvent("cancelled")
    }

    func requestWorkoutDiscardConfirmation() {
        isWorkoutStartConflictDialogPresented = false
        pendingWorkoutDiscardConfirmation = true
        logWorkoutStartConflictEvent("discard_confirmation_requested")
    }

    func cancelWorkoutDiscardConfirmation() {
        pendingWorkoutDiscardConfirmation = false
        if pendingWorkoutStartConflict != nil {
            isWorkoutStartConflictDialogPresented = true
        }
        logWorkoutStartConflictEvent("discard_confirmation_cancelled")
    }

    func resolveWorkoutStartConflict(_ resolution: GymWorkoutStartConflictResolution) async {
        guard !isResolvingWorkoutStartConflict else {
            logWorkoutStartConflictEvent("ignored_duplicate_resolution", resolution: resolution)
            return
        }
        guard let conflict = pendingWorkoutStartConflict else {
            logWorkoutStartConflictEvent("ignored_missing_conflict", resolution: resolution)
            return
        }
        let target = conflict.requestedWorkoutTarget

        isResolvingWorkoutStartConflict = true
        isWorkoutStartConflictDialogPresented = false
        pendingWorkoutDiscardConfirmation = false
        defer { isResolvingWorkoutStartConflict = false }

        logWorkoutStartConflictEvent(
            "resolve_started",
            resolution: resolution,
            conflict: conflict,
            target: target,
            activeSessionID: gym.session?.sessionID,
            activeStatus: gym.session?.status
        )

        switch resolution {
        case .resumeCurrent:
            pendingWorkoutStartConflict = nil
            await resumeStrengthWorkoutFromConversation()
            logWorkoutStartConflictEvent(
                "resume_completed",
                activeSessionID: gym.session?.sessionID,
                navigation: "active_workout"
            )
        case .finishCurrentAndStartSelected:
            pendingWorkoutStartConflict = nil
            await finishCurrentAndStartWorkout(target: target)
        case .discardCurrentAndStartSelected:
            pendingWorkoutStartConflict = nil
            await discardCurrentAndStartWorkout(target: target)
        case .cancel:
            pendingWorkoutStartConflict = nil
            logWorkoutStartConflictEvent("cancelled_via_resolution")
        }
    }

    private func presentWorkoutStartConflict(_ conflict: GymWorkoutStartConflict) {
        pendingWorkoutStartConflict = conflict
        pendingWorkoutDiscardConfirmation = false
        isWorkoutStartConflictDialogPresented = true
        logWorkoutStartConflictEvent(
            "presented",
            conflict: conflict,
            target: conflict.requestedWorkoutTarget,
            activeSessionID: gym.session?.sessionID,
            activeStatus: gym.session?.status
        )
    }

    func requestStartGymWorkout(target: GymPlanWorkoutTarget) async {
        guard !isStartingWorkout else { return }
        isStartingWorkout = true
        defer { isStartingWorkout = false }

        if usesShellWorkoutEntryRouting || strengthWorkoutCoordinator != nil {
            await beginConversationalStrengthWorkout(target: target)
            return
        }

        if let coordinator = strengthWorkoutCoordinator {
            do {
                if let active = try await coordinator.fetchActiveWorkout(),
                   active.planReference == target.reference {
                    if let presentation = try await coordinator.buildResumePresentation(source: .conversation) {
                        onPresentStrengthWorkout?(presentation)
                    }
                    return
                }

                let plan = try await gymPlanRepository.resolvePlan(
                    reference: target.reference,
                    sectionIndex: target.sectionIndex,
                    ownerID: ownerID
                )
                if let conflict = try await coordinator.detectStartConflict(
                    requestedTarget: target,
                    requestedTitle: plan.title,
                    entrySource: .conversation
                ) {
                    presentWorkoutStartConflict(conflict)
                    return
                }

                let presentation = try await coordinator.buildStartPresentation(
                    request: StrengthWorkoutStartRequest(
                        target: target,
                        source: .conversation,
                        skipPreFlight: false
                    )
                )
                onPresentStrengthWorkout?(presentation)
            } catch {
                errorMessage = "Could not start this workout."
                store.append(ConversationMessage(actor: .assistant, text: errorMessage!))
            }
            return
        }

        if gym.hasActiveSession, let current = gym.session, current.planReference == target.reference {
            resumeActiveGymWorkout()
            return
        }

        if let active = try? await gym.activeSessionSnapshot(), active.planReference == target.reference {
            resumeActiveGymWorkout()
            return
        }

        do {
            let plan = try await gymPlanRepository.resolvePlan(
                reference: target.reference,
                sectionIndex: target.sectionIndex,
                ownerID: ownerID
            )
            if let active = try await gym.activeSessionSnapshot() {
                presentWorkoutStartConflict(
                    GymWorkoutStartConflict(
                        activeSessionTitle: active.title,
                        activePlanReference: active.planReference,
                        requestedPlanReference: target.reference,
                        requestedPlanTitle: plan.title,
                        requestedWorkoutTarget: target,
                        entrySource: .conversation,
                        activeProgressSummary: nil,
                        activeCompletedSets: nil,
                        activeTotalSets: nil
                    )
                )
                return
            }
            await startGymWorkout(plan: plan)
        } catch {
            errorMessage = "Could not start this workout."
            store.append(ConversationMessage(actor: .assistant, text: errorMessage!))
        }
    }

    func beginConversationalStrengthFromHome() async {
        guard AIDataProcessingConsentStore.hasAccepted(version: AIDataProcessingConsentStore.gymPhotoVersion) else {
            pendingConsentKind = .gymPhoto
            pendingAfterConsent = { Task { await self.handleGymArrival() } }
            needsAIConsent = true
            return
        }
        await handleGymArrival()
    }

    func resumeConversationalStrengthFromHome() async {
        await resumeConversationalStrengthInThread()
    }

    func beginConversationalStrengthWorkout(
        target: GymPlanWorkoutTarget,
        entrySource: StrengthWorkoutEntrySource = .conversation
    ) async {
        await Task.yield()
        guard AIDataProcessingConsentStore.hasAccepted(version: AIDataProcessingConsentStore.gymPhotoVersion) else {
            pendingConsentKind = .gymPhoto
            pendingAfterConsent = { Task { await self.beginConversationalStrengthWorkout(target: target, entrySource: entrySource) } }
            needsAIConsent = true
            return
        }

        if let coordinator = strengthWorkoutCoordinator {
            do {
                if let active = try await coordinator.fetchActiveWorkout(),
                   active.planReference == target.reference
                {
                    await resumeConversationalStrengthInThread()
                    return
                }

                let plan = try await gymPlanRepository.resolvePlan(
                    reference: target.reference,
                    sectionIndex: target.sectionIndex,
                    ownerID: ownerID
                )
                if let conflict = try await coordinator.detectStartConflict(
                    requestedTarget: target,
                    requestedTitle: plan.title,
                    entrySource: entrySource
                ) {
                    presentWorkoutStartConflict(conflict)
                    return
                }
            } catch {
                errorMessage = "Could not start this workout."
                store.append(ConversationMessage(actor: .assistant, text: errorMessage!))
                return
            }
        }

        store.setActivity(.processing(reason: "starting_strength_workout"))
        store.setQuickActions([])
        do {
            let result = try await strengthConversation.startOrResumeFromTarget(target)
            try await presentConversationalStrengthStartResult(result)
        } catch {
            errorMessage = "Could not start this workout."
            store.append(ConversationMessage(actor: .assistant, text: errorMessage!))
            store.setActivity(.awaitingUser)
            store.setQuickActions(Self.defaultQuickActions)
        }
    }

    func openDedicatedStrengthWorkoutScreen() async {
        await openDedicatedStrengthWorkout()
    }

    private func resumeConversationalStrengthInThread() async {
        _ = try? await strengthConversation.workoutController.restoreInProgressSession()
        if strengthConversation.session != nil {
            appendOrRefreshStrengthOverviewCard()
            if let session = strengthConversation.session {
                store.setActivity(
                    StrengthConversationActivityCodec.makeActivity(
                        phase: .active,
                        sessionID: session.sessionID
                    )
                )
            }
            store.setQuickActions(ConversationDefaults.strengthConversationQuickActions)
            if store.active.messages.last?.card?.typeID != StrengthConversationCapabilityID.workoutOverviewCardType {
                store.append(
                    ConversationMessage(
                        actor: .assistant,
                        text: "Welcome back — your \(strengthConversation.session?.title ?? "workout") is still in progress."
                    )
                )
            }
            return
        }

        if gym.hasActiveSession {
            appendOrRefreshWorkoutPlanCard()
            store.setActivity(GymCapabilityActivityCodec.makeActivity(phase: .active, session: gym.session!))
            store.setQuickActions(ConversationDefaults.gymActiveQuickActions)
            store.append(
                ConversationMessage(
                    actor: .assistant,
                    text: "Welcome back — your \(gym.session?.title ?? "workout") is still in progress. Tap Take Photo when you’re ready for the next set."
                )
            )
            return
        }

        store.append(
            ConversationMessage(
                actor: .assistant,
                text: "I couldn't find an active workout to resume."
            )
        )
    }

    private func presentConversationalStrengthStartResult(
        _ result: StrengthConversationController.GymArrivalResult
    ) async throws {
        let session: StrengthWorkoutSession
        let greeting: String
        switch result {
        case .resumed(let resumed):
            session = resumed
            greeting = "Welcome back — your \(resumed.title) is still in progress."
        case .started(let started):
            session = started
            if strengthConversation.pendingProgressionProposals().isEmpty {
                greeting = "Well done making it to the gym. Here's what's expected today."
            } else {
                greeting = "Well done making it to the gym. Review today's progression suggestions when you're ready."
            }
        }
        store.append(ConversationMessage(actor: .assistant, text: greeting))
        appendOrRefreshStrengthOverviewCard()
        store.setActivity(
            StrengthConversationActivityCodec.makeActivity(
                phase: .active,
                sessionID: session.sessionID
            )
        )
        store.setQuickActions(
            StrengthConversationUITestSupport.isEnabled
                ? ConversationDefaults.strengthConversationQuickActionsForUITest
                : ConversationDefaults.strengthConversationQuickActions
        )
    }

    private func resumeStrengthWorkoutFromConversation() async {
        await resumeConversationalStrengthInThread()
    }

    private func interpretPastedWorkoutPlan(_ text: String) async {
        store.setActivity(.processing(reason: "interpreting_workout_plan"))
        do {
            let draft = try await GymPlanImportService.interpret(
                source: .pastedText(text),
                aiService: aiService
            )
            store.setActivity(.awaitingUser)
            store.append(
                ConversationMessage(
                    actor: .assistant,
                    text: "I’ve drafted “\(draft.title)” for review. Check sections, optional exercises, and any uncertain matches — nothing is saved until you tap Save Plan."
                )
            )
            onPresentGymPlanImportReview?(draft, text)
            onManageGymPlans?()
        } catch {
            errorMessage = "Couldn’t interpret this workout program."
            store.append(ConversationMessage(actor: .assistant, text: errorMessage!))
            store.setActivity(.awaitingUser)
        }
    }

    private func showCurrentGymProgram() async {
        do {
            let library = try await gymPlanRepository.fetchLibrary(ownerID: ownerID)
            if let active = library.activePlan {
                let sections = active.sectionNames.isEmpty ? [active.title] : active.sectionNames
                let sectionList = sections.joined(separator: ", ")
                store.append(
                    ConversationMessage(
                        actor: .assistant,
                        text: "Your active plan is “\(active.title)” (\(sectionList)). Open Gym Plans to edit, import a replacement, or start a workout."
                    )
                )
            } else {
                store.append(
                    ConversationMessage(
                        actor: .assistant,
                        text: "You don’t have an active gym plan yet. Import your trainer’s program from Gym Plans to get started."
                    )
                )
            }
            onManageGymPlans?()
        } catch {
            store.append(
                ConversationMessage(
                    actor: .assistant,
                    text: "I couldn’t load your gym plans right now. Try opening Gym Plans from the menu."
                )
            )
        }
    }

    private func requestStartGymWorkout(planReference: GymPlanReference) async {
        await requestStartGymWorkout(target: GymPlanWorkoutTarget(reference: planReference, sectionIndex: 0))
    }

    private func resumeActiveGymWorkout() {
        applyGymIntent(resume: true)
    }

    private func finishCurrentAndStartWorkout(target: GymPlanWorkoutTarget) async {
        if let coordinator = strengthWorkoutCoordinator {
            do {
                if hasActiveStrengthConversation {
                    _ = try await strengthConversation.finishWorkout()
                } else {
                    try await coordinator.finishActiveWorkout()
                }
                onWorkoutSaved?()
                if strengthWorkoutCoordinator != nil {
                    await beginConversationalStrengthWorkout(target: target)
                } else {
                    let presentation = try await coordinator.buildStartPresentation(
                        request: StrengthWorkoutStartRequest(
                            target: target,
                            source: .conversation,
                            skipPreFlight: false
                        )
                    )
                    onPresentStrengthWorkout?(presentation)
                }
            } catch {
                errorMessage = "Could not start this workout."
                store.append(ConversationMessage(actor: .assistant, text: errorMessage!))
            }
            return
        }

        guard gym.hasActiveSession else {
            await requestStartGymWorkout(target: target)
            return
        }
        store.setActivity(.processing(reason: "finishing_workout"))
        let finishingSessionID = gym.session?.sessionID
        let result = await gym.finishWorkoutExplicitly()
        switch result {
        case .success:
            onWorkoutSaved?()
            gym.resetAfterCompletion()
            store.setActivity(.awaitingUser)
            logWorkoutStartConflictEvent(
                "finish_succeeded",
                activeSessionID: gym.session?.sessionID,
                finishedSessionID: finishingSessionID
            )
            do {
                let plan = try await gymPlanRepository.resolvePlan(
                    reference: target.reference,
                    sectionIndex: target.sectionIndex,
                    ownerID: ownerID
                )
                await startGymWorkout(plan: plan)
                logWorkoutStartConflictEvent(
                    "finish_and_start_completed",
                    target: target,
                    activeSessionID: gym.session?.sessionID,
                    navigation: "new_workout"
                )
            } catch {
                errorMessage = "Could not start this workout."
                store.append(ConversationMessage(actor: .assistant, text: errorMessage!))
                logWorkoutStartConflictEvent(
                    "finish_and_start_failed",
                    target: target,
                    error: error.localizedDescription
                )
            }
        case .failure:
            errorMessage = gym.lastError ?? "Could not finish the workout."
            store.append(ConversationMessage(actor: .assistant, text: errorMessage!))
            if let session = gym.session {
                store.setActivity(GymCapabilityActivityCodec.makeActivity(phase: .active, session: session))
                store.setQuickActions(ConversationDefaults.gymActiveQuickActions)
            }
            logWorkoutStartConflictEvent(
                "finish_failed",
                finishedSessionID: finishingSessionID,
                error: errorMessage
            )
        }
    }

    private func discardCurrentAndStartWorkout(target: GymPlanWorkoutTarget) async {
        if let coordinator = strengthWorkoutCoordinator {
            do {
                if hasActiveStrengthConversation {
                    try await strengthConversation.workoutController.abandonWorkout()
                } else {
                    try await coordinator.abandonActiveWorkout()
                }
                if strengthWorkoutCoordinator != nil {
                    await beginConversationalStrengthWorkout(target: target)
                } else {
                    let presentation = try await coordinator.buildStartPresentation(
                        request: StrengthWorkoutStartRequest(
                            target: target,
                            source: .conversation,
                            skipPreFlight: false
                        )
                    )
                    onPresentStrengthWorkout?(presentation)
                }
            } catch {
                errorMessage = "Could not start this workout."
                store.append(ConversationMessage(actor: .assistant, text: errorMessage!))
            }
            return
        }

        guard let active = try? await gym.activeSessionSnapshot() else {
            await requestStartGymWorkout(target: target)
            return
        }
        let discardedSessionID = active.sessionID
        do {
            try await gym.discardActiveWorkout()
            logWorkoutStartConflictEvent(
                "discard_succeeded",
                activeSessionID: gym.session?.sessionID,
                finishedSessionID: discardedSessionID
            )
            let plan = try await gymPlanRepository.resolvePlan(
                reference: target.reference,
                sectionIndex: target.sectionIndex,
                ownerID: ownerID
            )
            await startGymWorkout(plan: plan)
            logWorkoutStartConflictEvent(
                "discard_and_start_completed",
                target: target,
                activeSessionID: gym.session?.sessionID,
                navigation: "new_workout"
            )
        } catch {
            errorMessage = "Could not start this workout."
            store.append(ConversationMessage(actor: .assistant, text: errorMessage!))
            logWorkoutStartConflictEvent(
                "discard_and_start_failed",
                target: target,
                error: error.localizedDescription
            )
        }
    }

    private func startGymWorkout(planReference: GymPlanReference) async {
        do {
            let plan = try await gymPlanRepository.resolvePlan(reference: planReference, ownerID: ownerID)
            await startGymWorkout(plan: plan)
        } catch {
            errorMessage = gym.lastError ?? "Could not start this workout."
            store.append(ConversationMessage(actor: .assistant, text: errorMessage!))
            store.setActivity(.awaitingUser)
            store.setQuickActions(Self.defaultQuickActions + ConversationDefaults.gymStartQuickActions)
        }
    }

    private func startGymWorkout(plan: GymResolvablePlan, replacingExisting: Bool = false) async {
        store.setActivity(.processing(reason: "starting_workout"))
        store.setQuickActions([])
        do {
            let session = try await gym.startWorkout(plan: plan, replacingExisting: replacingExisting)
            store.append(
                ConversationMessage(
                    actor: .assistant,
                    text: "Here’s your \(session.title) plan. When you’re at the machine, tap Take Photo so I can read the setup and weight."
                )
            )
            appendOrRefreshWorkoutPlanCard()
            store.setActivity(GymCapabilityActivityCodec.makeActivity(phase: .active, session: session))
            store.setQuickActions(ConversationDefaults.gymActiveQuickActions)
        } catch let error as GymWorkoutStartError {
            switch error {
            case .activeSessionInProgress(let active):
                presentWorkoutStartConflict(
                    GymWorkoutStartConflict(
                        activeSessionTitle: active.title,
                        activePlanReference: active.planReference,
                        requestedPlanReference: plan.reference,
                        requestedPlanTitle: plan.title,
                        requestedWorkoutTarget: GymPlanWorkoutTarget(
                            reference: plan.reference,
                            sectionIndex: plan.sectionIndex
                        ),
                        entrySource: .conversation,
                        activeProgressSummary: nil,
                        activeCompletedSets: nil,
                        activeTotalSets: nil
                    )
                )
                store.setActivity(.awaitingUser)
                if gym.hasActiveSession {
                    store.setQuickActions(ConversationDefaults.gymActiveQuickActions)
                } else {
                    store.setQuickActions(Self.defaultQuickActions + ConversationDefaults.gymStartQuickActions)
                }
            }
        } catch {
            errorMessage = gym.lastError ?? "Could not start this workout."
            store.append(ConversationMessage(actor: .assistant, text: errorMessage!))
            store.setActivity(.awaitingUser)
            store.setQuickActions(Self.defaultQuickActions + ConversationDefaults.gymStartQuickActions)
        }
    }

    private func interpretGymSetPhoto(_ jpeg: Data) async {
        if gym.hasActiveStrengthSession {
            store.append(
                ConversationMessage(
                    actor: .user,
                    text: "📷 Set photo captured"
                )
            )
            store.append(
                ConversationMessage(
                    actor: .assistant,
                    text: "Your workout is active in the strength session. Open it to confirm this set — I won't log it automatically."
                )
            )
            await resumeStrengthWorkoutFromConversation()
            return
        }
        guard gym.hasActiveSession else { return }
        store.append(
            ConversationMessage(
                actor: .user,
                text: "📷 Set photo captured"
            )
        )
        store.setActivity(.processing(reason: "interpreting_gym_photo"))
        store.setQuickActions([])

        let outcome = await gym.interpretCurrentSet(
            photoJPEG: jpeg,
            localeIdentifier: Locale.current.identifier,
            weightUnitPreference: Self.preferredWeightUnit()
        )
        gym.releaseTransientPhoto()

        switch outcome {
        case .failure(let message):
            errorMessage = message
            store.append(ConversationMessage(actor: .assistant, text: message))
            if let session = gym.session {
                store.setActivity(GymCapabilityActivityCodec.makeActivity(phase: .active, session: session))
            }
            store.setQuickActions(ConversationDefaults.gymActiveQuickActions)

        case .success(let success):
            if let note = success.assistantNote {
                store.append(ConversationMessage(actor: .assistant, text: note))
            }
            guard let session = gym.session else { return }
            let payload = GymCapabilityController.setCardPayload(from: success.draft, session: session)
            store.append(
                ConversationMessage(
                    actor: .assistant,
                    card: GymSetConfirmationCardCodec.makeCard(payload: payload, interactive: true)
                )
            )
            if let session = gym.session {
                store.setActivity(GymCapabilityActivityCodec.makeActivity(phase: .reviewingSet, session: session))
            }
            store.setQuickActions([])
        }
    }

    private func performGymPhotoSend(text: String, photo: Data?) async {
        store.updateComposer {
            $0.text = ""
            $0.pendingPhotoJPEG = nil
        }
        if !text.isEmpty {
            store.append(ConversationMessage(actor: .user, text: text))
        }
        if let photo {
            await interpretGymSetPhoto(photo)
        }
    }

    private func saveGymSet(cardID: UUID, payload: GymSetConfirmationCardPayload) async {
        guard let session = gym.session else { return }
        store.setActivity(.processing(reason: "saving_gym_set"))
        let result = await gym.confirmAndSaveSet(payload: payload)
        switch result {
        case .failure(let error):
            let message: String
            switch error {
            case .validationFailed(let reason): message = reason
            case .alreadySaved: message = "That set is already saved."
            default: message = gym.lastError ?? "Could not save this set."
            }
            errorMessage = message
            store.append(ConversationMessage(actor: .assistant, text: message))
            store.setActivity(GymCapabilityActivityCodec.makeActivity(phase: .reviewingSet, session: session))

        case .success(let setLog):
            var saved = payload
            saved.isSaved = true
            replaceGymSetCardPayload(cardID: cardID, payload: saved, interactive: false)
            store.append(
                ConversationMessage(
                    actor: .assistant,
                    text: "Saved \(setLog.exerciseName) — \(Int(setLog.weightValue)) \(setLog.weightUnit) × \(setLog.repetitions)."
                )
            )
            appendOrRefreshWorkoutPlanCard()
            onWorkoutSaved?()

            if gym.session?.status == .completed {
                store.append(
                    ConversationMessage(
                        actor: .assistant,
                        text: "Workout complete — great session! Your sets are on Home for today."
                    )
                )
                gym.resetAfterCompletion()
                store.setActivity(.awaitingUser)
                store.setQuickActions(Self.defaultQuickActions + ConversationDefaults.gymStartQuickActions)
            } else if let session = gym.session {
                store.setActivity(GymCapabilityActivityCodec.makeActivity(phase: .active, session: session))
                store.setQuickActions(ConversationDefaults.gymActiveQuickActions)
                store.append(
                    ConversationMessage(
                        actor: .assistant,
                        text: "Ready for the next set? Tap Take Photo when you’re at the machine."
                    )
                )
            }
        }
    }

    func requestStrengthFinish() {
        guard hasActiveStrengthConversation else {
            Task { await finishGymWorkout() }
            return
        }
        guard !isFinishingStrengthWorkout else { return }
        if strengthConversation.hasUnresolvedWork {
            isStrengthFinishConfirmationPresented = true
        } else {
            Task { await confirmStrengthFinish(skipRemaining: false) }
        }
    }

    func cancelStrengthFinishConfirmation() {
        isStrengthFinishConfirmationPresented = false
    }

    func confirmStrengthFinish(skipRemaining: Bool) async {
        guard !isFinishingStrengthWorkout else { return }
        isFinishingStrengthWorkout = true
        isStrengthFinishConfirmationPresented = false
        defer { isFinishingStrengthWorkout = false }
        await finishStrengthWorkout(skipRemaining: skipRemaining)
    }

    func refreshStrengthSessionFromRepository() async {
        _ = try? await strengthConversation.workoutController.restoreInProgressSession()
        guard strengthConversation.session != nil else { return }
        appendOrRefreshStrengthOverviewCard()
        refreshStrengthExerciseWorkspaceCards()
    }

    private func finishGymWorkout() async {
        if hasActiveStrengthConversation {
            await finishStrengthWorkout(skipRemaining: false)
            return
        }
        guard gym.hasActiveSession else { return }
        store.setActivity(.processing(reason: "finishing_workout"))
        let result = await gym.finishWorkoutExplicitly()
        switch result {
        case .failure:
            errorMessage = gym.lastError ?? "Could not finish the workout."
            store.append(ConversationMessage(actor: .assistant, text: errorMessage!))
            if let session = gym.session {
                store.setActivity(GymCapabilityActivityCodec.makeActivity(phase: .active, session: session))
                store.setQuickActions(ConversationDefaults.gymActiveQuickActions)
            }
        case .success(let log):
            appendOrRefreshWorkoutPlanCard(interactive: false)
            store.append(
                ConversationMessage(
                    actor: .assistant,
                    text: "Finished \(log.title). Your logged sets are on Home for today."
                )
            )
            gym.resetAfterCompletion()
            onWorkoutSaved?()
            store.setActivity(.awaitingUser)
            store.setQuickActions(Self.defaultQuickActions + ConversationDefaults.gymStartQuickActions)
        }
    }

    private func finishStrengthWorkout(skipRemaining: Bool) async {
        store.setActivity(.processing(reason: "finishing_workout"))
        do {
            let title = strengthConversation.session?.title ?? "your workout"
            let debrief: StrengthWorkoutDebrief
            if skipRemaining {
                debrief = try await strengthConversation.skipRemainingSetsAndComplete()
            } else {
                debrief = try await strengthConversation.finishWorkout()
            }
            deactivateStrengthConversationCards()
            let wins = debrief.wins.prefix(2).map(\.summaryLine).joined(separator: " ")
            let summary = wins.isEmpty
                ? "Finished \(title). Your logged sets are on Home for today."
                : "Finished \(title). \(wins)"
            store.append(ConversationMessage(actor: .assistant, text: summary))
            onWorkoutSaved?()
            store.setActivity(.awaitingUser)
            store.setQuickActions(Self.defaultQuickActions + ConversationDefaults.gymStartQuickActions)
        } catch {
            errorMessage = "Could not finish the workout."
            store.append(ConversationMessage(actor: .assistant, text: errorMessage!))
            if let session = strengthConversation.session {
                store.setActivity(
                    StrengthConversationActivityCodec.makeActivity(
                        phase: .active,
                        sessionID: session.sessionID
                    )
                )
                store.setQuickActions(ConversationDefaults.strengthConversationQuickActions)
            } else {
                store.setActivity(.awaitingUser)
            }
        }
    }

    private func deactivateStrengthConversationCards() {
        let strengthCardTypes: Set<String> = [
            StrengthConversationCapabilityID.workoutOverviewCardType,
            StrengthConversationCapabilityID.exerciseWorkspaceCardType,
            StrengthConversationCapabilityID.photoReviewCardType,
        ]
        store.mutate { conversation in
            conversation.messages = conversation.messages.map { message in
                guard let card = message.card,
                      strengthCardTypes.contains(card.typeID)
                else { return message }
                return ConversationMessage(
                    id: message.id,
                    actor: message.actor,
                    createdAt: message.createdAt,
                    text: message.text,
                    attachment: message.attachment,
                    card: ConversationCard(
                        id: card.id,
                        typeID: card.typeID,
                        payload: card.payload,
                        isInteractive: false
                    ),
                    quickActions: message.quickActions
                )
            }
        }
    }

    private func appendOrRefreshWorkoutPlanCard(interactive: Bool = true) {
        guard let payload = gym.makeWorkoutPlanCardPayload() else { return }
        if let existingIndex = store.active.messages.lastIndex(where: {
            $0.card?.typeID == GymCapabilityID.workoutPlanCardType
        }) {
            store.mutate { conversation in
                let message = conversation.messages[existingIndex]
                conversation.messages[existingIndex] = ConversationMessage(
                    id: message.id,
                    actor: message.actor,
                    createdAt: message.createdAt,
                    text: message.text,
                    attachment: message.attachment,
                    card: GymWorkoutPlanCardCodec.makeCard(payload: payload, interactive: interactive),
                    quickActions: message.quickActions
                )
            }
        } else {
            store.append(
                ConversationMessage(
                    actor: .assistant,
                    card: GymWorkoutPlanCardCodec.makeCard(payload: payload, interactive: interactive)
                )
            )
        }
    }

    private func replaceGymSetCardPayload(
        cardID: UUID,
        payload: GymSetConfirmationCardPayload,
        interactive: Bool = true
    ) {
        store.mutate { conversation in
            conversation.messages = conversation.messages.map { message in
                guard let card = message.card, card.id == cardID else { return message }
                let updated = GymSetConfirmationCardCodec.makeCard(payload: payload, interactive: interactive)
                return ConversationMessage(
                    id: message.id,
                    actor: message.actor,
                    createdAt: message.createdAt,
                    text: message.text,
                    attachment: message.attachment,
                    card: ConversationCard(
                        id: card.id,
                        typeID: updated.typeID,
                        payload: updated.payload,
                        isInteractive: interactive
                    ),
                    quickActions: message.quickActions
                )
            }
        }
        if var draft = gym.pendingSetDraft, draft.draftID == payload.draftID {
            draft.selectedExerciseID = payload.selectedExerciseID
            draft.selectedExerciseName = payload.selectedExerciseName
            draft.weightValue = payload.weightValue
            draft.weightUnit = payload.weightUnit
            draft.repetitions = payload.repetitions
            gym.updatePendingDraft(draft)
        }
    }

    private func cancelGymSetCard(cardID: UUID, payload: GymSetConfirmationCardPayload) {
        replaceGymSetCardPayload(cardID: cardID, payload: payload, interactive: false)
        gym.clearPendingSetDraft()
    }

    // MARK: - Conversational strength workout

    func handleGymArrival() async {
        guard !isHandlingGymArrival else { return }
        isHandlingGymArrival = true
        defer { isHandlingGymArrival = false }

        store.setActivity(.processing(reason: "starting_strength_workout"))
        store.setQuickActions([])
        do {
            let result = try await strengthConversation.startOrResumeFromGymArrival()
            try await presentConversationalStrengthStartResult(result)
            if ProcessInfo.processInfo.environment["UITEST_AUTO_SUBMIT_STRENGTH_PHOTOS"] == "1"
                || ImageDomainUITestSupport.autoSubmitPhoto
            {
                Task {
                    try? await Task.sleep(nanoseconds: 300_000_000)
                    await submitStrengthFixturePhotosForTesting()
                }
            }
        } catch {
            errorMessage = "Could not start today's workout."
            store.append(ConversationMessage(actor: .assistant, text: errorMessage!))
            store.setActivity(.awaitingUser)
            store.setQuickActions(Self.defaultQuickActions)
        }
    }

    private func performStrengthPhotoSend(text: String, photos: [Data]) async {
        store.updateComposer {
            $0.text = ""
            $0.pendingPhotoJPEG = nil
            $0.pendingPhotoJPEGs = []
        }
        if !text.isEmpty {
            store.append(ConversationMessage(actor: .user, text: text))
        }

        var evidenceAttachmentIDs: [UUID] = []
        for photo in photos {
            if let attachment = try? ConversationAttachment.storedPhotoJPEG(photo) {
                evidenceAttachmentIDs.append(attachment.id)
            }
        }

        if !photos.isEmpty {
            let attachment: ConversationAttachment?
            if let attachmentID = evidenceAttachmentIDs.first {
                attachment = ConversationAttachment(id: attachmentID, kind: .photoJPEGFile)
            } else {
                attachment = ConversationAttachment(kind: .photoJPEG(photos[0]))
            }
            store.append(
                ConversationMessage(
                    actor: .user,
                    text: photos.count == 1 ? "📷 Gym photo" : "📷 \(photos.count) gym photos",
                    attachment: attachment
                )
            )
        }

        store.setActivity(.processing(reason: "interpreting_gym_photo"))
        store.setQuickActions([])

        do {
            let review = try await strengthConversation.interpretPhotoEvidence(
                photos,
                evidenceAttachmentIDs: evidenceAttachmentIDs
            )
            if let clarification = photoClarificationMessage(for: review) {
                store.append(ConversationMessage(actor: .assistant, text: clarification))
            }
            guard let payload = strengthConversation.makePhotoReviewCardPayload(from: review) else { return }
            store.append(
                ConversationMessage(
                    actor: .assistant,
                    card: StrengthPhotoReviewCardCodec.makeCard(payload: payload, interactive: true)
                )
            )
            if let session = strengthConversation.session {
                store.setActivity(
                    StrengthConversationActivityCodec.makeActivity(
                        phase: .reviewingPhoto,
                        sessionID: session.sessionID
                    )
                )
            }
            scheduleImageDomainCorrectionForTestingIfNeeded()
        } catch {
            if let failure = error as? ImageInterpretationFailure {
                await handleImageInterpretationFailure(
                    failure,
                    photos: photos,
                    submittedViaGymRoute: true
                )
                if case .processing(let reason) = store.active.activity, reason == "interpreting_gym_photo" {
                    restoreStrengthActivityAfterPhotoFailure()
                }
                return
            }
            errorMessage = "Could not read those photos. Try another angle or choose an exercise manually."
            store.append(ConversationMessage(actor: .assistant, text: errorMessage!))
            if let session = strengthConversation.session {
                store.setActivity(
                    StrengthConversationActivityCodec.makeActivity(
                        phase: .active,
                        sessionID: session.sessionID
                    )
                )
            }
            store.setQuickActions(ConversationDefaults.strengthConversationQuickActions)
        }
    }

    func handleStrengthPhotoReviewAction(
        _ action: StrengthConversationCapabilityID.CardAction,
        cardID: UUID,
        payload: StrengthPhotoReviewCardPayload
    ) {
        switch action {
        case .applyPhotoReview:
            Task { await applyStrengthPhotoReview(cardID: cardID, payload: payload) }
        case .dismissPhotoReview:
            strengthConversation.dismissPhotoReview(reviewID: payload.reviewID)
            replaceStrengthPhotoReviewCard(cardID: cardID, payload: payload, interactive: false)
        default:
            break
        }
    }

    private func applyStrengthPhotoReview(
        cardID: UUID,
        payload: StrengthPhotoReviewCardPayload
    ) async {
        do {
            let exerciseInstanceID = try await strengthConversation.applyPhotoReview(
                reviewID: payload.reviewID,
                fallbackPayload: payload
            )
            var applied = payload
            applied.isApplied = true
            replaceStrengthPhotoReviewCard(cardID: cardID, payload: applied, interactive: false)
            appendOrActivateStrengthExerciseWorkspace(exerciseInstanceID: exerciseInstanceID)
            onWorkoutSaved?()
            if let session = strengthConversation.session {
                store.setActivity(
                    StrengthConversationActivityCodec.makeActivity(
                        phase: .active,
                        sessionID: session.sessionID
                    )
                )
            }
            store.setQuickActions(ConversationDefaults.strengthConversationQuickActions)
        } catch {
            errorMessage = "Could not apply that photo result."
            store.append(ConversationMessage(actor: .assistant, text: errorMessage!))
        }
    }

    func handleStrengthExerciseWorkspaceAction(
        _ action: StrengthConversationCapabilityID.CardAction,
        cardID: UUID,
        exerciseInstanceID: UUID,
        weight: Double,
        reps: Int
    ) {
        switch action {
        case .confirmSet:
            Task { await confirmStrengthSet(cardID: cardID, exerciseInstanceID: exerciseInstanceID, weight: weight, reps: reps) }
        case .skipSet:
            Task { await skipStrengthSet(cardID: cardID, exerciseInstanceID: exerciseInstanceID) }
        case .addEvidence:
            needsGymCamera = true
        case .openDedicatedWorkout:
            Task { await self.openDedicatedStrengthWorkout() }
        default:
            break
        }
    }

    func activateStrengthExerciseWorkspace(exerciseInstanceID: UUID) {
        Task {
            try? await strengthConversation.workoutController.selectExercise(
                exerciseInstanceID: exerciseInstanceID
            )
            refreshStrengthExerciseWorkspaceCards()
            onWorkoutSaved?()
        }
    }

    func handleStrengthOverviewProgression(exerciseID: String, accept: Bool) {
        Task {
            do {
                if accept {
                    try await strengthConversation.acceptProgressionProposal(exerciseID: exerciseID)
                } else {
                    try await strengthConversation.holdProgressionProposal(exerciseID: exerciseID)
                }
                appendOrRefreshStrengthOverviewCard()
                onWorkoutSaved?()
            } catch {
                errorMessage = "Could not update that progression."
            }
        }
    }

    func handleStrengthOverviewAcceptAllProgressions() {
        Task {
            do {
                try await strengthConversation.acceptAllProgressionProposals()
                appendOrRefreshStrengthOverviewCard()
                onWorkoutSaved?()
            } catch {
                errorMessage = "Could not accept progressions."
            }
        }
    }

    /// UITest hook — submits deterministic fixture photos without camera or PhotosPicker.
    func submitStrengthFixturePhotosForTesting() async {
        await performStrengthPhotoSend(
            text: "",
            photos: StrengthConversationTestFixtures.multiPhotoEvidence
        )
    }

    private func openDedicatedStrengthWorkout() async {
        if usesShellWorkoutEntryRouting {
            onRequestStrengthWorkoutResume?(.conversation)
            return
        }
        if let coordinator = strengthWorkoutCoordinator,
           let presentation = try? await coordinator.buildResumePresentation(source: .conversation) {
            onPresentStrengthWorkout?(presentation)
        }
    }

    func handleStrengthExerciseDraftChange(
        exerciseInstanceID: UUID,
        weight: Double,
        reps: Int
    ) {
        Task {
            try? await strengthConversation.updateCurrentSetDraft(
                exerciseInstanceID: exerciseInstanceID,
                weight: weight,
                reps: reps
            )
            refreshStrengthExerciseWorkspaceCards()
        }
    }

    private func confirmStrengthSet(
        cardID: UUID,
        exerciseInstanceID: UUID,
        weight: Double,
        reps: Int
    ) async {
        store.setActivity(.processing(reason: "saving_gym_set"))
        do {
            try await strengthConversation.confirmSet(
                exerciseInstanceID: exerciseInstanceID,
                weight: weight,
                reps: reps
            )
            refreshStrengthExerciseWorkspaceCard(cardID: cardID, exerciseInstanceID: exerciseInstanceID)
            appendOrRefreshStrengthOverviewCard()
            onWorkoutSaved?()

            if let exercise = strengthConversation.session?.exercises.first(where: { $0.id == exerciseInstanceID }),
               exercise.status == .completed,
               let name = strengthConversation.session?.exercises.first(where: { $0.id == exerciseInstanceID })?.displayName {
                store.append(
                    ConversationMessage(
                        actor: .assistant,
                        text: "\(name) complete."
                    )
                )
            }

            if let session = strengthConversation.session {
                store.setActivity(
                    StrengthConversationActivityCodec.makeActivity(
                        phase: .active,
                        sessionID: session.sessionID
                    )
                )
            }
            store.setQuickActions(ConversationDefaults.strengthConversationQuickActions)
        } catch {
            errorMessage = "Could not save this set."
            store.append(ConversationMessage(actor: .assistant, text: errorMessage!))
        }
    }

    private func skipStrengthSet(cardID: UUID, exerciseInstanceID: UUID) async {
        do {
            try await strengthConversation.skipSet(exerciseInstanceID: exerciseInstanceID)
            refreshStrengthExerciseWorkspaceCard(cardID: cardID, exerciseInstanceID: exerciseInstanceID)
            appendOrRefreshStrengthOverviewCard()
            onWorkoutSaved?()
        } catch {
            errorMessage = "Could not skip this set."
            store.append(ConversationMessage(actor: .assistant, text: errorMessage!))
        }
    }

    private func appendOrRefreshStrengthOverviewCard(interactive: Bool = true) {
        guard let payload = strengthConversation.makeOverviewCardPayload() else { return }
        if let existingIndex = store.active.messages.lastIndex(where: {
            $0.card?.typeID == StrengthConversationCapabilityID.workoutOverviewCardType
        }) {
            store.mutate { conversation in
                let message = conversation.messages[existingIndex]
                conversation.messages[existingIndex] = ConversationMessage(
                    id: message.id,
                    actor: message.actor,
                    createdAt: message.createdAt,
                    text: message.text,
                    attachment: message.attachment,
                    card: StrengthWorkoutOverviewCardCodec.makeCard(payload: payload, interactive: interactive),
                    quickActions: message.quickActions
                )
            }
        } else {
            store.append(
                ConversationMessage(
                    actor: .assistant,
                    card: StrengthWorkoutOverviewCardCodec.makeCard(payload: payload, interactive: interactive)
                )
            )
        }
    }

    private func appendOrActivateStrengthExerciseWorkspace(exerciseInstanceID: UUID) {
        guard let payload = strengthConversation.makeExerciseWorkspacePayload(
            exerciseInstanceID: exerciseInstanceID
        ) else { return }

        if let existingIndex = store.active.messages.lastIndex(where: {
            guard let card = $0.card,
                  card.typeID == StrengthConversationCapabilityID.exerciseWorkspaceCardType,
                  let existing = StrengthExerciseWorkspaceCardCodec.decode(card.payload)
            else { return false }
            return existing.exerciseInstanceID == exerciseInstanceID
        }) {
            refreshStrengthExerciseWorkspaceCard(
                cardID: store.active.messages[existingIndex].card!.id,
                exerciseInstanceID: exerciseInstanceID
            )
            return
        }

        store.append(
            ConversationMessage(
                actor: .assistant,
                card: StrengthExerciseWorkspaceCardCodec.makeCard(payload: payload, interactive: true)
            )
        )
    }

    private func refreshStrengthExerciseWorkspaceCards() {
        for message in store.active.messages {
            guard let card = message.card,
                  card.typeID == StrengthConversationCapabilityID.exerciseWorkspaceCardType,
                  let payload = StrengthExerciseWorkspaceCardCodec.decode(card.payload)
            else { continue }
            refreshStrengthExerciseWorkspaceCard(
                cardID: card.id,
                exerciseInstanceID: payload.exerciseInstanceID
            )
        }
    }

    private func refreshStrengthExerciseWorkspaceCard(cardID: UUID, exerciseInstanceID: UUID) {
        guard let payload = strengthConversation.makeExerciseWorkspacePayload(
            exerciseInstanceID: exerciseInstanceID
        ) else { return }
        store.mutate { conversation in
            conversation.messages = conversation.messages.map { message in
                guard let card = message.card, card.id == cardID else { return message }
                let updated = StrengthExerciseWorkspaceCardCodec.makeCard(payload: payload, interactive: true)
                return ConversationMessage(
                    id: message.id,
                    actor: message.actor,
                    createdAt: message.createdAt,
                    text: message.text,
                    attachment: message.attachment,
                    card: ConversationCard(
                        id: card.id,
                        typeID: updated.typeID,
                        payload: updated.payload,
                        isInteractive: true
                    ),
                    quickActions: message.quickActions
                )
            }
        }
    }

    private func replaceStrengthPhotoReviewCard(
        cardID: UUID,
        payload: StrengthPhotoReviewCardPayload,
        interactive: Bool
    ) {
        store.mutate { conversation in
            conversation.messages = conversation.messages.map { message in
                guard let card = message.card, card.id == cardID else { return message }
                let updated = StrengthPhotoReviewCardCodec.makeCard(payload: payload, interactive: interactive)
                return ConversationMessage(
                    id: message.id,
                    actor: message.actor,
                    createdAt: message.createdAt,
                    text: message.text,
                    attachment: message.attachment,
                    card: ConversationCard(
                        id: card.id,
                        typeID: updated.typeID,
                        payload: updated.payload,
                        isInteractive: interactive
                    ),
                    quickActions: message.quickActions
                )
            }
        }
    }

    private func supersedeUnconfirmedImageArtifacts() {
        store.freezeInteractiveCards(typeID: MealCapabilityID.estimateCardType)
        store.freezeInteractiveCards(typeID: StrengthConversationCapabilityID.photoReviewCardType)
        if let reviewID = strengthConversation.pendingPhotoReview?.reviewID {
            strengthConversation.dismissPhotoReview(reviewID: reviewID)
        }
        meal.syncUnloggedDrafts(from: [])
    }

    private func latestUserPhotoJPEG() -> Data? {
        for message in store.active.messages.reversed() {
            guard message.actor == .user, let attachment = message.attachment else { continue }
            if let data = ConversationAttachmentStore.shared.resolvedJPEGData(for: attachment) {
                return data
            }
        }
        return nil
    }

    private func handleImageDomainCorrection(_ intent: ImageDomainCorrectionIntent) async {
        guard let photo = latestUserPhotoJPEG() else {
            store.append(
                ConversationMessage(
                    actor: .assistant,
                    text: "I don't have a recent photo to correct. Send the image again and tell me what it is."
                )
            )
            store.setActivity(.awaitingUser)
            store.setQuickActions(ConversationDefaults.strengthConversationQuickActions)
            return
        }

        supersedeUnconfirmedImageArtifacts()

        switch intent {
        case .reclassifyAsMeal:
            store.append(
                ConversationMessage(
                    actor: .assistant,
                    text: "Got it — I'll treat that as a meal."
                )
            )
            await runInterpretation(userText: "", photoJPEG: photo)
        case .reclassifyAsGym:
            guard hasActiveStrengthConversation else {
                store.append(
                    ConversationMessage(
                        actor: .assistant,
                        text: "Got it — that looks like gym equipment. Start or resume a workout if you want to apply it."
                    )
                )
                store.setActivity(.awaitingUser)
                return
            }
            store.append(
                ConversationMessage(
                    actor: .assistant,
                    text: "Got it — I'll treat that as gym equipment."
                )
            )
            await performStrengthPhotoSend(text: "", photos: [photo])
        }
    }

    private func handleImageInterpretationFailure(
        _ failure: ImageInterpretationFailure,
        photos: [Data],
        submittedViaGymRoute: Bool
    ) async {
        switch failure {
        case .wrongDomain(_, let actual, _) where actual == .meal && submittedViaGymRoute:
            supersedeUnconfirmedImageArtifacts()
            store.append(
                ConversationMessage(
                    actor: .assistant,
                    text: "This looks like a meal rather than gym equipment. Here's a draft estimate — confirm before logging."
                )
            )
            await runInterpretation(userText: "", photoJPEG: photos.first)
        case .wrongDomain(_, let actual, _) where actual == .gymEquipment && !submittedViaGymRoute && hasActiveStrengthConversation:
            supersedeUnconfirmedImageArtifacts()
            store.append(
                ConversationMessage(
                    actor: .assistant,
                    text: "This looks like gym equipment rather than a meal. Review it before applying to your workout."
                )
            )
            await performStrengthPhotoSend(text: "", photos: photos)
        case .ambiguous:
            store.append(
                ConversationMessage(
                    actor: .assistant,
                    text: ImageInterpretationFailurePresentation.message(for: failure)
                )
            )
            if let session = strengthConversation.session {
                store.setActivity(
                    StrengthConversationActivityCodec.makeActivity(
                        phase: .active,
                        sessionID: session.sessionID
                    )
                )
            } else {
                store.setActivity(.awaitingUser)
            }
            store.setQuickActions(ConversationDefaults.strengthConversationQuickActions)
        default:
            errorMessage = ImageInterpretationFailurePresentation.message(for: failure)
            store.append(ConversationMessage(actor: .assistant, text: errorMessage!))
            if let session = strengthConversation.session {
                store.setActivity(
                    StrengthConversationActivityCodec.makeActivity(
                        phase: .active,
                        sessionID: session.sessionID
                    )
                )
            } else {
                store.setActivity(.awaitingUser)
            }
            store.setQuickActions(ConversationDefaults.strengthConversationQuickActions)
        }
    }

    private func scheduleImageDomainCorrectionForTestingIfNeeded() {
        guard ImageDomainUITestSupport.autoSubmitCorrection,
              ImageDomainUITestSupport.scenario == .wrongGymArtifact
        else { return }
        Task {
            try? await Task.sleep(nanoseconds: 400_000_000)
            store.updateComposer { $0.text = "Thats my lunch" }
            await sendComposer()
        }
    }

    private func restoreStrengthActivityAfterPhotoFailure() {
        if let session = strengthConversation.session {
            store.setActivity(
                StrengthConversationActivityCodec.makeActivity(
                    phase: .active,
                    sessionID: session.sessionID
                )
            )
            store.setQuickActions(ConversationDefaults.strengthConversationQuickActions)
        } else {
            store.setActivity(.awaitingUser)
            store.setQuickActions(Self.defaultQuickActions)
        }
    }

    private func photoClarificationMessage(for review: StrengthPhotoReviewState) -> String? {
        if review.detectedExerciseID == nil,
           review.interpretation.exerciseCandidates.count > 1 {
            return "I found a few possible matches. Choose the exercise on the review card before applying."
        }
        if review.detectedExerciseID == nil {
            return "I couldn't match this to a planned exercise. Pick the closest option, send a clearer machine label, or choose an exercise manually."
        }
        if review.suggestedWeight == nil,
           review.interpretation.detectedWeight == nil,
           let name = review.detectedExerciseName {
            return "I identified the \(name), but I couldn't read the selected weight. You can enter it manually after applying."
        }
        return nil
    }

    private static func preferredWeightUnit() -> String {
        Locale.current.measurementSystem == .us ? "lb" : "kg"
    }

    private func logWorkoutStartConflictEvent(
        _ event: String,
        resolution: GymWorkoutStartConflictResolution? = nil,
        conflict: GymWorkoutStartConflict? = nil,
        target: GymPlanWorkoutTarget? = nil,
        activeSessionID: UUID? = nil,
        activeStatus: GymWorkoutSessionStatus? = nil,
        finishedSessionID: UUID? = nil,
        navigation: String? = nil,
        error: String? = nil
    ) {
        #if DEBUG
        var parts = ["event=\(event)"]
        if let resolution {
            parts.append("resolution=\(resolution)")
        }
        if let conflict {
            parts.append("activePlan=\(conflict.activePlanReference.storageKey)")
            parts.append("requestedPlan=\(conflict.requestedPlanReference.storageKey)")
            parts.append("requestedSection=\(conflict.requestedWorkoutTarget.sectionIndex)")
        }
        if let target {
            parts.append("targetPlan=\(target.reference.storageKey)")
            parts.append("targetSection=\(target.sectionIndex)")
        }
        if let activeSessionID {
            parts.append("activeSessionID=\(activeSessionID.uuidString)")
        }
        if let activeStatus {
            parts.append("activeStatus=\(activeStatus.rawValue)")
        }
        if let finishedSessionID {
            parts.append("finishedSessionID=\(finishedSessionID.uuidString)")
        }
        if let navigation {
            parts.append("navigation=\(navigation)")
        }
        if let error {
            parts.append("error=\(error)")
        }
        print("[GymWorkoutStartConflict] \(parts.joined(separator: " "))")
        #endif
    }
}
