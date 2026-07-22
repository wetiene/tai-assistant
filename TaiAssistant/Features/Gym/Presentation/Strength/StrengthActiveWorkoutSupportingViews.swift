import SwiftUI

struct StrengthSetEditorContext: Identifiable, Equatable {
    let exerciseInstanceID: UUID
    let setID: UUID
    var id: UUID { setID }
}

struct StrengthSetEditorSheet: View {
    let exercise: StrengthExerciseInstance
    let set: StrengthSetRecord
    var onSave: (Double, Int) -> Void
    var onMarkSkipped: () -> Void
    var onRestore: () -> Void
    var onDeleteExtra: (() -> Void)?
    var onCancel: () -> Void

    @State private var weight: Double
    @State private var reps: Int
    @Environment(\.dismiss) private var dismiss

    init(
        exercise: StrengthExerciseInstance,
        set: StrengthSetRecord,
        onSave: @escaping (Double, Int) -> Void,
        onMarkSkipped: @escaping () -> Void,
        onRestore: @escaping () -> Void,
        onDeleteExtra: (() -> Void)? = nil,
        onCancel: @escaping () -> Void
    ) {
        self.exercise = exercise
        self.set = set
        self.onSave = onSave
        self.onMarkSkipped = onMarkSkipped
        self.onRestore = onRestore
        self.onDeleteExtra = onDeleteExtra
        self.onCancel = onCancel
        _weight = State(initialValue: set.confirmedWeight ?? set.suggestedWeight ?? 0)
        _reps = State(initialValue: set.confirmedReps ?? set.suggestedReps ?? set.plannedReps ?? 0)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Set \(set.setNumber)") {
                    if exercise.plannedExercise.tracksBodyweight {
                        LabeledContent("Weight", value: "Bodyweight")
                    } else {
                        Stepper(
                            "Weight: \(weight.formattedStrengthWeight) \(set.weightUnit)",
                            value: $weight,
                            in: 0...500,
                            step: StrengthWeightIncrement.defaultIncrement(for: exercise.exerciseID)
                        )
                    }
                    Stepper("Reps: \(reps)", value: $reps, in: 0...50)
                }

                if set.status == .confirmed {
                    Section {
                        Button("Mark Skipped", role: .destructive, action: onMarkSkipped)
                    }
                } else if set.status == .skipped {
                    Section {
                        Button("Restore Set", action: onRestore)
                    }
                }

                if set.isUserAdded, let onDeleteExtra {
                    Section {
                        Button("Delete Extra Set", role: .destructive, action: onDeleteExtra)
                    }
                }
            }
            .navigationTitle("Edit Set")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        onCancel()
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(weight, reps)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

struct StrengthPhotoAssistReviewSheet: View {
    let result: StrengthPhotoAssistResult
    let activeExerciseName: String
    var onApply: () -> Void
    var onSwitchExercise: (() -> Void)?
    var onCancel: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("Tai found") {
                    if let weight = result.suggestedWeight {
                        LabeledContent("Weight") {
                            Text("\(weight.formattedStrengthWeight) \(result.weightUnit)")
                        }
                    } else {
                        LabeledContent("Weight") {
                            Text("Could not determine weight")
                                .foregroundStyle(DSColor.textSecondary)
                        }
                    }

                    if let name = result.detectedExerciseName {
                        LabeledContent("Exercise", value: name)
                    }

                    if let confidence = result.interpretation.detectedWeight?.confidence {
                        LabeledContent("Confidence", value: confidenceLabel(confidence))
                    }
                }

                if !result.matchesActiveExercise {
                    Section {
                        Text("This may not match \(activeExerciseName).")
                            .font(.subheadline)
                            .foregroundStyle(DSColor.textSecondary)
                    }
                }

                if !result.interpretation.limitations.isEmpty {
                    Section("Notes") {
                        ForEach(result.interpretation.limitations, id: \.self) { note in
                            Text(note)
                                .font(.subheadline)
                        }
                    }
                }
            }
            .navigationTitle("Review Photo")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        onCancel()
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Apply to Set") {
                        onApply()
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .disabled(result.suggestedWeight == nil)
                }
            }
            .safeAreaInset(edge: .bottom) {
                if !result.matchesActiveExercise, let onSwitchExercise {
                    Button("Switch to \(result.detectedExerciseName ?? "matching exercise")") {
                        onSwitchExercise()
                        dismiss()
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(DSColor.coralEnd)
                    .frame(maxWidth: .infinity)
                    .padding()
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func confidenceLabel(_ value: Double) -> String {
        switch value {
        case 0.75...: return "High"
        case 0.45...: return "Medium"
        default: return "Low"
        }
    }
}

struct StrengthWorkoutCompletionReviewSheet: View {
    let session: StrengthWorkoutSession
    var onReturn: () -> Void
    var onSkipRemainingAndComplete: () -> Void
    var onCancel: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("Summary") {
                    LabeledContent("Confirmed sets", value: "\(confirmedCount)")
                    LabeledContent("Skipped sets", value: "\(skippedCount)")
                    LabeledContent("Incomplete sets", value: "\(pendingCount)")
                }

                if pendingCount > 0 {
                    Section("Incomplete work remains") {
                        ForEach(incompleteExercises, id: \.id) { exercise in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(exercise.displayName)
                                    .font(.subheadline.weight(.semibold))
                                Text("\(exercise.workingSets.filter { $0.status == .pending }.count) sets unresolved")
                                    .font(.caption)
                                    .foregroundStyle(DSColor.textSecondary)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Complete Workout")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        onCancel()
                        dismiss()
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: DSSpacing.md) {
                    Button("Return to Workout") {
                        onReturn()
                        dismiss()
                    }
                    .buttonStyle(.bordered)

                    if pendingCount > 0 {
                        Button("Mark Remaining Skipped and Complete") {
                            onSkipRemainingAndComplete()
                            dismiss()
                        }
                        .buttonStyle(CoralGradientButtonStyle())
                        .accessibilityIdentifier("strength.active.completeWithSkipped")
                    }
                }
                .padding()
            }
        }
        .presentationDetents([.medium, .large])
    }

    private var confirmedCount: Int {
        session.exercises.flatMap(\.workingSets).filter { $0.status == .confirmed }.count
    }

    private var skippedCount: Int {
        session.exercises.flatMap(\.workingSets).filter { $0.status == .skipped }.count
    }

    private var pendingCount: Int {
        StrengthSessionNavigation.unresolvedSetCount(in: session)
    }

    private var incompleteExercises: [StrengthExerciseInstance] {
        session.exercises.filter { exercise in
            exercise.status != .skipped && exercise.workingSets.contains { $0.status == .pending }
        }
    }
}

struct StrengthExerciseNavigatorCard: View {
    let exercise: StrengthExerciseInstance
    let session: StrengthWorkoutSession
    let isCurrent: Bool
    var onSelectExercise: () -> Void
    var onSelectSet: (UUID) -> Void

    private var displayState: StrengthExerciseDisplayState {
        StrengthSessionNavigation.displayState(for: exercise, isCurrent: isCurrent)
    }

    var body: some View {
        Button(action: onSelectExercise) {
            VStack(alignment: .leading, spacing: DSSpacing.sm) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(exercise.displayName)
                            .font(.subheadline.weight(isCurrent ? .bold : .semibold))
                            .foregroundStyle(DSColor.textPrimary)
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(DSColor.textSecondary)
                    }
                    Spacer()
                    stateBadge
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(DSColor.textSecondary)
                }

                ForEach(exercise.workingSets) { set in
                    setRow(set)
                }
            }
            .padding(DSSpacing.md)
            .background(isCurrent ? DSColor.coralEnd.opacity(0.08) : DSColor.surface)
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(isCurrent ? DSColor.coralEnd.opacity(0.35) : Color.clear, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("strength.active.exercise.\(exercise.exerciseID)")
    }

    @ViewBuilder
    private var stateBadge: some View {
        switch displayState {
        case .active:
            Text("Active").font(.caption2.weight(.semibold)).foregroundStyle(DSColor.coralEnd)
        case .completed:
            Image(systemName: "checkmark.circle.fill").foregroundStyle(DSColor.coralEnd)
        case .skipped:
            Text("Skipped").font(.caption2).foregroundStyle(DSColor.textSecondary)
        case .partial(let completed, let total):
            Text("\(completed)/\(total)").font(.caption2.weight(.semibold)).foregroundStyle(DSColor.coralEnd)
        case .upcoming:
            EmptyView()
        }
    }

    private var subtitle: String {
        switch displayState {
        case .active:
            let resolved = exercise.workingSets.filter { $0.status != .pending }.count
            return "Active · \(resolved) of \(exercise.workingSets.count) sets"
        case .partial(let completed, let total):
            return "In progress · \(completed) of \(total) sets"
        case .completed:
            return "Completed · \(exercise.workingSets.count) sets"
        case .skipped:
            return "Skipped"
        case .upcoming:
            return "Upcoming · \(exercise.workingSets.count) sets"
        }
    }

    @ViewBuilder
    private func setRow(_ set: StrengthSetRecord) -> some View {
        let isCurrentSet = set.id == session.currentSetID && exercise.id == session.currentExerciseInstanceID
        Button {
            if set.status == .confirmed || set.status == .skipped {
                onSelectSet(set.id)
            } else {
                onSelectSet(set.id)
            }
        } label: {
            HStack {
                Text("Set \(set.setNumber)")
                    .font(.caption)
                    .foregroundStyle(DSColor.textSecondary)
                Spacer()
                Text(StrengthSetFormatting.displayLine(for: set, exercise: exercise))
                    .font(.caption.weight(isCurrentSet ? .bold : .medium))
                    .foregroundStyle(set.status == .pending ? DSColor.textSecondary : DSColor.textPrimary)
                if isCurrentSet {
                    Text("· next")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(DSColor.coralEnd)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("strength.active.set.\(set.setNumber)")
    }
}

struct StrengthExerciseCompleteBanner: View {
    let exerciseName: String
    var onNextExercise: () -> Void
    var onChooseExercise: () -> Void
    var onStay: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: DSSpacing.md) {
            Text("\(exerciseName) complete")
                .font(.headline)
                .foregroundStyle(DSColor.textPrimary)
            HStack(spacing: DSSpacing.md) {
                Button("Next", action: onNextExercise)
                Button("Choose", action: onChooseExercise)
                Button("Stay", action: onStay)
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(DSColor.coralEnd)
        }
        .padding(DSSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DSColor.coralEnd.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}
