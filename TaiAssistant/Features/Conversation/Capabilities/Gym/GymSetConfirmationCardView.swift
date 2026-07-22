import SwiftUI

struct GymSetConfirmationCardView: View {
    @State private var payload: GymSetConfirmationCardPayload
    let isInteractive: Bool
    var onDraftChange: (GymSetConfirmationCardPayload) -> Void
    var onAction: (GymCapabilityID.CardAction, GymSetConfirmationCardPayload) -> Void

    @State private var weightText: String
    @State private var repsText: String
    @State private var isExercisePickerPresented = false

    init(
        payload: GymSetConfirmationCardPayload,
        isInteractive: Bool,
        onDraftChange: @escaping (GymSetConfirmationCardPayload) -> Void,
        onAction: @escaping (GymCapabilityID.CardAction, GymSetConfirmationCardPayload) -> Void
    ) {
        _payload = State(initialValue: payload)
        self.isInteractive = isInteractive
        self.onDraftChange = onDraftChange
        self.onAction = onAction
        _weightText = State(initialValue: GymSetCardValidation.formatWeight(payload.weightValue))
        _repsText = State(initialValue: payload.repetitions.map(String.init) ?? "")
    }

    var body: some View {
        PrimaryCard(cornerRadius: 20) {
            VStack(alignment: .leading, spacing: DSSpacing.md) {
                header
                if isInteractive && !payload.isSaved {
                    Text(GymSetCardFormatting.notLoggedDisclaimer)
                        .font(.caption)
                        .foregroundStyle(DSColor.textSecondary)
                }
                exerciseField
                weightField
                repsField
                aiContextSection
                if isInteractive && !payload.isSaved {
                    actionButtons
                }
            }
        }
        .frame(maxWidth: 340, alignment: .leading)
        .sheet(isPresented: $isExercisePickerPresented) {
            exercisePickerSheet
        }
    }

    private var header: some View {
        HStack {
            Text("Set \(payload.setNumber)")
                .font(.caption.weight(.semibold))
                .foregroundStyle(DSColor.coralEnd)
            Spacer()
            if payload.isSaved {
                Label("Saved", systemImage: "checkmark.circle.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(DSColor.coralEnd)
            }
        }
    }

    private var exerciseField: some View {
        VStack(alignment: .leading, spacing: DSSpacing.xs) {
            Text("Exercise")
                .font(.caption.weight(.semibold))
                .foregroundStyle(DSColor.textSecondary)

            if isInteractive && !payload.isSaved {
                Button {
                    isExercisePickerPresented = true
                } label: {
                    HStack {
                        Text(payload.selectedExerciseID.isEmpty ? "Select exercise" : payload.selectedExerciseName)
                            .foregroundStyle(payload.selectedExerciseID.isEmpty ? DSColor.textSecondary : DSColor.textPrimary)
                        Spacer()
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.caption)
                            .foregroundStyle(DSColor.textSecondary)
                    }
                    .padding(.horizontal, DSSpacing.sm)
                    .padding(.vertical, DSSpacing.sm)
                    .background(DSColor.warmSurface)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(.plain)
            } else {
                Text(payload.selectedExerciseName.isEmpty ? "—" : payload.selectedExerciseName)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(DSColor.textPrimary)
            }
        }
    }

    private var exercisePickerSheet: some View {
        NavigationStack {
            List(payload.templateExerciseOptions) { option in
                Button {
                    payload.selectedExerciseID = option.exerciseID
                    payload.selectedExerciseName = option.displayName
                    isExercisePickerPresented = false
                    publishDraftChange()
                } label: {
                    HStack {
                        Text(option.displayName + (option.isOptional ? " (optional)" : ""))
                        Spacer()
                        if payload.selectedExerciseID == option.exerciseID {
                            Image(systemName: "checkmark")
                                .foregroundStyle(DSColor.coralEnd)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
            .navigationTitle("Exercise")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { isExercisePickerPresented = false }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private var weightField: some View {
        VStack(alignment: .leading, spacing: DSSpacing.xs) {
            Text("Weight")
                .font(.caption.weight(.semibold))
                .foregroundStyle(DSColor.textSecondary)

            if isInteractive && !payload.isSaved {
                HStack(spacing: DSSpacing.sm) {
                    TextField("e.g. 40", text: $weightText)
                        .keyboardType(.decimalPad)
                        .textFieldStyle(.roundedBorder)
                        .onChange(of: weightText) { _, newValue in
                            payload.weightValue = GymSetCardValidation.parseWeight(newValue)
                            publishDraftChange()
                        }

                    Picker("Unit", selection: $payload.weightUnit) {
                        ForEach(GymSetCardValidation.supportedWeightUnits, id: \.self) { unit in
                            Text(unit).tag(unit)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 100)
                    .onChange(of: payload.weightUnit) { _, _ in
                        publishDraftChange()
                    }
                }
            } else {
                Text(GymSetCardFormatting.weightLabel(value: payload.weightValue, unit: payload.weightUnit))
                    .font(.body.weight(.semibold))
                    .foregroundStyle(DSColor.textPrimary)
            }
        }
    }

    private var repsField: some View {
        VStack(alignment: .leading, spacing: DSSpacing.xs) {
            Text("Repetitions")
                .font(.caption.weight(.semibold))
                .foregroundStyle(DSColor.textSecondary)

            if isInteractive && !payload.isSaved {
                TextField("e.g. 10", text: $repsText)
                    .keyboardType(.numberPad)
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: repsText) { _, newValue in
                        let digits = newValue.filter(\.isNumber)
                        if digits != newValue { repsText = digits }
                        payload.repetitions = Int(digits)
                        publishDraftChange()
                    }
            } else if let reps = payload.repetitions {
                Text("\(reps)")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(DSColor.textPrimary)
            } else {
                Text("—")
                    .font(.caption)
                    .foregroundStyle(DSColor.textSecondary)
            }
        }
    }

    private var aiContextSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let top = payload.interpretation.exerciseCandidates.first, !payload.selectedExerciseID.isEmpty {
                Text(GymSetCardFormatting.confidenceLabel(top.confidence))
                    .font(.caption2)
                    .foregroundStyle(DSColor.textSecondary)
            }
            if let detected = payload.interpretation.detectedWeight {
                Text("Detected weight: \(GymSetCardFormatting.weightLabel(value: detected.value, unit: detected.unit))")
                    .font(.caption2)
                    .foregroundStyle(DSColor.textSecondary)
            }
            if !payload.interpretation.limitations.isEmpty {
                Text(payload.interpretation.limitations.joined(separator: " "))
                    .font(.caption2)
                    .foregroundStyle(DSColor.textSecondary)
            }
        }
    }

    private var actionButtons: some View {
        VStack(spacing: DSSpacing.sm) {
            Button("Save Set") {
                onAction(.saveSet, payload)
            }
            .buttonStyle(CoralGradientButtonStyle())
            .disabled(!payload.canSaveSet)
            .opacity(payload.canSaveSet ? 1 : 0.5)

            HStack(spacing: DSSpacing.md) {
                Button("Retake Photo") {
                    onAction(.retakePhoto, payload)
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(DSColor.coralEnd)
                .buttonStyle(.plain)

                Button("Cancel") {
                    onAction(.cancelSet, payload)
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(DSColor.textSecondary)
                .buttonStyle(.plain)
            }
        }
        .padding(.top, DSSpacing.xs)
    }

    private func publishDraftChange() {
        onDraftChange(payload)
    }
}
