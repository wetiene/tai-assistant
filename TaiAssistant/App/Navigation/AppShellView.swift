import SwiftUI
import UIKit

struct AppShellView: View {
    fileprivate enum Tab: Hashable {
        case dashboard
        case checkIn
        case goals
    }

    let dependencies: AppDependencies
    let config: RuntimeAppConfig

    @State private var selectedTab: Tab = .dashboard
    @State private var isAskTaiPresented = false
    @State private var askTaiSeedPrompt: String?
    @State private var isKeyboardVisible = false
    @State private var mealAddedFeedbackTrigger = 0
    @State private var isAskTaiDeemphasized = false

    init(dependencies: AppDependencies, config: RuntimeAppConfig) {
        self.dependencies = dependencies
        self.config = config
        UITabBar.appearance().isHidden = true
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack {
                DashboardView(
                    mealRepository: dependencies.mealRepository,
                    goalRepository: dependencies.goalRepository,
                    recurringMealRepository: dependencies.recurringMealRepository,
                    alcoholPlanRepository: dependencies.alcoholPlanRepository,
                    ownerID: config.localOwnerID,
                    assistantName: config.assistantName,
                    mealAddedFeedbackTrigger: mealAddedFeedbackTrigger,
                    onCheckInRequested: {
                        selectedTab = .checkIn
                    },
                    onAskTaiRequested: { prompt in
                        handleAskTaiTap(seedPrompt: prompt)
                    },
                    onScrollDirectionChanged: { isScrollingDown in
                        withAnimation(.easeInOut(duration: 0.2)) {
                            isAskTaiDeemphasized = isScrollingDown
                        }
                    }
                )
            }
            .tabItem { Label("Dashboard", systemImage: "square.grid.2x2.fill") }
            .tag(Tab.dashboard)

            NavigationStack {
                CheckInView(
                    mealRepository: dependencies.mealRepository,
                    ownerID: config.localOwnerID,
                    interpreter: AIServiceCheckInInterpreter(
                        aiService: dependencies.aiService,
                        ownerID: config.localOwnerID
                    ),
                    onMealsSaved: {
                        selectedTab = .dashboard
                        mealAddedFeedbackTrigger += 1
                    }
                )
            }
            .tabItem { Label("Check In", systemImage: "plus.circle.fill") }
            .tag(Tab.checkIn)

            NavigationStack {
                GoalsView(goalRepository: dependencies.goalRepository, ownerID: config.localOwnerID)
            }
            .tabItem { Label("Goals", systemImage: "target") }
            .tag(Tab.goals)
        }
        .toolbar(.hidden, for: .tabBar)
        .overlay(alignment: .bottomTrailing) {
            if shouldShowAskTaiFAB {
                FloatingAskTaiButton(
                    assistantName: config.assistantName,
                    isDeemphasized: isAskTaiDeemphasized,
                    action: { handleAskTaiTap(seedPrompt: nil) }
                )
                .padding(.trailing, DSSpacing.lg)
                .padding(.bottom, -40)
            }
        }
        .safeAreaInset(edge: .bottom) {
            if !isKeyboardVisible {
                AppShellBottomBar(selectedTab: $selectedTab)
            }
        }
        .fullScreenCover(isPresented: $isAskTaiPresented) {
            AskTaiEntrySheet(
                assistantName: config.assistantName,
                askTaiGuidance: dependencies.askTaiGuidance,
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
        .onChange(of: selectedTab) { _, newTab in
            if newTab != .dashboard {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isAskTaiDeemphasized = false
                }
            }
        }
    }

    private func handleAskTaiTap(seedPrompt: String? = nil) {
        selectedTab = .dashboard
        askTaiSeedPrompt = seedPrompt
        isAskTaiPresented = true
    }

    private var shouldShowAskTaiFAB: Bool {
        selectedTab == .dashboard && !isKeyboardVisible
    }
}

private struct AppShellBottomBar: View {
    @Binding var selectedTab: AppShellView.Tab

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
                selectedTab = AppShellView.Tab.checkIn
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

            HStack {
                BottomTabButton(
                    title: "Dashboard",
                    icon: "square.grid.2x2.fill",
                    isSelected: selectedTab == AppShellView.Tab.dashboard
                ) {
                    selectedTab = AppShellView.Tab.dashboard
                }
                Spacer(minLength: 92)
                BottomTabButton(
                    title: "Goals",
                    icon: "target",
                    isSelected: selectedTab == AppShellView.Tab.goals
                ) {
                    selectedTab = AppShellView.Tab.goals
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
    }
}
