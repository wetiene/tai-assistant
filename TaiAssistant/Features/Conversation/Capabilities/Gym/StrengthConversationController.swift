import Foundation

enum StrengthConversationError: Error, Equatable {
    case noPlannedWorkout
    case activeSessionConflict(sessionID: UUID)
    case interpretationFailed
    case noActiveSession
    case exerciseNotFound
    case reviewNotFound
    case reviewAlreadyApplied
}

/// Conversational strength workout orchestration. Canonical state lives in `StrengthWorkoutController`.
@MainActor
@Observable
final class StrengthConversationController {
    let workoutController: StrengthWorkoutController
    private let workoutRepository: WorkoutRepository
    private let gymPlanRepository: GymPlanRepository
    private let aiService: AIService
    private let ownerID: String
    private let photoAssist: StrengthGymPhotoAssistService

    private(set) var phase: StrengthConversationCapabilityID.Phase = .idle
    private(set) var pendingPhotoReview: StrengthPhotoReviewState?
    private(set) var lastError: String?

    var session: StrengthWorkoutSession? { workoutController.session }

    var hasActiveSession: Bool {
        session?.status == .inProgress
    }

    var isBusy: Bool {
        phase == .interpretingPhoto || phase == .savingSet
    }

    init(
        workoutRepository: WorkoutRepository,
        gymPlanRepository: GymPlanRepository,
        aiService: AIService,
        ownerID: String
    ) {
        self.workoutRepository = workoutRepository
        self.gymPlanRepository = gymPlanRepository
        self.aiService = aiService
        self.ownerID = ownerID
        self.workoutController = StrengthWorkoutController(
            workoutRepository: workoutRepository,
            ownerID: ownerID
        )
        self.photoAssist = StrengthGymPhotoAssistService(aiService: aiService)
    }

    func clearError() {
        lastError = nil
    }

    // MARK: - Restore

    func restoreFromConversation(_ conversation: ActiveConversation) async {
        _ = try? await workoutController.restoreInProgressSession()
        if let session = workoutController.session, session.status == .inProgress {
            phase = .active
            return
        }
        if let sessionID = StrengthConversationActivityCodec.sessionID(from: conversation.activity) {
            _ = try? await workoutController.restoreInProgressSession()
            if workoutController.session?.sessionID == sessionID {
                phase = .active
            }
        }
    }

    // MARK: - Gym arrival

    enum GymArrivalResult: Equatable {
        case resumed(StrengthWorkoutSession)
        case started(StrengthWorkoutSession)
    }

    func startOrResumeFromGymArrival() async throws -> GymArrivalResult {
        clearError()
        if let active = try await workoutController.restoreInProgressSession(),
           active.status == .inProgress {
            phase = .active
            return .resumed(active)
        }

        let library = try await gymPlanRepository.fetchLibrary(ownerID: ownerID)
        guard let plan = try await StrengthTrainingBriefingBuilder.resolvePlannedWorkout(
            library: library,
            gymPlanRepository: gymPlanRepository,
            ownerID: ownerID
        ) else {
            throw StrengthConversationError.noPlannedWorkout
        }

        let history = try await fetchHistory()
        let proposals = StrengthSessionBuilder.proposals(for: plan, historySessions: history)
        let prepared = workoutController.prepareSession(
            plan: plan,
            proposals: proposals,
            acceptedProposals: [:],
            historySessions: history,
            origin: .conversation,
            preFlightCompleted: proposals.isEmpty
        )

        do {
            try await workoutController.startSession(prepared, activateFirstExercise: false)
        } catch StrengthWorkoutStartError.activeSessionInProgress(let sessionID) {
            _ = try await workoutController.restoreInProgressSession()
            if let restored = workoutController.session {
                phase = .active
                return .resumed(restored)
            }
            throw StrengthConversationError.activeSessionConflict(sessionID: sessionID)
        }

        guard let started = workoutController.session else {
            throw StrengthConversationError.noActiveSession
        }
        phase = .active
        return .started(started)
    }

    func startOrResumeFromTarget(_ target: GymPlanWorkoutTarget) async throws -> GymArrivalResult {
        clearError()
        if let active = try await workoutController.restoreInProgressSession(),
           active.status == .inProgress,
           active.planReference == target.reference
        {
            phase = .active
            return .resumed(active)
        }

        let plan = try await gymPlanRepository.resolvePlan(
            reference: target.reference,
            sectionIndex: target.sectionIndex,
            ownerID: ownerID
        )
        let history = try await fetchHistory()
        let proposals = StrengthSessionBuilder.proposals(for: plan, historySessions: history)
        let prepared = workoutController.prepareSession(
            plan: plan,
            proposals: proposals,
            acceptedProposals: [:],
            historySessions: history,
            origin: .conversation,
            preFlightCompleted: proposals.isEmpty
        )

        do {
            try await workoutController.startSession(prepared, activateFirstExercise: false)
        } catch StrengthWorkoutStartError.activeSessionInProgress {
            _ = try await workoutController.restoreInProgressSession()
            if let restored = workoutController.session {
                phase = .active
                return .resumed(restored)
            }
            throw StrengthConversationError.noActiveSession
        }

        guard let started = workoutController.session else {
            throw StrengthConversationError.noActiveSession
        }
        phase = .active
        return .started(started)
    }

    func finishWorkout() async throws -> StrengthWorkoutDebrief {
        clearError()
        let debrief = try await workoutController.finishWorkout()
        pendingPhotoReview = nil
        phase = .idle
        return debrief
    }

    func skipRemainingSetsAndComplete() async throws -> StrengthWorkoutDebrief {
        clearError()
        let debrief = try await workoutController.skipRemainingSetsAndComplete()
        pendingPhotoReview = nil
        phase = .idle
        return debrief
    }

    var hasUnresolvedWork: Bool {
        workoutController.hasUnresolvedWork
    }

    var unresolvedSetCount: Int {
        guard let session else { return 0 }
        return StrengthSessionNavigation.unresolvedSetCount(in: session)
    }

    func pendingProgressionProposals() -> [StrengthProgressionProposal] {
        guard let session, let proposals = session.preFlightProposals else { return [] }
        return proposals.filter { session.acceptedProposals[$0.exerciseID] == nil }
    }

    func acceptProgressionProposal(exerciseID: String) async throws {
        guard let session,
              let proposal = session.preFlightProposals?.first(where: { $0.exerciseID == exerciseID })
        else { return }
        try await workoutController.recordProgressionDecision(
            StrengthAcceptedProposal(
                exerciseID: proposal.exerciseID,
                decision: .accepted,
                weight: proposal.proposedWeight ?? proposal.currentWeight,
                weightUnit: proposal.weightUnit,
                originalProposal: proposal
            )
        )
    }

    func holdProgressionProposal(exerciseID: String) async throws {
        guard let session,
              let proposal = session.preFlightProposals?.first(where: { $0.exerciseID == exerciseID })
        else { return }
        try await workoutController.recordProgressionDecision(
            StrengthAcceptedProposal(
                exerciseID: proposal.exerciseID,
                decision: .hold,
                weight: proposal.currentWeight,
                weightUnit: proposal.weightUnit,
                originalProposal: proposal
            )
        )
    }

    func acceptAllProgressionProposals() async throws {
        for proposal in pendingProgressionProposals() {
            try await acceptProgressionProposal(exerciseID: proposal.exerciseID)
        }
    }

    // MARK: - Photo interpretation

    func interpretPhotoEvidence(
        _ jpegs: [Data],
        evidenceAttachmentIDs: [UUID] = []
    ) async throws -> StrengthPhotoReviewState {
        guard let active = session else { throw StrengthConversationError.noActiveSession }
        guard !jpegs.isEmpty else { throw StrengthConversationError.interpretationFailed }

        clearError()
        phase = .interpretingPhoto
        defer {
            if phase == .interpretingPhoto { phase = .active }
        }

        let result = try await photoAssist.interpretPhotos(
            jpegs: jpegs,
            session: active,
            localeIdentifier: Locale.current.identifier,
            weightUnitPreference: active.weightUnit
        )

        var review = StrengthPhotoReviewState(
            reviewID: UUID(),
            interpretation: result.interpretation,
            detectedExerciseID: result.detectedExerciseID,
            detectedExerciseName: result.detectedExerciseName,
            suggestedWeight: result.suggestedWeight,
            weightUnit: result.weightUnit,
            suggestedReps: result.suggestedReps,
            photoCount: jpegs.count,
            evidenceAttachmentIDs: evidenceAttachmentIDs,
            imageClassification: result.imageClassification
        )
        if var classification = review.imageClassification,
           classification.sourceAttachmentID == nil,
           let attachmentID = evidenceAttachmentIDs.first
        {
            classification.sourceAttachmentID = attachmentID
            review.imageClassification = classification
        }
        pendingPhotoReview = review
        phase = .reviewingPhoto
        return review
    }

    func applyPhotoReview(
        reviewID: UUID,
        fallbackPayload: StrengthPhotoReviewCardPayload? = nil
    ) async throws -> UUID {
        if let fallbackPayload, fallbackPayload.reviewID == reviewID {
            pendingPhotoReview = StrengthPhotoReviewState(
                reviewID: fallbackPayload.reviewID,
                interpretation: fallbackPayload.interpretation,
                detectedExerciseID: fallbackPayload.detectedExerciseID,
                detectedExerciseName: fallbackPayload.detectedExerciseName,
                suggestedWeight: fallbackPayload.suggestedWeight,
                weightUnit: fallbackPayload.weightUnit,
                suggestedReps: fallbackPayload.suggestedReps,
                photoCount: fallbackPayload.photoCount,
                evidenceAttachmentIDs: fallbackPayload.evidenceAttachmentIDs,
                imageClassification: fallbackPayload.imageClassification
            )
        }
        guard var review = pendingPhotoReview, review.reviewID == reviewID else {
            throw StrengthConversationError.reviewNotFound
        }
        guard let active = session else { throw StrengthConversationError.noActiveSession }

        guard let detectedID = review.detectedExerciseID,
              let match = active.exercises.first(where: { $0.exerciseID == detectedID })
        else {
            throw StrengthConversationError.exerciseNotFound
        }

        try await workoutController.selectExercise(exerciseInstanceID: match.id)
        try await workoutController.applySuggestedValuesToCurrentSet(
            weight: review.suggestedWeight,
            reps: review.suggestedReps
        )
        pendingPhotoReview = nil
        phase = .active
        return match.id
    }

    func dismissPhotoReview(reviewID: UUID) {
        guard pendingPhotoReview?.reviewID == reviewID else { return }
        pendingPhotoReview = nil
        phase = .active
    }

    // MARK: - Set operations

    func confirmSet(
        exerciseInstanceID: UUID,
        weight: Double,
        reps: Int
    ) async throws {
        phase = .savingSet
        defer { phase = .active }
        try await workoutController.selectExercise(exerciseInstanceID: exerciseInstanceID)
        try await workoutController.confirmCurrentSet(weight: weight, reps: reps)
    }

    func skipSet(exerciseInstanceID: UUID) async throws {
        phase = .savingSet
        defer { phase = .active }
        try await workoutController.selectExercise(exerciseInstanceID: exerciseInstanceID)
        try await workoutController.skipCurrentSet()
    }

    func updateCurrentSetDraft(
        exerciseInstanceID: UUID,
        weight: Double?,
        reps: Int?
    ) async throws {
        try await workoutController.selectExercise(exerciseInstanceID: exerciseInstanceID)
        try await workoutController.applySuggestedValuesToCurrentSet(weight: weight, reps: reps)
    }

    // MARK: - Card builders

    func makeOverviewCardPayload() -> StrengthWorkoutOverviewCardPayload? {
        guard let session else { return nil }
        return StrengthWorkoutOverviewCardPayload(sessionID: session.sessionID)
    }

    func makeExerciseWorkspacePayload(exerciseInstanceID: UUID) -> StrengthExerciseWorkspaceCardPayload? {
        guard let session else { return nil }
        guard session.exercises.contains(where: { $0.id == exerciseInstanceID }) else { return nil }
        return StrengthExerciseWorkspaceCardPayload(
            sessionID: session.sessionID,
            exerciseInstanceID: exerciseInstanceID
        )
    }

    func makePhotoReviewCardPayload(from review: StrengthPhotoReviewState) -> StrengthPhotoReviewCardPayload? {
        guard let session else { return nil }
        return StrengthPhotoReviewCardPayload(
            reviewID: review.reviewID,
            sessionID: session.sessionID,
            detectedExerciseID: review.detectedExerciseID,
            detectedExerciseName: review.detectedExerciseName,
            suggestedWeight: review.suggestedWeight,
            weightUnit: review.weightUnit,
            suggestedReps: review.suggestedReps,
            interpretation: review.interpretation,
            photoCount: review.photoCount,
            evidenceAttachmentIDs: review.evidenceAttachmentIDs,
            isApplied: false,
            imageClassification: review.imageClassification
        )
    }

    func exerciseInstance(for exerciseID: String) -> StrengthExerciseInstance? {
        session?.exercises.first { $0.exerciseID == exerciseID }
    }

    // MARK: - Helpers

    private func fetchHistory() async throws -> [WorkoutSessionLog] {
        let from = Calendar.current.date(byAdding: .year, value: -1, to: .now) ?? .distantPast
        return try await workoutRepository.fetchSessions(
            ownerID: ownerID,
            from: from,
            to: .now.addingTimeInterval(86400)
        )
    }

}
