import SwiftUI

struct StrengthExerciseWorkspaceCardView: View {
    let exercise: StrengthExerciseInstance
    let session: StrengthWorkoutSession
    var isExpanded: Bool
    var isInteractive: Bool
    var onActivate: () -> Void
    var onDraftChange: (Double, Int) -> Void
    var onConfirmSet: (Double, Int) -> Void
    var onSkipSet: () -> Void
    var onAddEvidence: () -> Void

    @State private var editWeight: Double = 0
    @State private var editReps: Int = 0
    @State private var hasEditedWeight = false

    private var requiresExplicitWeightEntry: Bool {
        guard let set = currentSet else { return false }
        return set.suggestedWeight == nil && set.confirmedWeight == nil
    }

    private var canConfirmSet: Bool {
        !requiresExplicitWeightEntry || hasEditedWeight
    }

    private var currentSet: StrengthSetRecord? {
        guard exercise.id == session.currentExerciseInstanceID else {
            return StrengthSessionNavigation.firstUnresolvedSet(in: exercise)
        }
        return session.currentSet ?? StrengthSessionNavigation.firstUnresolvedSet(in: exercise)
    }

    private var weightStep: Double {
        StrengthWeightIncrement.defaultIncrement(for: exercise.exerciseID)
    }

    var body: some View {
        Group {
            if isExpanded {
                expandedWorkspace
            } else {
                compactSummary
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
        .accessibilityIdentifier("strength.conversation.exerciseWorkspace.\(exercise.exerciseID)")
    }

    private var compactSummary: some View {
        Button(action: onActivate) {
            HStack(spacing: DSSpacing.sm) {
                VStack(alignment: .leading, spacing: DSSpacing.xs) {
                    Text(exercise.displayName)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(DSColor.textPrimary)
                    if let nextSet = StrengthSessionNavigation.firstUnresolvedSet(in: exercise) {
                        Text("Set \(nextSet.setNumber) pending")
                            .font(.caption)
                            .foregroundStyle(DSColor.textSecondary)
                    } else if exercise.status == .completed {
                        Text("All sets complete")
                            .font(.caption)
                            .foregroundStyle(DSColor.textSecondary)
                    }
                    confirmedHistoryText
                }
                Spacer()
                Image(systemName: "chevron.down")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(DSColor.textSecondary)
            }
        }
        .buttonStyle(.plain)
        .disabled(!isInteractive)
    }

    private var expandedWorkspace: some View {
        VStack(alignment: .leading, spacing: DSSpacing.md) {
            header
            confirmedHistory
            if let set = currentSet, set.status == .pending {
                currentSetEditor(set)
            } else if exercise.status == .completed {
                Text("All sets complete")
                    .font(.subheadline)
                    .foregroundStyle(DSColor.textSecondary)
            }
        }
        .onAppear { syncEditors() }
        .onChange(of: session.currentSetID) { _, _ in
            syncEditors()
            hasEditedWeight = false
        }
    }

    @ViewBuilder
    private var confirmedHistoryText: some View {
        let confirmed = exercise.workingSets.filter { $0.status == .confirmed }
        if !confirmed.isEmpty {
            Text(confirmed.map {
                "Set \($0.setNumber): \(StrengthSetFormatting.confirmedLine(for: $0, exercise: exercise))"
            }.joined(separator: " · "))
            .font(.caption2)
            .foregroundStyle(DSColor.textSecondary)
            .lineLimit(2)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: DSSpacing.xs) {
            Text(exercise.displayName)
                .font(.headline)
                .foregroundStyle(DSColor.textPrimary)
            if let set = currentSet, set.status == .pending {
                Text("Set \(set.setNumber) of \(exercise.workingSets.count)")
                    .font(.subheadline)
                    .foregroundStyle(DSColor.textSecondary)
                    .accessibilityIdentifier("strength.conversation.currentSetLabel")
            }
        }
    }

    @ViewBuilder
    private var confirmedHistory: some View {
        let confirmed = exercise.workingSets.filter { $0.status == .confirmed }
        if !confirmed.isEmpty {
            VStack(alignment: .leading, spacing: DSSpacing.xs) {
                Text("Completed")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(DSColor.textSecondary)
                ForEach(confirmed) { set in
                    Text("Set \(set.setNumber) — \(StrengthSetFormatting.confirmedLine(for: set, exercise: exercise))")
                        .font(.caption)
                        .foregroundStyle(DSColor.textPrimary)
                        .accessibilityIdentifier("strength.conversation.confirmedSet.\(set.setNumber)")
                }
            }
        }
    }

    @ViewBuilder
    private func currentSetEditor(_ set: StrengthSetRecord) -> some View {
        VStack(spacing: DSSpacing.md) {
            if set.suggestedWeight == nil, set.confirmedWeight == nil {
                Text("Enter or confirm the weight for this set.")
                    .font(.caption)
                    .foregroundStyle(DSColor.textSecondary)
                    .accessibilityIdentifier("strength.conversation.weight.needsEntry")
            }
            HStack(spacing: DSSpacing.lg) {
                valueStepper(
                    title: "Weight",
                    valueText: "\(editWeight.formattedStrengthWeight) \(set.weightUnit)",
                    decrementID: "strength.conversation.weight.decrement",
                    incrementID: "strength.conversation.weight.increment",
                    onDecrement: {
                        hasEditedWeight = true
                        editWeight = max(0, editWeight - weightStep)
                        onDraftChange(editWeight, editReps)
                    },
                    onIncrement: {
                        hasEditedWeight = true
                        editWeight += weightStep
                        onDraftChange(editWeight, editReps)
                    }
                )
                valueStepper(
                    title: "Reps",
                    valueText: "\(editReps)",
                    decrementID: "strength.conversation.reps.decrement",
                    incrementID: "strength.conversation.reps.increment",
                    onDecrement: {
                        editReps = max(0, editReps - 1)
                        onDraftChange(editWeight, editReps)
                    },
                    onIncrement: {
                        editReps += 1
                        onDraftChange(editWeight, editReps)
                    }
                )
            }

            if isInteractive {
                HStack(spacing: DSSpacing.sm) {
                    Button("Skip Set", action: onSkipSet)
                        .buttonStyle(.bordered)
                        .tint(DSColor.textSecondary)
                    Button(action: { onConfirmSet(editWeight, editReps) }) {
                        Text("Confirm Set")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(DSColor.coralEnd)
                    .disabled(!canConfirmSet)
                    .accessibilityIdentifier("strength.conversation.confirmSet")
                }

                Button(action: onAddEvidence) {
                    Label("Add Evidence", systemImage: "camera")
                        .font(.caption.weight(.semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(DSColor.coralEnd)
            }
        }
    }

    private func valueStepper(
        title: String,
        valueText: String,
        decrementID: String,
        incrementID: String,
        onDecrement: @escaping () -> Void,
        onIncrement: @escaping () -> Void
    ) -> some View {
        VStack(spacing: DSSpacing.xs) {
            Text(title)
                .font(.caption)
                .foregroundStyle(DSColor.textSecondary)
            Text(valueText)
                .font(.title3.weight(.bold))
                .accessibilityIdentifier(title == "Weight" ? "strength.conversation.weight.value" : "strength.conversation.reps.value")
            HStack(spacing: DSSpacing.md) {
                Button(action: onDecrement) {
                    Image(systemName: "minus.circle.fill")
                }
                .accessibilityIdentifier(decrementID)
                Button(action: onIncrement) {
                    Image(systemName: "plus.circle.fill")
                }
                .accessibilityIdentifier(incrementID)
            }
            .font(.title2)
            .foregroundStyle(DSColor.coralEnd)
            .buttonStyle(.plain)
            .disabled(!isInteractive)
        }
        .frame(maxWidth: .infinity)
    }

    private func syncEditors() {
        guard let set = currentSet else { return }
        editWeight = set.suggestedWeight ?? set.confirmedWeight ?? 0
        editReps = set.suggestedReps ?? set.plannedReps ?? set.confirmedReps ?? 0
        hasEditedWeight = set.suggestedWeight != nil || set.confirmedWeight != nil
    }
}
