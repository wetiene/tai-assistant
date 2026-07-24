import SwiftUI

struct StrengthWorkoutOverviewCardView: View {
    let session: StrengthWorkoutSession
    let pendingProposals: [StrengthProgressionProposal]
    var isInteractive: Bool
    var onAcceptProgression: (String) -> Void
    var onHoldProgression: (String) -> Void
    var onAcceptAllProgressions: () -> Void
    var onOpenDedicatedWorkout: () -> Void

    private var keyProposals: [StrengthProgressionProposal] {
        Array(pendingProposals.prefix(3))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DSSpacing.md) {
            HStack {
                VStack(alignment: .leading, spacing: DSSpacing.xs) {
                    Text(session.title)
                        .font(.headline)
                        .foregroundStyle(DSColor.textPrimary)
                    Text(session.mission)
                        .font(.subheadline)
                        .foregroundStyle(DSColor.textSecondary)
                }
                Spacer()
                progressBadge
            }

            if isInteractive, !keyProposals.isEmpty {
                progressionSection
            }

            VStack(alignment: .leading, spacing: DSSpacing.sm) {
                ForEach(session.exercises) { exercise in
                    exerciseRow(exercise)
                }
            }

            if isInteractive {
                Button(action: onOpenDedicatedWorkout) {
                    Label("Open Workout Screen", systemImage: "arrow.up.left.and.arrow.down.right")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(DSColor.coralEnd)
                .accessibilityIdentifier("strength.conversation.openDedicated")
            }
        }
        .padding(DSSpacing.md)
        .background(DSColor.surface)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(DSColor.cardStroke, lineWidth: 1)
        )
        .frame(maxWidth: 340)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("strength.conversation.overview")
        .accessibilityLabel("Workout overview, \(session.title)")
    }

    private var progressionSection: some View {
        VStack(alignment: .leading, spacing: DSSpacing.sm) {
            HStack {
                Text("Suggested progressions")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(DSColor.textPrimary)
                Spacer()
                if pendingProposals.count > 1 {
                    Button("Accept all", action: onAcceptAllProgressions)
                        .font(.caption.weight(.semibold))
                        .accessibilityIdentifier("strength.conversation.acceptAllProgressions")
                }
            }

            ForEach(keyProposals) { proposal in
                VStack(alignment: .leading, spacing: DSSpacing.xs) {
                    Text(proposal.exerciseName)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(DSColor.textPrimary)
                    Text(proposal.reasoning.recommendation)
                        .font(.caption)
                        .foregroundStyle(DSColor.textSecondary)
                    HStack(spacing: DSSpacing.sm) {
                        Button("Accept") {
                            onAcceptProgression(proposal.exerciseID)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(DSColor.coralEnd)
                        .font(.caption.weight(.semibold))
                        .accessibilityIdentifier("strength.conversation.acceptProgression.\(proposal.exerciseID)")

                        Button("Keep previous") {
                            onHoldProgression(proposal.exerciseID)
                        }
                        .buttonStyle(.bordered)
                        .font(.caption.weight(.semibold))
                        .accessibilityIdentifier("strength.conversation.holdProgression.\(proposal.exerciseID)")
                    }
                }
                .padding(DSSpacing.sm)
                .background(DSColor.warmSurface)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
    }

    private var progressBadge: some View {
        let completed = session.completedWorkingSetCount
        let total = session.totalPlannedWorkingSets
        return Text("\(completed)/\(total)")
            .font(.caption.weight(.bold))
            .foregroundStyle(DSColor.coralEnd)
            .padding(.horizontal, DSSpacing.sm)
            .padding(.vertical, DSSpacing.xs)
            .background(DSColor.warmSurface)
            .clipShape(Capsule())
    }

    @ViewBuilder
    private func exerciseRow(_ exercise: StrengthExerciseInstance) -> some View {
        let working = exercise.workingSets
        let resolved = working.filter { $0.status == .confirmed || $0.status == .skipped }.count
        let displayState = StrengthSessionNavigation.displayState(
            for: exercise,
            isCurrent: exercise.id == session.currentExerciseInstanceID
        )

        HStack(spacing: DSSpacing.sm) {
            statusIcon(for: displayState)
            VStack(alignment: .leading, spacing: 2) {
                Text(exercise.displayName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(DSColor.textPrimary)
                if let proposal = session.acceptedProposals[exercise.exerciseID] {
                    Text(proposalSummary(proposal, exercise: exercise))
                        .font(.caption)
                        .foregroundStyle(DSColor.textSecondary)
                }
            }
            Spacer()
            Text("\(resolved)/\(working.count)")
                .font(.caption.weight(.medium))
                .foregroundStyle(DSColor.textSecondary)
        }
    }

    @ViewBuilder
    private func statusIcon(for state: StrengthExerciseDisplayState) -> some View {
        switch state {
        case .completed:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .partial:
            Image(systemName: "circle.lefthalf.filled")
                .foregroundStyle(DSColor.coralEnd)
        case .active:
            Image(systemName: "circle.fill")
                .foregroundStyle(DSColor.coralEnd)
        case .skipped:
            Image(systemName: "minus.circle")
                .foregroundStyle(DSColor.textSecondary)
        case .upcoming:
            Image(systemName: "circle")
                .foregroundStyle(DSColor.textSecondary.opacity(0.5))
        }
    }

    private func proposalSummary(
        _ proposal: StrengthAcceptedProposal,
        exercise: StrengthExerciseInstance
    ) -> String {
        let repRange = exercise.plannedExercise.effectiveRepRange(planPrescription: session.prescription)
        if let weight = proposal.weight {
            return "\(weight.formattedStrengthWeight) \(proposal.weightUnit) · \(repRange.lower)–\(repRange.upper) reps"
        }
        return "\(repRange.lower)–\(repRange.upper) reps"
    }
}
