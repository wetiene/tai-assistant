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

    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack {
                DashboardView(
                    mealRepository: dependencies.mealRepository,
                    goalRepository: dependencies.goalRepository,
                    recurringMealRepository: dependencies.recurringMealRepository,
                    alcoholPlanRepository: dependencies.alcoholPlanRepository,
                    assistantName: config.assistantName
                )
            }
            .tabItem { Label("Dashboard", systemImage: "square.grid.2x2.fill") }
            .tag(Tab.dashboard)

            NavigationStack {
                GoalsView(goalRepository: dependencies.goalRepository)
            }
            .tabItem { Label("Goals", systemImage: "target") }
            .tag(Tab.goals)
        }
        .overlay(alignment: .bottomTrailing) {
            FloatingAskTaiButton(
                assistantName: config.assistantName,
                action: handleAskTaiTap
            )
            .padding(.trailing, DSSpacing.lg)
            .padding(.bottom, DSSpacing.xxl)
        }
        .fullScreenCover(isPresented: $isAskTaiPresented) {
            AskTaiEntrySheet(
                assistantName: config.assistantName,
                dismiss: { isAskTaiPresented = false }
            )
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    private func handleAskTaiTap() {
        selectedTab = .dashboard
        isAskTaiPresented = true
    }
}
