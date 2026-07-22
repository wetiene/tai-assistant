import SwiftUI

struct StrengthDebriefView: View {
    let debrief: StrengthWorkoutDebrief
    var onDone: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DSSpacing.xl) {
                header
                if !debrief.wins.isEmpty {
                    section(title: "Wins", items: debrief.wins)
                }
                if !debrief.watchItems.isEmpty {
                    section(title: "Watch", items: debrief.watchItems)
                }
                if !debrief.nextTimeRecommendations.isEmpty {
                    nextTimeSection
                }
                if let recovery = debrief.recoveryNote {
                    Text(recovery)
                        .font(.subheadline)
                        .foregroundStyle(DSColor.textSecondary)
                }
                Button(action: onDone) {
                    Text("Done")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(CoralGradientButtonStyle())
                .accessibilityIdentifier("strength.debrief.done")
            }
            .padding(DSSpacing.lg)
        }
        .background(DSColor.background.ignoresSafeArea())
        .navigationTitle("Coach Debrief")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .accessibilityIdentifier("strength.debrief.root")
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: DSSpacing.sm) {
            Text("Workout complete")
                .font(.title2.weight(.bold))
                .foregroundStyle(DSColor.textPrimary)
            HStack(spacing: DSSpacing.md) {
                Label(formatDuration(debrief.durationSeconds), systemImage: "clock")
                Label("\(debrief.totalWorkingSets) sets", systemImage: "list.number")
                Label("\(debrief.exercisesCompleted) exercises", systemImage: "figure.strengthtraining.traditional")
            }
            .font(.caption)
            .foregroundStyle(DSColor.textSecondary)
            if debrief.exercisesSkipped > 0 {
                Text("\(debrief.exercisesSkipped) exercise(s) skipped")
                    .font(.caption)
                    .foregroundStyle(DSColor.textSecondary)
            }
        }
    }

    private func section(title: String, items: [StrengthDebriefExerciseSummary]) -> some View {
        VStack(alignment: .leading, spacing: DSSpacing.md) {
            Text(title)
                .font(.headline)
                .foregroundStyle(DSColor.textPrimary)
            ForEach(items) { item in
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.exerciseName)
                        .font(.subheadline.weight(.semibold))
                    Text(item.summaryLine)
                        .font(.subheadline)
                        .foregroundStyle(DSColor.textPrimary)
                    Text(item.detail)
                        .font(.caption)
                        .foregroundStyle(DSColor.textSecondary)
                }
                .padding(DSSpacing.md)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(DSColor.surface)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
        }
    }

    private var nextTimeSection: some View {
        VStack(alignment: .leading, spacing: DSSpacing.md) {
            Text("Next time")
                .font(.headline)
                .foregroundStyle(DSColor.textPrimary)
            ForEach(debrief.nextTimeRecommendations) { item in
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.exerciseName)
                        .font(.subheadline.weight(.semibold))
                    Text(item.recommendation)
                        .font(.subheadline)
                        .foregroundStyle(DSColor.textSecondary)
                }
                .padding(DSSpacing.md)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(DSColor.surface)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
        }
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let minutes = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", minutes, secs)
    }
}
