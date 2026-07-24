import SwiftUI
import UIKit

extension Notification.Name {
    static let uiTestHomeStrengthStartButtonTapped = Notification.Name("UITestHomeStrengthStartButtonTapped")
}

struct AppShellView: View {
    fileprivate enum LegacyTab: Hashable {
        case dashboard
        case checkIn
        case goals
    }

    let dependencies: AppDependencies
    let config: RuntimeAppConfig

    @State private var legacyTab: LegacyTab = .dashboard
    @State private var navV2Tab: NavV2PrimaryTab =
        (StrengthConversationUITestSupport.isEnabled || ImageDomainUITestSupport.isEnabled) ? .tai : .home
    @State private var isAskTaiPresented = false
    @State private var askTaiSeedPrompt: String?
    @State private var isKeyboardVisible = false
    @State private var mealAddedFeedbackTrigger = 0
    @State private var workoutAddedFeedbackTrigger = 0
    @State private var isAskTaiDeemphasized = false
    @State private var pendingTaiIntent: TaiLaunchIntent?
    @State private var hasOpenedTai = ProcessInfo.processInfo.arguments.contains("-UITestStrengthSmoke")
        || StrengthConversationUITestSupport.isEnabled
        || ImageDomainUITestSupport.isEnabled
    @State private var uiTestHomeStrengthStartSignal = "idle"
    @State private var isGymPlansPresented = false
    @State private var pendingGymPlanImportReview: (draft: GymPlanImportDraft, sourceText: String?)?
    @State private var strengthWorkoutPresentation: StrengthWorkoutPresentation?
    @State private var workoutEntryRouter: StrengthWorkoutEntryRouter?

    private var strengthWorkoutCoordinator: StrengthWorkoutCoordinator {
        StrengthWorkoutCoordinator(
            workoutRepository: dependencies.workoutRepository,
            gymPlanRepository: dependencies.gymPlanRepository,
            ownerID: config.localOwnerID
        )
    }

    init(dependencies: AppDependencies, config: RuntimeAppConfig) {
        self.dependencies = dependencies
        self.config = config
        // Nav V2 uses the system tab bar (exactly Home | Tai).
        // Legacy keeps a custom centre Check In control, so hide the system bar.
        UITabBar.appearance().isHidden = !config.navV2Enabled
    }

    var body: some View {
        Group {
            if config.navV2Enabled {
                navV2Shell
            } else {
                legacyShell
            }
        }
        .fullScreenCover(isPresented: $isAskTaiPresented) {
            AskTaiEntrySheet(
                assistantName: config.assistantName,
                askTaiGuidance: dependencies.askTaiGuidance,
                isPreview: dependencies.isAskTaiPreview,
                initialPrompt: askTaiSeedPrompt,
                dismiss: {
                    isAskTaiPresented = false
                    askTaiSeedPrompt = nil
                }
            )
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
            isKeyboardVisible = true
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            isKeyboardVisible = false
        }
        .onReceive(NotificationCenter.default.publisher(for: .uiTestHomeStrengthStartButtonTapped)) { _ in
            uiTestHomeStrengthStartSignal = "button"
        }
        .overlay {
            if ProcessInfo.processInfo.arguments.contains("-UITestStrengthSmoke") {
                Color.clear
                    .frame(width: 1, height: 1)
                    .accessibilityElement(children: .ignore)
                    .accessibilityIdentifier("uitest.home.strength.\(uiTestHomeStrengthStartSignal)")
            }
        }
    }

    // MARK: - Nav V2 (Home | Tai) — structurally two destinations only

    private var navV2Shell: some View {
        Group {
            if let workoutEntryRouter {
                navV2TabContent
                    .strengthWorkoutConflictDialogs(router: workoutEntryRouter)
                    .alert("Workout unavailable", isPresented: Binding(
                        get: { workoutEntryRouter.alertMessage != nil },
                        set: { if !$0 { workoutEntryRouter.alertMessage = nil } }
                    )) {
                        Button("OK", role: .cancel) {}
                    } message: {
                        Text(workoutEntryRouter.alertMessage ?? "")
                    }
            } else {
                navV2TabContent
            }
        }
        .task {
            if workoutEntryRouter == nil {
                let router = StrengthWorkoutEntryRouter(
                    coordinator: strengthWorkoutCoordinator,
                    gymPlanRepository: dependencies.gymPlanRepository,
                    ownerID: config.localOwnerID,
                    onPresentWorkout: { presentation in
                        presentStrengthWorkout(presentation)
                    },
                    onWorkoutSaved: {
                        workoutAddedFeedbackTrigger += 1
                    }
                )
                workoutEntryRouter = router
                wireStrengthWorkoutRouting(router: router)
            }
            await dependencies.conversationSession.ensureLoaded()
        }
    }

    private var navV2TabContent: some View {
        TabView(selection: $navV2Tab) {
            NavigationStack {
                HomeBriefingView(
                    mealRepository: dependencies.mealRepository,
                    workoutRepository: dependencies.workoutRepository,
                    gymPlanRepository: dependencies.gymPlanRepository,
                    goalRepository: dependencies.goalRepository,
                    nutritionDaySelection: dependencies.nutritionDaySelection,
                    ownerID: config.localOwnerID,
                    assistantName: config.assistantName,
                    mealAddedFeedbackTrigger: mealAddedFeedbackTrigger,
                    workoutAddedFeedbackTrigger: workoutAddedFeedbackTrigger,
                    analytics: dependencies.analytics,
                    onPrimaryAction: handleHomePrimaryAction,
                    onOpenTai: handleOpenTaiFromHome,
                    onManageGymPlans: { isGymPlansPresented = true },
                    onStartStrengthWorkout: { plan, _, _ in
                        if ProcessInfo.processInfo.arguments.contains("-UITestStrengthSmoke") {
                            NotificationCenter.default.post(name: .uiTestHomeStrengthStartButtonTapped, object: nil)
                        }
                        openTaiForConversationalStrengthWorkout(
                            target: GymPlanWorkoutTarget(
                                reference: plan.reference,
                                sectionIndex: plan.sectionIndex
                            )
                        )
                    },
                    onResumeStrengthWorkout: {
                        openTaiForConversationalStrengthResume()
                    }
                )
            }
            .tabItem { Label(NavV2PrimaryTab.home.title, systemImage: "house.fill") }
            .tag(NavV2PrimaryTab.home)

            NavigationStack {
                if hasOpenedTai || navV2Tab == .tai {
                    TaiConversationContainerView(
                        conversationSession: dependencies.conversationSession,
                        goalRepository: dependencies.goalRepository,
                        gymPlanRepository: dependencies.gymPlanRepository,
                        aiService: dependencies.aiService,
                        ownerID: config.localOwnerID,
                        assistantName: config.assistantName,
                        analytics: dependencies.analytics,
                        launchIntent: pendingTaiIntent,
                        onLaunchIntentConsumed: {
                            pendingTaiIntent = nil
                        },
                        onManageGymPlans: { isGymPlansPresented = true },
                        onStartWorkout: { target in
                            isGymPlansPresented = false
                            pendingGymPlanImportReview = nil
                            openTaiForConversationalStrengthWorkout(target: target)
                        }
                    )
                } else {
                    DSColor.background.ignoresSafeArea()
                }
            }
            .tabItem {
                Label(NavV2PrimaryTab.tai.title, systemImage: "bubble.left.and.bubble.right.fill")
            }
            .tag(NavV2PrimaryTab.tai)
        }
        .tint(DSColor.coralEnd)
        .onChange(of: navV2Tab) { _, tab in
            if tab == .tai {
                hasOpenedTai = true
            }
        }
        .sheet(isPresented: $isGymPlansPresented) {
            NavigationStack {
                GymPlansView(
                    gymPlanRepository: dependencies.gymPlanRepository,
                    aiService: dependencies.aiService,
                    ownerID: config.localOwnerID,
                    importRequestContext: config.gymPlanImportRequestContext(
                        sourceType: .text,
                        sourceTextCharacterCount: 0,
                        knownExerciseCount: GymExerciseID.allCases.count
                    ),
                    pendingImportReview: pendingGymPlanImportReview,
                    onStartWorkout: { target in
                        isGymPlansPresented = false
                        pendingGymPlanImportReview = nil
                        openTaiForConversationalStrengthWorkout(target: target)
                    },
                    onDismiss: {
                        isGymPlansPresented = false
                        pendingGymPlanImportReview = nil
                    }
                )
            }
        }
        .fullScreenCover(item: $strengthWorkoutPresentation) { presentation in
            NavigationStack {
                StrengthWorkoutFlowView(
                    presentation: presentation,
                    workoutRepository: dependencies.workoutRepository,
                    aiService: dependencies.aiService,
                    ownerID: config.localOwnerID,
                    onComplete: {
                        strengthWorkoutPresentation = nil
                        workoutAddedFeedbackTrigger += 1
                        Task {
                            await dependencies.conversationSession.refreshStrengthAfterDedicatedDismiss()
                        }
                    },
                    onLeave: {
                        strengthWorkoutPresentation = nil
                        Task {
                            await dependencies.conversationSession.refreshStrengthAfterDedicatedDismiss()
                        }
                    },
                    onCancel: {
                        strengthWorkoutPresentation = nil
                        Task {
                            await dependencies.conversationSession.refreshStrengthAfterDedicatedDismiss()
                        }
                    }
                )
            }
        }
    }

    private func wireStrengthWorkoutRouting(router: StrengthWorkoutEntryRouter) {
        dependencies.conversationSession.updateOnMealSaved {
            mealAddedFeedbackTrigger += 1
        }
        dependencies.conversationSession.updateOnWorkoutSaved {
            workoutAddedFeedbackTrigger += 1
        }
        dependencies.conversationSession.updateOnManageGymPlans {
            isGymPlansPresented = true
        }
        dependencies.conversationSession.updateOnPresentGymPlanImportReview { draft, sourceText in
            pendingGymPlanImportReview = (draft, sourceText)
            isGymPlansPresented = true
        }
        dependencies.conversationSession.updateStrengthWorkoutEntryRouting(
            coordinator: strengthWorkoutCoordinator,
            router: router,
            onPresent: { presentation in
                presentStrengthWorkout(presentation)
            }
        )
    }

    private func presentStrengthWorkout(_ presentation: StrengthWorkoutPresentation) {
        strengthWorkoutPresentation = presentation
    }

    // MARK: - Legacy shell (flag off)

    private var legacyShell: some View {
        TabView(selection: $legacyTab) {
            NavigationStack {
                DashboardView(
                    mealRepository: dependencies.mealRepository,
                    goalRepository: dependencies.goalRepository,
                    recurringMealRepository: dependencies.recurringMealRepository,
                    alcoholPlanRepository: dependencies.alcoholPlanRepository,
                    ownerID: config.localOwnerID,
                    assistantName: config.assistantName,
                    isAskTaiPreview: dependencies.isAskTaiPreview,
                    mealAddedFeedbackTrigger: mealAddedFeedbackTrigger,
                    onCheckInRequested: {
                        legacyTab = .checkIn
                    },
                    onAskTaiRequested: { prompt in
                        legacyTab = .dashboard
                        presentAskTai(seedPrompt: prompt)
                    },
                    onScrollDirectionChanged: { isScrollingDown in
                        withAnimation(.easeInOut(duration: 0.2)) {
                            isAskTaiDeemphasized = isScrollingDown
                        }
                    }
                )
            }
            .tabItem { Label("Dashboard", systemImage: "square.grid.2x2.fill") }
            .tag(LegacyTab.dashboard)

            NavigationStack {
                CheckInView(
                    mealRepository: dependencies.mealRepository,
                    ownerID: config.localOwnerID,
                    interpreter: AIServiceCheckInInterpreter(
                        aiService: dependencies.aiService,
                        ownerID: config.localOwnerID
                    ),
                    onMealsSaved: {
                        legacyTab = .dashboard
                        mealAddedFeedbackTrigger += 1
                    }
                )
            }
            .tabItem { Label("Check In", systemImage: "plus.circle.fill") }
            .tag(LegacyTab.checkIn)

            NavigationStack {
                GoalsView(
                    goalRepository: dependencies.goalRepository,
                    aiService: dependencies.aiService,
                    ownerID: config.localOwnerID,
                    localeIdentifier: Locale.current.identifier,
                    timeZoneIdentifier: TimeZone.current.identifier
                )
            }
            .tabItem { Label("Goals", systemImage: "target") }
            .tag(LegacyTab.goals)
        }
        .toolbar(.hidden, for: .tabBar)
        .overlay(alignment: .bottomTrailing) {
            if shouldShowLegacyAskTaiFAB {
                FloatingAskTaiButton(
                    assistantName: config.assistantName,
                    isPreview: dependencies.isAskTaiPreview,
                    isDeemphasized: isAskTaiDeemphasized,
                    action: { presentAskTai(seedPrompt: nil) }
                )
                .padding(.trailing, DSSpacing.lg)
                .padding(.bottom, -40)
            }
        }
        .safeAreaInset(edge: .bottom) {
            if !isKeyboardVisible {
                AppShellBottomBarLegacy(selectedTab: $legacyTab)
            }
        }
        .onChange(of: legacyTab) { _, newTab in
            if newTab != .dashboard {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isAskTaiDeemphasized = false
                }
            }
        }
    }

    private var shouldShowLegacyAskTaiFAB: Bool {
        legacyTab == .dashboard && !isKeyboardVisible
    }

    private func presentAskTai(seedPrompt: String?) {
        askTaiSeedPrompt = seedPrompt
        isAskTaiPresented = true
    }

    private func handleHomePrimaryAction(_ destination: RecommendationActionDestination) {
        switch destination {
        case .manageGymPlans:
            isGymPlansPresented = true
        case .startGymWorkout(let templateID):
            openTaiForConversationalStrengthWorkout(
                target: GymPlanWorkoutTarget(reference: .starter(templateID), sectionIndex: 0)
            )
        case .startGymWorkoutPlan(let reference):
            openTaiForConversationalStrengthWorkout(
                target: GymPlanWorkoutTarget(reference: reference, sectionIndex: 0)
            )
        case .resumeGymWorkout:
            openTaiForConversationalStrengthResume()
        default:
            pendingTaiIntent = TaiLaunchIntent.fromHomeDestination(
                destination,
                dayContext: dependencies.nutritionDaySelection.dayContext()
            )
            hasOpenedTai = true
            navV2Tab = .tai
        }
    }

    private func handleOpenTaiFromHome() {
        pendingTaiIntent = TaiLaunchIntent(
            kind: .openConversation,
            dayContext: dependencies.nutritionDaySelection.dayContext()
        )
        hasOpenedTai = true
        navV2Tab = .tai
    }

    private func openTaiForConversationalStrengthStart() {
        openTaiForConversationalStrength(
            TaiLaunchIntent(
                kind: .startConversationalStrength,
                dayContext: dependencies.nutritionDaySelection.dayContext()
            )
        )
    }

    private func openTaiForConversationalStrengthResume() {
        openTaiForConversationalStrength(
            TaiLaunchIntent(
                kind: .resumeConversationalStrength,
                dayContext: dependencies.nutritionDaySelection.dayContext()
            )
        )
    }

    private func openTaiForConversationalStrengthWorkout(target: GymPlanWorkoutTarget) {
        openTaiForConversationalStrength(
            TaiLaunchIntent(
                kind: .startGymWorkout(target),
                dayContext: dependencies.nutritionDaySelection.dayContext()
            )
        )
    }

    /// Switches to Tai and delivers strength intents directly so lazy tab mount cannot miss them.
    private func openTaiForConversationalStrength(_ intent: TaiLaunchIntent) {
        if ProcessInfo.processInfo.arguments.contains("-UITestStrengthSmoke") {
            uiTestHomeStrengthStartSignal = "started"
        }
        hasOpenedTai = true
        navV2Tab = .tai
        Task {
            await dependencies.conversationSession.ensureLoaded()
            // Let Home strength-card loading finish before starting a session on the shared store.
            try? await Task.sleep(nanoseconds: 250_000_000)
            dependencies.conversationSession.deliver(intent)
        }
    }
}

// MARK: - Legacy bottom bar only

private struct AppShellBottomBarLegacy: View {
    @Binding var selectedTab: AppShellView.LegacyTab

    var body: some View {
        ZStack(alignment: .top) {
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 26, style: .continuous)
                        .stroke(Color.white.opacity(0.55), lineWidth: 1)
                )
                .frame(height: 68)
                .padding(.top, 22)

            Button {
                selectedTab = .checkIn
            } label: {
                VStack(spacing: 2) {
                    Image(systemName: "plus")
                        .font(.headline.weight(.bold))
                    Text("Check In")
                        .font(.caption2.weight(.semibold))
                }
                .foregroundStyle(.white)
                .frame(width: 84, height: 84)
                .background(DSColor.coralGradient)
                .clipShape(Circle())
                .overlay(
                    Circle()
                        .stroke(Color.white.opacity(0.45), lineWidth: 1)
                )
                .shadow(color: DSColor.coralEnd.opacity(0.3), radius: 12, y: 8)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Check In")
            .accessibilityHint("Log a meal")

            HStack {
                BottomTabButton(
                    title: "Dashboard",
                    icon: "square.grid.2x2.fill",
                    isSelected: selectedTab == .dashboard
                ) {
                    selectedTab = .dashboard
                }
                Spacer(minLength: 92)
                BottomTabButton(
                    title: "Goals",
                    icon: "target",
                    isSelected: selectedTab == .goals
                ) {
                    selectedTab = .goals
                }
            }
            .padding(.horizontal, DSSpacing.xl + 6)
            .padding(.top, 32)
        }
        .padding(.horizontal, DSSpacing.lg)
        .padding(.top, DSSpacing.xs)
        .frame(height: DSSpacing.customBottomNavHeight + 8)
    }
}

private struct BottomTabButton: View {
    let title: String
    let icon: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: icon)
                    .font(.subheadline.weight(.semibold))
                Text(title)
                    .font(.caption.weight(.semibold))
            }
            .foregroundStyle(isSelected ? DSColor.coralEnd : DSColor.textSecondary)
            .frame(minWidth: 84)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
