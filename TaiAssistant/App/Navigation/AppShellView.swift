import SwiftUI
import UIKit

struct AppShellView: View {
    fileprivate enum LegacyTab: Hashable {
        case dashboard
        case checkIn
        case goals
    }

    fileprivate enum NavV2Tab: Hashable {
        case home
        case tai
    }

    let dependencies: AppDependencies
    let config: RuntimeAppConfig

    @State private var legacyTab: LegacyTab = .dashboard
    @State private var navV2Tab: NavV2Tab = .home
    @State private var isAskTaiPresented = false
    @State private var askTaiSeedPrompt: String?
    @State private var isKeyboardVisible = false
    @State private var mealAddedFeedbackTrigger = 0
    @State private var isAskTaiDeemphasized = false
    @State private var mealIntentToken = 0

    init(dependencies: AppDependencies, config: RuntimeAppConfig) {
        self.dependencies = dependencies
        self.config = config
        UITabBar.appearance().isHidden = true
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

    // MARK: - Nav V2 (Home | Tai)

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
            .tabItem { Label("Home", systemImage: "house.fill") }
            .tag(NavV2Tab.home)

            NavigationStack {
                TaiConversationContainerView(
                    mealRepository: dependencies.mealRepository,
                    goalRepository: dependencies.goalRepository,
                    aiService: dependencies.aiService,
                    ownerID: config.localOwnerID,
                    assistantName: config.assistantName,
                    analytics: dependencies.analytics,
                    mealIntentToken: mealIntentToken,
                    onMealSaved: {
                        mealAddedFeedbackTrigger += 1
                    }
                )
            }
            .tabItem { Label("Tai", systemImage: "bubble.left.and.bubble.right.fill") }
            .tag(NavV2Tab.tai)
        }
        .toolbar(.hidden, for: .tabBar)
        .safeAreaInset(edge: .bottom) {
            if !isKeyboardVisible {
                AppShellBottomBarV2(
                    selectedTab: $navV2Tab,
                    onComposeTapped: {
                        navV2Tab = .tai
                        mealIntentToken += 1
                    }
                )
            }
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
        switch destination {
        case .checkInMeal:
            navV2Tab = .tai
            mealIntentToken += 1
        case .reviewGoal:
            navV2Tab = .tai
        }
    }
}

// MARK: - Bottom bars

private struct AppShellBottomBarV2: View {
    @Binding var selectedTab: AppShellView.NavV2Tab
    var onComposeTapped: () -> Void

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

            Button(action: onComposeTapped) {
                VStack(spacing: 2) {
                    Image(systemName: "plus")
                        .font(.headline.weight(.bold))
                    Text("Log")
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
            .accessibilityLabel("Log meal with Tai")
            .accessibilityHint("Opens Tai to log a meal")

            HStack {
                BottomTabButton(
                    title: "Home",
                    icon: "house.fill",
                    isSelected: selectedTab == .home
                ) {
                    selectedTab = .home
                }
                Spacer(minLength: 92)
                BottomTabButton(
                    title: "Tai",
                    icon: "bubble.left.and.bubble.right.fill",
                    isSelected: selectedTab == .tai
                ) {
                    selectedTab = .tai
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
