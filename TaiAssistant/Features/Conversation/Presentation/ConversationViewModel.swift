import Foundation
import Observation

@MainActor
@Observable
final class ConversationViewModel {
    let store: ConversationSessionStore
    let meal: MealCapabilityController
    let liveTai: LiveTaiCapabilityController
    let assistantName: String
    var onMealSaved: (() -> Void)?

    private(set) var needsCamera = false
    private(set) var needsAIConsent = false
    private(set) var pendingConsentKind: AIDataProcessingConsentKind = .mealAndGoal
    private var pendingAfterConsent: (() -> Void)?

    /// Last Live Tai ask retained for Retry without duplicating the user turn.
    private(set) var pendingLiveTaiRetryAsk: String?
    /// Original text awaiting clarify → Log meal / Ask about it (no duplicate user turn).
    private(set) var pendingClarificationText: String?
    /// Evidence for the most recent Live Tai reply (Why sheet).
    private(set) var latestLiveTaiEvidence: LiveTaiEvidencePayload?
    var showLiveTaiWhy = false

    var conversation: ActiveConversation { store.snapshotIncludingComposer }
    var composer: ConversationComposerState { store.composerDraft }
    var errorMessage: String?
    var isProcessing: Bool {
        if case .processing = store.active.activity { return true }
        return meal.isBusy
    }

    /// Durable targeted meal refinement draft ID (restored from activity payload).
    var targetedMealDraftID: UUID? {
        MealCapabilityActivityCodec.targetedDraftID(from: store.active.activity)
    }

    static let defaultQuickActions: [ConversationQuickAction] = ConversationDefaults.mealQuickActions

    init(
        store: ConversationSessionStore,
        meal: MealCapabilityController,
        liveTai: LiveTaiCapabilityController,
        assistantName: String,
        onMealSaved: (() -> Void)? = nil
    ) {
        self.store = store
        self.meal = meal
        self.liveTai = liveTai
        self.assistantName = assistantName
        self.onMealSaved = onMealSaved
    }

    func startIfNeeded() {
        guard store.active.messages.isEmpty else { return }
        seedGreeting()
    }

    /// Deep-link from Home: open Tai ready for meal logging.
    func applyMealIntent() {
        startIfNeeded()
        clearTargetedMealRefinement()
        meal.beginCollecting()
        store.setActivity(MealCapabilityActivityCodec.makeActivity(phase: .collecting))
        store.append(
            ConversationMessage(
                actor: .assistant,
                text: "Let’s log a meal. Take a photo or describe what you ate."
            )
        )
        store.setQuickActions(Self.defaultQuickActions.filter {
            $0.id == MealCapabilityID.QuickAction.takePhoto
                || $0.id == MealCapabilityID.QuickAction.describeMeal
        })
    }

    func handleQuickAction(_ action: ConversationQuickAction) {
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
        }
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

    func updateComposerText(_ text: String) {
        store.updateComposer { $0.text = text }
    }

    func clearPendingPhoto() {
        store.updateComposer { $0.pendingPhotoJPEG = nil }
    }

    func sendComposer() async {
        let text = store.composerDraft.text.trimmingCharacters(in: .whitespacesAndNewlines)
        let photo = store.composerDraft.pendingPhotoJPEG
        guard !text.isEmpty || photo != nil else { return }

        let route = ConversationRouter.route(
            text: text,
            hasPhoto: photo != nil,
            targetedMealDraftID: targetedMealDraftID,
            isExplicitMealCaptureIntent: ConversationRouter.isMealCollecting(store.active.activity)
        )

        switch route {
        case .clarifyMealOrAsk:
            presentMealOrAskClarification(originalText: text)
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
            await performMealSend(text: text, photo: photo, route: route)
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
            store.append(
                ConversationMessage(
                    actor: .assistant,
                    text: "Great — tap Log Meal when you’re ready to save it."
                )
            )
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
        case .liveTai, .clarifyMealOrAsk:
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

        let outcome = await meal.interpret(userText: userText, photoJPEG: photoJPEG, targetDraftID: nil)
        switch outcome {
        case .failure(let message):
            errorMessage = message
            store.append(ConversationMessage(actor: .assistant, text: message))
            store.setActivity(.awaitingUser)
            store.setQuickActions(Self.defaultQuickActions)

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
            store.setQuickActions([])
        }
    }

    private func runTargetedRefinement(userText: String, draftID: UUID) async {
        store.setActivity(.processing(reason: "interpreting_meal"))
        store.setQuickActions([])

        let outcome = await meal.interpret(userText: userText, photoJPEG: nil, targetDraftID: draftID)
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

        case .success(let success):
            guard let updated = success.drafts.first(where: { $0.id == draftID }) ?? success.drafts.first else {
                store.setActivity(MealCapabilityActivityCodec.makeActivity(
                    phase: .reviewing,
                    targetedDraftID: draftID
                ))
                return
            }
            if let note = success.assistantNote {
                store.append(ConversationMessage(actor: .assistant, text: note))
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
                    text: "Logged \(draft.label). Nice work — anything else I can help with?"
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
}
