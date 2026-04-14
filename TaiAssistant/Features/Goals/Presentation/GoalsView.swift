import SwiftUI

struct GoalsView: View {
    let goalRepository: GoalRepository

    var body: some View {
        List {
            Section("Goals") {
                Text("Goal management will be implemented by the goals feature team.")
                    .foregroundStyle(DSColor.textSecondary)
            }
        }
        .navigationTitle("Goals")
    }
}
