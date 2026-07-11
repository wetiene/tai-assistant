import Foundation
import Observation

@MainActor
@Observable
final class ConversationViewModel {
    let store: ConversationSessionStore
    let meal: MealCapabilityController
    let assistantName: String
    var onMealSaved: (() -> Void)?

    private(set) var needsCamera = false
    private(set) var needsAIConsent = false
    private var pendingAfterConsent: (() -> Void)?

    var conversation: ActiveConversation { store.snapshotIncludingComposer }
    var composer: ConversationComposerState { store.composerDraft }
    var errorMessage: String?
    var isProcessing: Bool {
        if case .processing = store.active.activity { return true }
        return meal.isBusy
    }

    static let defaultQuickActions: [ConversationQuickAction] = ConversationDefaults.mealQuickActions

    init(
        store: ConversationSessionStore,
        meal: MealCapabilityController,
        assistantName: String,
        onMealSaved: (() -> Void)? = nil
    ) {
        self.store = store
        self.meal = meal
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
        meal.beginCollecting()
        store.setActivity(.capability(
            capabilityID: MealCapabilityID.capability,
            phaseID: MealCapabilityID.Phase.collecting.rawValue,
            payload: nil
        ))
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
        switch action.id {
        case MealCapabilityID.QuickAction.takePhoto:
            requestConsentThen {
                self.meal.beginCollecting()
                self.needsCamera = true
            }
        case MealCapabilityID.QuickAction.describeMeal:
            meal.beginCollecting()
            store.setActivity(.capability(
                capabilityID: MealCapabilityID.capability,
                phaseID: MealCapabilityID.Phase.collecting.rawValue,
                payload: nil
            ))
            store.append(
                ConversationMessage(
                    actor: .assistant,
                    text: "What did you have? A short description is enough."
                )
            )
            store.setQuickActions([])
        case MealCapabilityID.QuickAction.askTai:
            store.append(
                ConversationMessage(
                    actor: .user,
                    text: "Ask Tai"
                )
            )
            store.append(
                ConversationMessage(
                    actor: .assistant,
                    text: "I’m here. For now I can help you log meals — try Take Photo or Describe Meal, or just tell me what you ate."
                )
            )
            store.setQuickActions(Self.defaultQuickActions)
        default:
            break
        }
    }

    func dismissCameraRequest() {
        needsCamera = false
    }

    func handleCapturedPhoto(_ jpeg: Data) {
        needsCamera = false
        requestConsentThen {
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

        requestConsentThen {
            Task {
                await self.performSend(text: text, photo: photo)
            }
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
            store.setActivity(.capability(
                capabilityID: MealCapabilityID.capability,
                phaseID: MealCapabilityID.Phase.readyToLog.rawValue,
                payload: nil
            ))
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
            store.setActivity(.capability(
                capabilityID: MealCapabilityID.capability,
                phaseID: MealCapabilityID.Phase.reviewing.rawValue,
                payload: nil
            ))
            store.append(
                ConversationMessage(
                    actor: .assistant,
                    text: "No problem — tell me what to change. For example: “it was grilled chicken,” “much smaller,” or “no cheese.”"
                )
            )
            store.setQuickActions([])

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

    private func requestConsentThen(_ action: @escaping () -> Void) {
        if AIDataProcessingConsentStore.hasAccepted {
            action()
        } else {
            pendingAfterConsent = action
            needsAIConsent = true
        }
    }

    private func performSend(text: String, photo: Data?) async {
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

        await runInterpretation(userText: text, photoJPEG: photo)
    }

    private func sendPhotoAndInterpret(_ jpeg: Data) async {
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

        let outcome = await meal.interpret(userText: userText, photoJPEG: photoJPEG)
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
            store.setActivity(.capability(
                capabilityID: MealCapabilityID.capability,
                phaseID: MealCapabilityID.Phase.reviewing.rawValue,
                payload: nil
            ))
            store.setQuickActions([])
        }
    }

    /// Logs exactly one draft addressed by `payload.draft.id` / `cardID`.
    func logMealDraft(cardID: UUID, payload: MealEstimateCardPayload) async {
        let draftID = payload.draft.id
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
                store.setActivity(.capability(
                    capabilityID: MealCapabilityID.capability,
                    phaseID: (ready ? MealCapabilityID.Phase.readyToLog : MealCapabilityID.Phase.reviewing).rawValue,
                    payload: nil
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

    private func restoreActivityAfterPartialMealState() {
        let remaining = ConversationRestoration.interactiveUnloggedMealPayloads(in: store.active)
        meal.syncUnloggedDrafts(from: remaining)
        if remaining.isEmpty {
            store.setActivity(.awaitingUser)
            store.setQuickActions(Self.defaultQuickActions)
        } else {
            let ready = remaining.contains(where: \.refinementAccepted)
            store.setActivity(.capability(
                capabilityID: MealCapabilityID.capability,
                phaseID: (ready ? MealCapabilityID.Phase.readyToLog : MealCapabilityID.Phase.reviewing).rawValue,
                payload: nil
            ))
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
