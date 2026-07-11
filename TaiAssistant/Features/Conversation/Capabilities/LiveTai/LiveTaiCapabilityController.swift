import Foundation

enum LiveTaiOutcome: Sendable {
    case success(AICoachResponse)
    case failure(String)
}

/// Live Tai coaching capability — advisory only. Never mutates Artifacts.
@MainActor
final class LiveTaiCapabilityController {
    static let processingReason = "live_tai"

    private let mealRepository: MealRepository
    private let goalRepository: GoalRepository
    private let aiService: AIService
    private let ownerID: String
    private let assembler = LiveTaiContextAssembler()

    init(
        mealRepository: MealRepository,
        goalRepository: GoalRepository,
        aiService: AIService,
        ownerID: String
    ) {
        self.mealRepository = mealRepository
        self.goalRepository = goalRepository
        self.aiService = aiService
        self.ownerID = ownerID
    }

    /// Captures a Sendable snapshot from repositories, assembles off MainActor, then calls `/ai/coach`.
    func ask(userAsk: String, conversationMessages: [ConversationMessage]) async -> LiveTaiOutcome {
        let trimmed = userAsk.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return .failure("Add a question and try again.")
        }

        do {
            let snapshot = try await captureSnapshot(userAsk: trimmed, messages: conversationMessages)
            let request = await assembler.assemble(snapshot: snapshot)
            let response = try await aiService.coach(request: request)
            return .success(response)
        } catch {
            return .failure(Self.userFacingError(error))
        }
    }

    // MARK: - Snapshot capture (MainActor / value types only)

    private func captureSnapshot(
        userAsk: String,
        messages: [ConversationMessage]
    ) async throws -> LiveTaiContextSnapshot {
        let bounds = CoachBriefingInputFactory.dayBounds(for: .now)
        let logs = try await mealRepository.fetchMealLogs(
            ownerID: ownerID,
            from: bounds.start,
            to: bounds.end
        )
        let mealSnapshots = LiveTaiContextSnapshotBuilder.mealSnapshots(from: logs)

        let profiles = try await goalRepository.fetchGoalProfiles(ownerID: ownerID)
        let goalProfile = profiles.sorted { $0.updatedAt > $1.updatedAt }.first
        var targets: DailyTargets?
        if let goalProfile {
            targets = try await goalRepository.fetchDailyTargets(goalProfileID: goalProfile.id)
        }
        let goalSnap = LiveTaiContextSnapshotBuilder.goalSnapshot(profile: goalProfile, targets: targets)
        let day = LiveTaiContextSnapshotBuilder.dayNutrition(meals: mealSnapshots, goal: goalSnap)

        return LiveTaiContextSnapshotBuilder.capture(
            userAsk: userAsk,
            messages: messages,
            mealsToday: mealSnapshots,
            goal: goalSnap,
            dayNutrition: day
        )
    }

    private static func userFacingError(_ error: Error) -> String {
        if let ai = error as? AIServiceError {
            switch ai {
            case .transport:
                return "I couldn’t reach Tai’s coaching service. Check your connection and try again."
            case .unexpectedStatusCode:
                return "Tai’s coaching service had a problem. Please try again in a moment."
            case .malformedResponse:
                return "I got an unexpected response. Please try again."
            default:
                break
            }
        }
        return "Something went wrong while asking Tai. Please try again."
    }
}

enum LiveTaiResponsePresentation {
    /// Clean user-facing prose only. Limitations and disclaimers stay in Why / Evidence.
    static func assistantText(from response: AICoachResponse) -> String {
        sanitizeAssistantText(response.assistantText)
    }

    /// Strips bracketed provenance, capability jargon, and internal labels from model prose.
    static func sanitizeAssistantText(_ raw: String) -> String {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        // Remove [Bracketed annotations] the model may inline.
        text = text.replacingOccurrences(
            of: #"\[[^\]]{0,120}\]"#,
            with: "",
            options: .regularExpression
        )
        let bannedSubstrings = [
            "Meal Memory unavailable",
            "Location context unavailable",
            "Location unavailable",
            "HealthKit unavailable",
            "Apple Health / HealthKit is not connected",
            "Workout tracking is not available",
            "Confirmed today’s totals",
            "Confirmed today's totals",
            "Confirmed Artifact",
            "confirmed artifact",
            "capability flags",
            "I don’t have meal memory",
            "I don't have meal memory",
            "I will not update your saved data",
            "I won’t update your saved data",
            "I won't update your saved data",
        ]
        for banned in bannedSubstrings {
            text = text.replacingOccurrences(of: banned, with: "", options: .caseInsensitive)
        }
        // Collapse whitespace left by removals.
        text = text.replacingOccurrences(of: #"\n{3,}"#, with: "\n\n", options: .regularExpression)
        text = text.replacingOccurrences(of: #" {2,}"#, with: " ", options: .regularExpression)
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func evidencePayload(from response: AICoachResponse) -> LiveTaiEvidencePayload? {
        let items = response.evidence.map {
            LiveTaiEvidenceItem(kind: $0.kind, label: $0.label, detail: $0.detail)
        }
        // Only surface material limitations in Why — never generic capability catalogues.
        let limitations = response.limitations
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .filter { !isGenericCapabilityLimitation($0) }
        guard !items.isEmpty || !limitations.isEmpty || response.recommendation != nil else {
            return nil
        }
        return LiveTaiEvidencePayload(
            summary: response.recommendation?.detail ?? response.recommendation?.title,
            evidence: items,
            limitationsShown: limitations,
            confidence: response.confidence,
            requiresUserDecision: response.requiresUserDecision
        )
    }

    static func quickActions(from response: AICoachResponse) -> [ConversationQuickAction] {
        var actions = ConversationQuickActionAllowlist.mapProxyActions(response.quickActions)
        if evidencePayload(from: response) != nil,
           !actions.contains(where: { $0.id == ConversationAllowedQuickAction.liveTaiWhy.rawValue })
        {
            actions.insert(ConversationAllowedQuickAction.liveTaiWhy.asConversationQuickAction(), at: 0)
        }
        return actions
    }

    private static func isGenericCapabilityLimitation(_ text: String) -> Bool {
        let lowered = text.lowercased()
        let generics = [
            "healthkit", "apple health", "meal memory", "location", "workout",
            "sleep data", "weight data",
        ]
        return generics.contains { lowered.contains($0) }
    }
}
