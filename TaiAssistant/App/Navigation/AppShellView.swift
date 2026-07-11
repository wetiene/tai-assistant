import SwiftUI
import UIKit

struct AppShellView: View {
    fileprivate enum LegacyTab: Hashable {
        case dashboard
        case checkIn
        case goals
    }

    let dependencies: AppDependencies
    let config: RuntimeAppConfig

    @State private var legacyTab: LegacyTab = .dashboard
    @State private var navV2Tab: NavV2PrimaryTab = .home
    @State private var isAskTaiPresented = false
    @State private var askTaiSeedPrompt: String?
    @State private var isKeyboardVisible = false
    @State private var mealAddedFeedbackTrigger = 0
    @State private var isAskTaiDeemphasized = false
    @State private var pendingTaiIntent: TaiLaunchIntent?
    @State private var hasOpenedTai = false

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
    }

    // MARK: - Nav V2 (Home | Tai) — structurally two destinations only

    private var navV2Shell: some View {
        TabView(selection: $navV2Tab) {
            NavigationStack {
                HomeBriefingView(
                    mealRepository: dependencies.mealRepository,
                    goalRepository: dependencies.goalRepository,
                    ownerID: config.localOwnerID,
                    assistantName: config.assistantName,
                    mealAddedFeedbackTrigger: mealAddedFeedbackTrigger,
                    analytics: dependencies.analytics,
                    onPrimaryAction: handleHomePrimaryAction
                )
            }
            .tabItem { Label(NavV2PrimaryTab.home.title, systemImage: "house.fill") }
            .tag(NavV2PrimaryTab.home)

            NavigationStack {
                if hasOpenedTai || navV2Tab == .tai {
                    TaiConversationContainerView(
                        conversationSession: dependencies.conversationSession,
                        goalRepository: dependencies.goalRepository,
                        aiService: dependencies.aiService,
                        ownerID: config.localOwnerID,
                        assistantName: config.assistantName,
                        analytics: dependencies.analytics,
                        launchIntent: pendingTaiIntent,
                        onLaunchIntentConsumed: {
                            pendingTaiIntent = nil
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
        .onChange(of: navV2Tab) { _, tab in
            if tab == .tai {
                hasOpenedTai = true
            }
        }
        .task {
            dependencies.conversationSession.updateOnMealSaved {
                mealAddedFeedbackTrigger += 1
            }
            // Prefetch Conversation after first frame so Home is not blocked.
            await dependencies.conversationSession.ensureLoaded()
        }
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
        pendingTaiIntent = TaiLaunchIntent.fromHomeDestination(destination)
        hasOpenedTai = true
        navV2Tab = .tai
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
