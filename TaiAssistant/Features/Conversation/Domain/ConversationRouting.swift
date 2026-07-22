import Foundation

// MARK: - Routing

enum ConversationInputRoute: Equatable, Sendable {
    case liveTai
    case mealInterpret
    case mealRefine(draftID: UUID)
    /// Ambiguous food fragment — ask whether to log or ask about it.
    case clarifyMealOrAsk
    case gymStart(GymProgramTemplateID)
    case gymFinish
    case gymSetPhoto
    case gymOpenPlanImport
    case gymImportPasteText(String)
    case gymShowCurrentProgram
}

enum ConversationRouter {
    /// Deterministic routing priority:
    /// 1) targeted meal refinement
    /// 2) photo
    /// 3) explicit meal capture intent
    /// 4) high-confidence NL meal log statement
    /// 5) ambiguous food fragment → clarify
    /// 6) everything else → Live Tai
    ///
    /// Never infers a meal refine target from the “latest” draft.
    /// Pending meal cards alone never hijack general questions.
    static func route(
        text: String,
        hasPhoto: Bool,
        targetedMealDraftID: UUID?,
        isExplicitMealCaptureIntent: Bool = false,
        hasActiveGymSession: Bool = false
    ) -> ConversationInputRoute {
        if hasActiveGymSession {
            if hasPhoto {
                return .gymSetPhoto
            }
            switch ConversationGymIntentClassifier.classify(text) {
            case .finishWorkout:
                return .gymFinish
            case .startUpperBody, .startLowerBody:
                return .liveTai
            case .openPlanImport, .replacePlan:
                return .gymOpenPlanImport
            case .pastePlanText(let planText):
                return .gymImportPasteText(planText)
            case .showCurrentProgram:
                return .gymShowCurrentProgram
            case .general:
                return .liveTai
            }
        }

        switch ConversationGymIntentClassifier.classify(text) {
        case .startUpperBody:
            return .gymStart(.upperBody)
        case .startLowerBody:
            return .gymStart(.lowerBody)
        case .finishWorkout:
            return .liveTai
        case .openPlanImport, .replacePlan:
            return .gymOpenPlanImport
        case .pastePlanText(let planText):
            return .gymImportPasteText(planText)
        case .showCurrentProgram:
            return .gymShowCurrentProgram
        case .general:
            break
        }

        if let targetedMealDraftID {
            return .mealRefine(draftID: targetedMealDraftID)
        }
        if hasPhoto || isExplicitMealCaptureIntent {
            return .mealInterpret
        }

        switch ConversationMealIntentClassifier.classify(text) {
        case .mealLogStatement:
            return .mealInterpret
        case .ambiguousFoodFragment:
            return .clarifyMealOrAsk
        case .coachingQuestion, .general:
            return .liveTai
        }
    }

    /// True when Conversation activity is an explicit meal capture (Describe Meal / start meal), not idle review cards.
    static func isMealCollecting(_ activity: ConversationActivity) -> Bool {
        guard case let .capability(capabilityID, phaseID, _) = activity,
              capabilityID == MealCapabilityID.capability,
              phaseID == MealCapabilityID.Phase.collecting.rawValue
        else { return false }
        return true
    }

    static func isGymActive(_ activity: ConversationActivity) -> Bool {
        guard case let .capability(capabilityID, phaseID, _) = activity,
              capabilityID == GymCapabilityID.capability
        else { return false }
        return phaseID != GymCapabilityID.Phase.idle.rawValue
            && phaseID != GymCapabilityID.Phase.completed.rawValue
    }
}

// MARK: - Quick-action allowlist

/// Controlled allowlist for proxy-suggested or app quick actions.
/// Arbitrary model-generated identifiers must never drive navigation, persistence or capabilities.
enum ConversationAllowedQuickAction: String, CaseIterable, Sendable {
    case mealTakePhoto = "meal.takePhoto"
    case mealDescribeMeal = "meal.describeMeal"
    case mealAskTai = "meal.askTai"
    case mealCancelRefine = "meal.cancelRefine"
    case mealLogIt = "meal.logIt"
    case liveTaiAskAboutIt = "liveTai.askAboutIt"
    case liveTaiRetry = "liveTai.retry"
    case liveTaiWhy = "liveTai.why"
    case gymStartUpperBody = "gym.startUpperBody"
    case gymStartLowerBody = "gym.startLowerBody"
    case gymManagePlans = "gym.managePlans"
    case gymTakeSetPhoto = "gym.takeSetPhoto"
    case gymFinishWorkout = "gym.finishWorkout"
    case gymResumeWorkout = "gym.resumeWorkout"

    var title: String {
        switch self {
        case .mealTakePhoto: return "Take Photo"
        case .mealDescribeMeal: return "Describe Meal"
        case .mealAskTai: return "Ask Tai"
        case .mealCancelRefine: return "Cancel change"
        case .mealLogIt: return "Log meal"
        case .liveTaiAskAboutIt: return "Ask about it"
        case .liveTaiRetry: return "Retry"
        case .liveTaiWhy: return "Why?"
        case .gymStartUpperBody: return "Upper Body"
        case .gymStartLowerBody: return "Lower Body"
        case .gymManagePlans: return "Gym Plans"
        case .gymTakeSetPhoto: return "Take Photo"
        case .gymFinishWorkout: return "Finish Workout"
        case .gymResumeWorkout: return "Resume Workout"
        }
    }

    var systemImage: String? {
        switch self {
        case .mealTakePhoto: return "camera.fill"
        case .mealDescribeMeal: return "fork.knife"
        case .mealAskTai: return "bubble.left.fill"
        case .mealCancelRefine: return "xmark.circle"
        case .mealLogIt: return "checkmark.circle"
        case .liveTaiAskAboutIt: return "bubble.left"
        case .liveTaiRetry: return "arrow.clockwise"
        case .liveTaiWhy: return "questionmark.circle"
        case .gymStartUpperBody: return "figure.strengthtraining.traditional"
        case .gymStartLowerBody: return "figure.run"
        case .gymManagePlans: return "list.bullet.rectangle"
        case .gymTakeSetPhoto: return "camera.fill"
        case .gymFinishWorkout: return "flag.checkered"
        case .gymResumeWorkout: return "arrow.clockwise.circle"
        }
    }

    static func resolve(_ id: String) -> ConversationAllowedQuickAction? {
        ConversationAllowedQuickAction(rawValue: id)
    }

    func asConversationQuickAction() -> ConversationQuickAction {
        ConversationQuickAction(
            id: rawValue,
            title: title,
            systemImage: systemImage
        )
    }
}

enum ConversationQuickActionAllowlist {
    /// Maps proxy-provided actions onto the allowlist. Unknown ids are dropped (never interactive).
    static func mapProxyActions(
        _ actions: [AICoachQuickAction]
    ) -> [ConversationQuickAction] {
        actions.compactMap { action in
            guard let allowed = ConversationAllowedQuickAction.resolve(action.id) else {
                return nil
            }
            let title: String
            switch allowed {
            case .liveTaiWhy, .liveTaiRetry:
                let trimmed = action.title.trimmingCharacters(in: .whitespacesAndNewlines)
                title = trimmed.isEmpty ? allowed.title : trimmed
            default:
                title = allowed.title
            }
            return ConversationQuickAction(
                id: allowed.rawValue,
                title: title,
                systemImage: allowed.systemImage
            )
        }
    }

    /// Non-interactive suggestion labels for unknown proxy action titles (display only).
    static func nonInteractiveSuggestions(
        from actions: [AICoachQuickAction]
    ) -> [String] {
        actions.compactMap { action in
            guard ConversationAllowedQuickAction.resolve(action.id) == nil else { return nil }
            let title = action.title.trimmingCharacters(in: .whitespacesAndNewlines)
            return title.isEmpty ? nil : title
        }
    }
}
