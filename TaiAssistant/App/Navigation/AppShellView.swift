import SwiftUI

struct AppShellView: View {
    private enum Tab: Hashable {
        case dashboard
        case goals
    }

    let dependencies: AppDependencies
    let config: RuntimeAppConfig

    @State private var selectedTab: Tab = .dashboard

    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack {
                DashboardView(
                    aiService: dependencies.aiService,
                    healthService: dependencies.healthService,
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
    }

    private func handleAskTaiTap() {
        // Dashboard-first loop: Ask Tai always routes back to the primary home surface.
        selectedTab = .dashboard
    }
}
