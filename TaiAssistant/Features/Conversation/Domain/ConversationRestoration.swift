import Foundation

/// Honest recovery when a Conversation is restored after process death mid-task.
enum ConversationRestoration {
    static let interruptedMealInterpretationMessage = "Meal interpretation was interrupted."
    static let interruptedMealSaveMessage = "Meal save was interrupted. Your meal was not logged — try again when ready."
    static let interruptedGymInterpretationMessage = "Set photo interpretation was interrupted."
    static let interruptedGymSaveMessage = "Set save was interrupted. Your set was not logged — try again when ready."
    static let interruptedLiveTaiMessage = "Tai was interrupted while answering. Your question is still here — tap Retry when you’re ready."

    /// Returns a healed conversation when activity was left in a non-restorable transient state.
    /// Does not duplicate messages if an interruption notice is already the last assistant text.
    /// Targeted meal refinement (`capability` reviewing + draft payload) is restorable and is not healed away.
    static func healInterruptedWork(_ conversation: ActiveConversation) -> (ActiveConversation, didHeal: Bool) {
        var healed = conversation
        switch conversation.activity {
        case .processing(let reason):
            let messageText: String
            if reason == "saving_meal" {
                messageText = interruptedMealSaveMessage
            } else if reason == "saving_gym_set" {
                messageText = interruptedGymSaveMessage
            } else if reason == "interpreting_gym_photo" {
                messageText = interruptedGymInterpretationMessage
            } else if reason == LiveTaiCapabilityController.processingReason {
                messageText = interruptedLiveTaiMessage
            } else {
                messageText = interruptedMealInterpretationMessage
            }
            appendInterruptionNoticeIfNeeded(to: &healed, text: messageText)
            healed.activity = .awaitingUser
            if reason == LiveTaiCapabilityController.processingReason {
                healed.activeQuickActions = [
                    ConversationAllowedQuickAction.liveTaiRetry.asConversationQuickAction()
                ] + ConversationDefaults.mealQuickActions
            } else {
                healed.activeQuickActions = ConversationDefaults.mealQuickActions
            }
            healed.composer.pendingPhotoJPEG = nil
            return (healed, true)

        case .capability(let capabilityID, let phaseID, _):
            // Interpreting/saving phases should not appear as capability; processing covers those.
            // Collecting / reviewing / readyToLog (including targeted refine payload) are restorable.
            if capabilityID == MealCapabilityID.capability,
               phaseID == MealCapabilityID.Phase.interpreting.rawValue
                || phaseID == MealCapabilityID.Phase.saving.rawValue
            {
                let text = phaseID == MealCapabilityID.Phase.saving.rawValue
                    ? interruptedMealSaveMessage
                    : interruptedMealInterpretationMessage
                appendInterruptionNoticeIfNeeded(to: &healed, text: text)
                healed.activity = .awaitingUser
                healed.activeQuickActions = ConversationDefaults.mealQuickActions
                return (healed, true)
            }
            return (conversation, false)

        case .idle, .awaitingUser:
            return (conversation, false)
        }
    }

    /// Interactive unlogged meal estimate cards still on screen after restore.
    static func interactiveUnloggedMealPayloads(in conversation: ActiveConversation) -> [MealEstimateCardPayload] {
        conversation.messages.compactMap { message in
            guard let card = message.card,
                  card.typeID == MealCapabilityID.estimateCardType,
                  card.isInteractive,
                  let payload = MealCardCodec.decode(card.payload),
                  !payload.isLogged
            else { return nil }
            return payload
        }
    }

    private static func appendInterruptionNoticeIfNeeded(to conversation: inout ActiveConversation, text: String) {
        if conversation.messages.last?.text == text { return }
        conversation.messages.append(
            ConversationMessage(actor: .assistant, text: text)
        )
    }
}
