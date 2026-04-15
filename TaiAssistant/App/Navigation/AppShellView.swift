import SwiftUI

struct AppShellView: View {
    private enum Tab: Hashable {
        case dashboard
        case goals
    }

    let dependencies: AppDependencies
    let config: RuntimeAppConfig

    @State private var selectedTab: Tab = .dashboard
    @State private var isAskTaiPresented = false
    @State private var askTaiSeedPrompt: String?

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
                    onAskTaiRequested: { prompt in
                        handleAskTaiTap(seedPrompt: prompt)
                    }
                )
            }
            .tabItem { Label("Dashboard", systemImage: "square.grid.2x2.fill") }
            .tag(Tab.dashboard)

            NavigationStack {
                GoalsView(goalRepository: dependencies.goalRepository, ownerID: config.localOwnerID)
            }
            .tabItem { Label("Goals", systemImage: "target") }
            .tag(Tab.goals)
        }
        .overlay(alignment: .bottomTrailing) {
            FloatingAskTaiButton(
                assistantName: config.assistantName,
                action: { handleAskTaiTap(seedPrompt: nil) }
            )
            .padding(.trailing, DSSpacing.lg)
            .padding(.bottom, DSSpacing.xxl)
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
    }

    private func handleAskTaiTap(seedPrompt: String? = nil) {
        selectedTab = .dashboard
        askTaiSeedPrompt = seedPrompt
        isAskTaiPresented = true
    }
}
