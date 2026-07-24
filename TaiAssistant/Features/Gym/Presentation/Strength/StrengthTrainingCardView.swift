import SwiftUI

struct StrengthTrainingCardView: View {
    let state: StrengthTrainingCardState
    var onResume: () -> Void
    var onStart: () -> Void

    var body: some View {
        switch state {
        case .active(let model):
            activeCard(model)
        case .planned(let model):
            plannedCard(model)
        }
    }

    @ViewBuilder
    private func activeCard(_ model: StrengthActiveWorkoutCardModel) -> some View {
        PrimaryCard(cornerRadius: 24, useWarmBackground: true) {
            Label("Active workout", systemImage: "figure.strengthtraining.traditional")
                .font(.caption.weight(.semibold))
                .foregroundStyle(DSColor.coralEnd)

            Text(model.title)
                .font(.title3.weight(.bold))
                .foregroundStyle(DSColor.textPrimary)

            HStack(spacing: DSSpacing.md) {
                metricChip(title: "Elapsed", value: formatDuration(model.elapsedSeconds))
                metricChip(title: "Sets", value: "\(model.completedSets)/\(model.totalSets)")
            }

            if let current = model.currentExerciseName {
                Text("Now: \(current)")
                    .font(.subheadline)
                    .foregroundStyle(DSColor.textSecondary)
            } else if let next = model.nextExerciseName {
                Text("Next: \(next)")
                    .font(.subheadline)
                    .foregroundStyle(DSColor.textSecondary)
            }

            Button(action: onResume) {
                Text("Resume Workout")
            }
            .buttonStyle(CoralGradientButtonStyle())
            .accessibilityIdentifier("strength.home.resume")
        }
    }

    @ViewBuilder
    private func plannedCard(_ model: StrengthPlannedWorkoutCardModel) -> some View {
        PrimaryCard(cornerRadius: 24, useWarmBackground: true) {
            Label("Today's training", systemImage: "figure.strengthtraining.traditional")
                .font(.caption.weight(.semibold))
                .foregroundStyle(DSColor.coralEnd)

            Text(model.title)
                .font(.title3.weight(.bold))
                .foregroundStyle(DSColor.textPrimary)

            HStack(spacing: DSSpacing.md) {
                metricChip(title: "Duration", value: "~\(model.estimatedDurationMinutes) min")
                metricChip(title: "Exercises", value: "\(model.exerciseCount)")
            }

            VStack(alignment: .leading, spacing: DSSpacing.xs) {
                Text("Today's mission")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(DSColor.textSecondary)
                Text(model.mission)
                    .font(.subheadline)
                    .foregroundStyle(DSColor.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let progression = model.primaryProgression {
                progressionSnippet(progression)
            }

            Button(action: onStart) {
                Text("Start Workout")
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
            }
            .buttonStyle(CoralGradientButtonStyle())
            .accessibilityIdentifier("strength.home.start")
        }
    }

    @ViewBuilder
    private func progressionSnippet(_ proposal: StrengthProgressionProposal) -> some View {
        VStack(alignment: .leading, spacing: DSSpacing.xs) {
            Text(proposal.exerciseName)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(DSColor.textPrimary)

            if let current = proposal.currentWeight, let proposed = proposal.proposedWeight, proposed != current {
                Text("Recommendation: \(proposed.formattedStrengthWeight) \(proposal.weightUnit)")
                    .font(.subheadline)
                    .foregroundStyle(DSColor.coralEnd)
            } else if let current = proposal.currentWeight {
                Text("Hold \(current.formattedStrengthWeight) \(proposal.weightUnit)")
                    .font(.subheadline)
                    .foregroundStyle(DSColor.textSecondary)
            }

            Text("Target: \(proposal.reasoning.targetRepsLabel)")
                .font(.caption)
                .foregroundStyle(DSColor.textSecondary)
        }
        .padding(DSSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DSColor.surface)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func metricChip(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption)
                .foregroundStyle(DSColor.textSecondary)
            Text(value)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(DSColor.textPrimary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let minutes = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", minutes, secs)
    }
}
