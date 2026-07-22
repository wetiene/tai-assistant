import SwiftUI

struct StrengthPreFlightView: View {
    let plan: GymResolvablePlan
    let proposals: [StrengthProgressionProposal]
    @Binding var acceptedProposals: [String: StrengthAcceptedProposal]
    var onStart: () -> Void
    var onEditPlan: () -> Void
    var onCancel: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DSSpacing.xl) {
                header
                missionSection
                if !keyProposals.isEmpty {
                    progressionSection
                }
                actions
            }
            .padding(DSSpacing.lg)
        }
        .background(DSColor.background.ignoresSafeArea())
        .navigationTitle("Pre-Flight")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel", action: onCancel)
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: DSSpacing.sm) {
            Text(plan.title)
                .font(.title2.weight(.bold))
                .foregroundStyle(DSColor.textPrimary)

            if let section = plan.sectionName {
                Text(section)
                    .font(.subheadline)
                    .foregroundStyle(DSColor.textSecondary)
            }

            HStack(spacing: DSSpacing.lg) {
                Label("~\(StrengthSessionBuilder.estimatedDurationMinutes(for: plan)) min", systemImage: "clock")
                Label("\(plan.exercises.count) exercises", systemImage: "list.bullet")
            }
            .font(.subheadline)
            .foregroundStyle(DSColor.textSecondary)
        }
    }

    private var missionSection: some View {
        VStack(alignment: .leading, spacing: DSSpacing.xs) {
            Text("Today's mission")
                .font(.caption.weight(.semibold))
                .foregroundStyle(DSColor.coralEnd)
            Text(StrengthSessionBuilder.buildMission(plan: plan, primaryProposal: keyProposals.first))
                .font(.body)
                .foregroundStyle(DSColor.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var keyProposals: [StrengthProgressionProposal] {
        Array(proposals.prefix(3))
    }

    private var progressionSection: some View {
        VStack(alignment: .leading, spacing: DSSpacing.md) {
            Text("Key progressions")
                .font(.headline)
                .foregroundStyle(DSColor.textPrimary)

            ForEach(keyProposals) { proposal in
                StrengthProgressionProposalCard(
                    proposal: proposal,
                    userDecision: acceptedProposals[proposal.exerciseID]?.decision,
                    onAccept: { accept(proposal) },
                    onHold: { hold(proposal) },
                    onAdjust: { weight in adjust(proposal, weight: weight) }
                )
            }
        }
    }

    private var actions: some View {
        VStack(spacing: DSSpacing.md) {
            Button(action: onStart) {
                Text("Start Workout")
            }
            .buttonStyle(CoralGradientButtonStyle())
            .accessibilityIdentifier("strength.preflight.start")

            Button("Edit Today's Plan", action: onEditPlan)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(DSColor.coralEnd)
                .buttonStyle(.plain)
        }
    }

    private func accept(_ proposal: StrengthProgressionProposal) {
        acceptedProposals[proposal.exerciseID] = StrengthAcceptedProposal(
            exerciseID: proposal.exerciseID,
            decision: .accepted,
            weight: proposal.proposedWeight ?? proposal.currentWeight,
            weightUnit: proposal.weightUnit,
            originalProposal: proposal
        )
    }

    private func hold(_ proposal: StrengthProgressionProposal) {
        acceptedProposals[proposal.exerciseID] = StrengthAcceptedProposal(
            exerciseID: proposal.exerciseID,
            decision: .hold,
            weight: proposal.currentWeight,
            weightUnit: proposal.weightUnit,
            originalProposal: proposal
        )
    }

    private func adjust(_ proposal: StrengthProgressionProposal, weight: Double) {
        acceptedProposals[proposal.exerciseID] = StrengthAcceptedProposal(
            exerciseID: proposal.exerciseID,
            decision: .custom,
            weight: weight,
            weightUnit: proposal.weightUnit,
            originalProposal: proposal
        )
    }
}

private struct StrengthProgressionProposalCard: View {
    let proposal: StrengthProgressionProposal
    let userDecision: StrengthProposalUserDecision?
    var onAccept: () -> Void
    var onHold: () -> Void
    var onAdjust: (Double) -> Void

    @State private var showsAdjust = false
    @State private var adjustWeight: Double

    init(
        proposal: StrengthProgressionProposal,
        userDecision: StrengthProposalUserDecision?,
        onAccept: @escaping () -> Void,
        onHold: @escaping () -> Void,
        onAdjust: @escaping (Double) -> Void
    ) {
        self.proposal = proposal
        self.userDecision = userDecision
        self.onAccept = onAccept
        self.onHold = onHold
        self.onAdjust = onAdjust
        _adjustWeight = State(initialValue: proposal.proposedWeight ?? proposal.currentWeight ?? 0)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DSSpacing.sm) {
            HStack {
                Text(proposal.exerciseName)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                confidenceBadge
            }

            Text(proposal.reasoning.observation)
                .font(.caption)
                .foregroundStyle(DSColor.textSecondary)

            Text(proposal.reasoning.recommendation)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(DSColor.textPrimary)

            Text("Target: \(proposal.reasoning.targetRepsLabel)")
                .font(.caption)
                .foregroundStyle(DSColor.textSecondary)

            HStack(spacing: DSSpacing.sm) {
                decisionButton("Accept", selected: userDecision == .accepted, action: onAccept)
                    .accessibilityIdentifier("strength.preflight.accept.\(proposal.exerciseID)")
                decisionButton("Hold", selected: userDecision == .hold, action: onHold)
                decisionButton("Adjust", selected: userDecision == .custom, action: { showsAdjust.toggle() })
            }

            if showsAdjust {
                HStack {
                    Stepper(value: $adjustWeight, in: 0...500, step: StrengthWeightIncrement.defaultIncrement(for: proposal.exerciseID)) {
                        Text("\(adjustWeight.formattedStrengthWeight) \(proposal.weightUnit)")
                            .font(.subheadline.weight(.semibold))
                    }
                    Button("Apply") {
                        onAdjust(adjustWeight)
                        showsAdjust = false
                    }
                    .font(.subheadline.weight(.semibold))
                }
            }
        }
        .padding(DSSpacing.md)
        .background(DSColor.surface)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(DSColor.cardStroke, lineWidth: 1)
        )
    }

    private var confidenceBadge: some View {
        Text(proposal.confidence.rawValue.capitalized)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(DSColor.textSecondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(DSColor.background)
            .clipShape(Capsule())
    }

    private func decisionButton(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.caption.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(selected ? DSColor.coralEnd.opacity(0.15) : DSColor.background)
                .foregroundStyle(selected ? DSColor.coralEnd : DSColor.textSecondary)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}
