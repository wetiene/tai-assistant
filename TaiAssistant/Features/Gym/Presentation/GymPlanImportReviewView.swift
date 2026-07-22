import SwiftUI

struct GymPlanImportReviewView: View {
    @State private var importDraft: GymPlanImportDraft
    @State private var pastedSourceText: String
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var showReplaceActiveConfirmation = false

    let gymPlanRepository: GymPlanRepository
    let ownerID: String
    let hasActivePlan: Bool
    var onSaved: () -> Void
    var onCancel: () -> Void
    var onReanalyse: (GymPlanImportSource) async throws -> GymPlanImportDraft

    init(
        importDraft: GymPlanImportDraft,
        sourceText: String? = nil,
        gymPlanRepository: GymPlanRepository,
        ownerID: String,
        hasActivePlan: Bool,
        onSaved: @escaping () -> Void,
        onCancel: @escaping () -> Void,
        onReanalyse: @escaping (GymPlanImportSource) async throws -> GymPlanImportDraft
    ) {
        _importDraft = State(initialValue: importDraft)
        _pastedSourceText = State(initialValue: sourceText ?? "")
        self.gymPlanRepository = gymPlanRepository
        self.ownerID = ownerID
        self.hasActivePlan = hasActivePlan
        self.onSaved = onSaved
        self.onCancel = onCancel
        self.onReanalyse = onReanalyse
    }

    var body: some View {
        Form {
            Section {
                Text("Nothing is added to your workout plans until you save.")
                    .font(.subheadline)
                    .foregroundStyle(DSColor.textSecondary)
            }

            Section("Plan") {
                TextField("Plan name", text: $importDraft.title)
                if importDraft.suggestedDurationWeeks != nil {
                    Stepper(
                        "Suggested duration: \(importDraft.suggestedDurationWeeks ?? 4) weeks",
                        value: Binding(
                            get: { importDraft.suggestedDurationWeeks ?? 4 },
                            set: { importDraft.suggestedDurationWeeks = $0 }
                        ),
                        in: 1...12
                    )
                }
            }

            if !importDraft.generalInstructions.isEmpty {
                Section("General instructions") {
                    ForEach(importDraft.generalInstructions.indices, id: \.self) { index in
                        Text(importDraft.generalInstructions[index])
                            .font(.subheadline)
                    }
                }
            }

            ForEach(importDraft.sections.indices, id: \.self) { sectionIndex in
                Section(importDraft.sections[sectionIndex].name) {
                    ForEach(importDraft.sections[sectionIndex].exercises.indices, id: \.self) { exerciseIndex in
                        exerciseReviewRow(sectionIndex: sectionIndex, exerciseIndex: exerciseIndex)
                    }
                }
            }

            if !importDraft.unresolvedItems.isEmpty {
                Section("Needs review") {
                    ForEach(importDraft.unresolvedItems) { item in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.sourceText)
                                .font(.subheadline.weight(.semibold))
                            Text(item.reason)
                                .font(.caption)
                                .foregroundStyle(DSColor.textSecondary)
                        }
                    }
                }
            }

            if importDraft.sourceType == .text {
                Section("Edit source") {
                    TextEditor(text: $pastedSourceText)
                        .frame(minHeight: 120)
                }
            }

            if let errorMessage {
                Section {
                    Text(errorMessage).foregroundStyle(DSColor.destructiveCoral)
                }
            }
        }
        .navigationTitle("Review Import")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel", action: onCancel)
            }
            ToolbarItemGroup(placement: .bottomBar) {
                Button("Re-analyse") {
                    Task { await reanalyse() }
                }
                Spacer()
                Button("Save Only") {
                    Task { await save(activation: .saveOnly) }
                }
                .disabled(isSaving)
                Button(isSaving ? "Saving…" : "Save & Activate") {
                    if hasActivePlan {
                        showReplaceActiveConfirmation = true
                    } else {
                        Task { await save(activation: .makeActive) }
                    }
                }
                .disabled(isSaving)
            }
        }
        .confirmationDialog(
            "Replace active plan?",
            isPresented: $showReplaceActiveConfirmation,
            titleVisibility: .visible
        ) {
            Button("Save new plan and make it active") {
                Task { await save(activation: .makeActive) }
            }
            Button("Save without activating") {
                Task { await save(activation: .saveOnly) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Your previous active plan will be archived. Workout history is kept.")
        }
    }

    @ViewBuilder
    private func exerciseReviewRow(sectionIndex: Int, exerciseIndex: Int) -> some View {
        let exercise = importDraft.sections[sectionIndex].exercises[exerciseIndex]
        VStack(alignment: .leading, spacing: DSSpacing.xs) {
            HStack {
                Text("\(exerciseIndex + 1).")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(DSColor.textSecondary)
                TextField("Exercise name", text: bindingDisplayName(sectionIndex: sectionIndex, exerciseIndex: exerciseIndex))
            }
            if let source = exercise.sourceName, source != exercise.displayName {
                Text("Trainer: \(source)")
                    .font(.caption2)
                    .foregroundStyle(DSColor.textSecondary)
            }
            HStack {
                if exercise.isUnresolved {
                    Label("Unresolved", systemImage: "questionmark.circle")
                        .font(.caption2)
                        .foregroundStyle(DSColor.coralEnd)
                } else if let confidence = exercise.matchConfidence {
                    Text("Match \(Int(confidence * 100))%")
                        .font(.caption2)
                        .foregroundStyle(DSColor.textSecondary)
                }
                Spacer()
                Toggle("Optional", isOn: bindingOptional(sectionIndex: sectionIndex, exerciseIndex: exerciseIndex))
                    .labelsHidden()
            }
            Stepper(
                "Sets: \(exercise.targetSets ?? 3)",
                value: bindingSets(sectionIndex: sectionIndex, exerciseIndex: exerciseIndex),
                in: 1...8
            )
            let repRange = exercise.effectiveRepRange(planPrescription: importDraft.sections[sectionIndex].prescription ?? .default)
            Text("\(repRange.lower)–\(repRange.upper) reps")
                .font(.caption)
                .foregroundStyle(DSColor.textSecondary)
            Menu(exercise.reference.catalogID?.displayName ?? "Custom exercise") {
                ForEach(GymExerciseID.allCases, id: \.self) { candidate in
                    Button(candidate.displayName) {
                        updateCatalogMatch(sectionIndex: sectionIndex, exerciseIndex: exerciseIndex, catalogID: candidate)
                    }
                }
                Button("Keep as custom") {
                    keepAsCustom(sectionIndex: sectionIndex, exerciseIndex: exerciseIndex)
                }
            }
            .font(.caption)
        }
        .padding(.vertical, 2)
    }

    private func bindingDisplayName(sectionIndex: Int, exerciseIndex: Int) -> Binding<String> {
        Binding(
            get: { importDraft.sections[sectionIndex].exercises[exerciseIndex].reference.customName },
            set: { newValue in
                importDraft.sections[sectionIndex].exercises[exerciseIndex].reference.customName = newValue
            }
        )
    }

    private func bindingOptional(sectionIndex: Int, exerciseIndex: Int) -> Binding<Bool> {
        Binding(
            get: { importDraft.sections[sectionIndex].exercises[exerciseIndex].isOptional },
            set: { importDraft.sections[sectionIndex].exercises[exerciseIndex].isOptional = $0 }
        )
    }

    private func bindingSets(sectionIndex: Int, exerciseIndex: Int) -> Binding<Int> {
        Binding(
            get: { importDraft.sections[sectionIndex].exercises[exerciseIndex].targetSets ?? 3 },
            set: { importDraft.sections[sectionIndex].exercises[exerciseIndex].targetSets = $0 }
        )
    }

    private func updateCatalogMatch(sectionIndex: Int, exerciseIndex: Int, catalogID: GymExerciseID) {
        importDraft.sections[sectionIndex].exercises[exerciseIndex].reference.catalogExerciseID = catalogID.rawValue
        importDraft.sections[sectionIndex].exercises[exerciseIndex].reference.customName = catalogID.displayName
        importDraft.sections[sectionIndex].exercises[exerciseIndex].isUnresolved = false
        importDraft.sections[sectionIndex].exercises[exerciseIndex].matchConfidence = 1
    }

    private func keepAsCustom(sectionIndex: Int, exerciseIndex: Int) {
        importDraft.sections[sectionIndex].exercises[exerciseIndex].reference.catalogExerciseID = nil
        importDraft.sections[sectionIndex].exercises[exerciseIndex].isUnresolved = false
    }

    private func reanalyse() async {
        guard importDraft.sourceType == .text else { return }
        do {
            importDraft = try await onReanalyse(.pastedText(pastedSourceText))
        } catch {
            errorMessage = "Couldn’t re-analyse this program."
        }
    }

    private func save(activation: GymPlanSaveActivation) async {
        isSaving = true
        defer { isSaving = false }
        var planDraft = importDraft.asPlanDraft()
        planDraft.importedAt = .now
        do {
            _ = try await gymPlanRepository.saveDraft(planDraft, ownerID: ownerID, activation: activation)
            onSaved()
        } catch {
            errorMessage = "Couldn’t save this plan."
        }
    }
}
