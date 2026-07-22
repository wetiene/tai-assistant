import SwiftUI

enum StrengthWorkoutFlowRoute: Hashable {
    case preFlight
    case active
    case debrief
}

struct StrengthWorkoutFlowView: View {
    let presentation: StrengthWorkoutPresentation
    let workoutRepository: WorkoutRepository
    let aiService: AIService
    let ownerID: String
    var onComplete: () -> Void
    var onLeave: () -> Void
    var onCancel: () -> Void

    @State private var controller: StrengthWorkoutController
    @State private var sessionPlan: GymResolvablePlan
    @State private var proposals: [StrengthProgressionProposal]
    @State private var acceptedProposals: [String: StrengthAcceptedProposal] = [:]
    @State private var route: StrengthWorkoutFlowRoute
    @State private var preparedSession: StrengthWorkoutSession?
    @State private var startError: String?
    @State private var isEditingSessionPlan = false

    init(
        presentation: StrengthWorkoutPresentation,
        workoutRepository: WorkoutRepository,
        aiService: AIService,
        ownerID: String,
        onComplete: @escaping () -> Void,
        onLeave: @escaping () -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.presentation = presentation
        self.workoutRepository = workoutRepository
        self.aiService = aiService
        self.ownerID = ownerID
        self.onComplete = onComplete
        self.onLeave = onLeave
        self.onCancel = onCancel
        _controller = State(initialValue: StrengthWorkoutController(workoutRepository: workoutRepository, ownerID: ownerID))
        _sessionPlan = State(initialValue: presentation.plan)
        _proposals = State(initialValue: presentation.proposals)
        if let resumeSession = presentation.resumeSession {
            _route = State(initialValue: .active)
            _preparedSession = State(initialValue: resumeSession)
            _acceptedProposals = State(initialValue: resumeSession.acceptedProposals)
        } else {
            _route = State(initialValue: .preFlight)
        }
    }

    var body: some View {
        Group {
            switch route {
            case .preFlight:
                StrengthPreFlightView(
                    plan: sessionPlan,
                    proposals: proposals,
                    acceptedProposals: $acceptedProposals,
                    onStart: { Task { await startWorkout() } },
                    onEditPlan: { isEditingSessionPlan = true },
                    onCancel: onCancel
                )
            case .active:
                StrengthActiveWorkoutView(
                    controller: controller,
                    photoAssist: StrengthGymPhotoAssistService(aiService: aiService),
                    onCompleteWorkout: { route = .debrief },
                    onLeave: onLeave,
                    onAbandon: {
                        Task {
                            try? await controller.abandonWorkout()
                            onCancel()
                        }
                    }
                )
            case .debrief:
                if let debrief = controller.debrief {
                    StrengthDebriefView(debrief: debrief, onDone: onComplete)
                }
            }
        }
        .sheet(isPresented: $isEditingSessionPlan) {
            NavigationStack {
                StrengthSessionPlanEditorView(
                    plan: $sessionPlan,
                    onDone: {
                        refreshProposalsAfterPlanEdit()
                        isEditingSessionPlan = false
                    },
                    onCancel: {
                        sessionPlan = presentation.plan
                        refreshProposalsAfterPlanEdit()
                        isEditingSessionPlan = false
                    }
                )
            }
        }
        .alert("Could not start workout", isPresented: Binding(
            get: { startError != nil },
            set: { if !$0 { startError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(startError ?? "")
        }
        .task {
            if let prepared = preparedSession {
                controller.loadSession(prepared)
            }
        }
    }

    @MainActor
    private func startWorkout() async {
        let prepared = controller.prepareSession(
            plan: sessionPlan,
            proposals: proposals,
            acceptedProposals: acceptedProposals,
            historySessions: presentation.historySessions,
            origin: presentation.source,
            preFlightCompleted: true
        )
        do {
            try await controller.startSession(prepared)
            route = .active
        } catch StrengthWorkoutStartError.activeSessionInProgress {
            startError = "You already have a workout in progress."
        } catch {
            startError = "Could not start workout."
        }
    }

    private func refreshProposalsAfterPlanEdit() {
        let refreshed = StrengthSessionBuilder.proposals(
            for: sessionPlan,
            historySessions: presentation.historySessions
        )
        proposals = refreshed
        let exerciseIDs = Set(sessionPlan.exercises.map(\.id))
        acceptedProposals = StrengthSessionInvariants.reconcileAcceptedProposals(
            StrengthSessionInvariants.pruneAcceptedProposals(acceptedProposals, for: exerciseIDs),
            refreshedProposals: refreshed
        )
    }
}
