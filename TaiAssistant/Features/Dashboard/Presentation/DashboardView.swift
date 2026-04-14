import SwiftUI

struct DashboardView: View {
    let aiService: AIService
    let healthService: HealthService
    let assistantName: String

    @State private var dailySummaryText = "No health summary loaded."

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DSSpacing.lg) {
                Text("Hi, I am \(assistantName)")
                    .font(.largeTitle.bold())
                    .foregroundStyle(DSColor.textPrimary)

                PrimaryCard {
                    Text("Today")
                        .font(.headline)
                    Text(dailySummaryText)
                        .foregroundStyle(DSColor.textSecondary)
                }

                PrimaryCard {
                    Text("Habit Loop")
                        .font(.headline)
                    Text("Review your dashboard and use Ask \(assistantName) to adjust next actions.")
                        .foregroundStyle(DSColor.textSecondary)
                }
            }
            .padding(DSSpacing.lg)
        }
        .background(DSColor.background.ignoresSafeArea())
        .navigationTitle("Dashboard")
        .task {
            await loadSummary()
        }
    }

    private func loadSummary() async {
        do {
            let summary = try await healthService.latestDailySummary()
            if let summary {
                dailySummaryText = "Steps: \(summary.steps), Calories burned: \(Int(summary.caloriesBurned))"
            } else {
                dailySummaryText = "No summary available."
            }
        } catch {
            dailySummaryText = "Summary unavailable in scaffold mode."
        }
    }
}
