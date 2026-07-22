import SwiftUI

struct GymPlanEditorView: View {
    @State private var draft: GymPlanDraft
    private let baselineDraft: GymPlanDraft
    let gymPlanRepository: GymPlanRepository
    let ownerID: String
    let isNewPlan: Bool
    var onSave: (GymPlanReference) -> Void
    var onDuplicate: (GymPlanReference) -> Void
    var onResetStarter: (GymProgramTemplateID) -> Void
    var onCancel: () -> Void

    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var isExercisePickerPresented = false
    @Environment(\.editMode) private var editMode

    init(
        draft: GymPlanDraft,
        gymPlanRepository: GymPlanRepository,
        ownerID: String,
        isNewPlan: Bool,
        onSave: @escaping (GymPlanReference) -> Void,
        onDuplicate: @escaping (GymPlanReference) -> Void,
        onResetStarter: @escaping (GymProgramTemplateID) -> Void,
        onCancel: @escaping () -> Void
    ) {
        _draft = State(initialValue: draft)
        baselineDraft = draft
        self.gymPlanRepository = gymPlanRepository
        self.ownerID = ownerID
        self.isNewPlan = isNewPlan
        self.onSave = onSave
        self.onDuplicate = onDuplicate
        self.onResetStarter = onResetStarter
        self.onCancel = onCancel
    }

    var body: some View {
        Form {
            Section("Plan") {
                TextField("Title", text: $draft.title)
            }

            Section("Prescription") {
                Stepper("Working sets: \(draft.prescription.workingSetsPerExercise)", value: $draft.prescription.workingSetsPerExercise, in: 1...6)
                Stepper("Rep range low: \(draft.prescription.repRangeLower)", value: $draft.prescription.repRangeLower, in: 1...30)
                Stepper("Rep range high: \(draft.prescription.repRangeUpper)", value: $draft.prescription.repRangeUpper, in: 1...30)
                TextField("Coaching note", text: $draft.prescription.coachingNote, axis: .vertical)
                    .lineLimit(2...4)
            }

            Section {
                if draft.exercises.isEmpty {
                    Text("Add at least one exercise.")
                        .foregroundStyle(DSColor.textSecondary)
                }
                ForEach(Array(draft.exercises.enumerated()), id: \.element.id) { index, exercise in
                    HStack(alignment: .top, spacing: DSSpacing.sm) {
                        Text("\(index + 1)")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(DSColor.textSecondary)
                            .frame(width: 22, alignment: .trailing)
                            .accessibilityHidden(true)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(exercise.displayName)
                                .foregroundStyle(DSColor.textPrimary)
                                .fixedSize(horizontal: false, vertical: true)
                            if exercise.isOptional {
                                Text("Optional")
                                    .font(.caption2)
                                    .foregroundStyle(DSColor.textSecondary)
                            }
                        }

                        Spacer(minLength: DSSpacing.sm)

                        if editMode?.wrappedValue != .active {
                            Toggle("Optional", isOn: binding(for: exercise))
                                .labelsHidden()
                        }
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("Exercise \(index + 1), \(exercise.displayName)")
                    .accessibilityHint(isReordering ? "Drag to reorder" : "Double tap to mark optional")
                }
                .onMove(perform: moveExercises)
                .onDelete(perform: removeExercises)

                Button {
                    isExercisePickerPresented = true
                } label: {
                    Label("Add exercise", systemImage: "plus.circle.fill")
                }
            } header: {
                Text("Exercises")
            } footer: {
                if !draft.exercises.isEmpty {
                    Text("Tap Reorder to drag exercises into your preferred sequence.")
                        .font(.caption)
                }
            }

            if let errorMessage {
                Section {
                    Text(errorMessage)
                        .foregroundStyle(DSColor.destructiveCoral)
                }
            }
        }
        .navigationTitle(isNewPlan ? "New Plan" : "Edit Plan")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel", action: onCancel)
            }
            ToolbarItem(placement: .confirmationAction) {
                Button(isSaving ? "Saving…" : "Save") {
                    Task { await save() }
                }
                .disabled(isSaving || !canSave)
            }
            ToolbarItem(placement: .topBarTrailing) {
                if !draft.exercises.isEmpty {
                    EditButton()
                        .accessibilityLabel(isReordering ? "Done reordering" : "Reorder exercises")
                }
            }
            ToolbarItem(placement: .bottomBar) {
                HStack {
                    if let reference = draft.reference {
                        Button("Duplicate") {
                            onDuplicate(reference)
                        }
                    }
                    if case .starter(let templateID)? = draft.reference {
                        Button("Reset starter") {
                            onResetStarter(templateID)
                        }
                    }
                    Spacer()
                }
            }
        }
        .sheet(isPresented: $isExercisePickerPresented) {
            exercisePicker
        }
    }

    private var isReordering: Bool {
        editMode?.wrappedValue == .active
    }

    private var canSave: Bool {
        !draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !draft.exercises.isEmpty
            && draft != baselineDraft
    }

    private var exercisePicker: some View {
        NavigationStack {
            List(GymExerciseID.allCases, id: \.self) { exerciseID in
                Button {
                    addExercise(exerciseID)
                    isExercisePickerPresented = false
                } label: {
                    Text(exerciseID.displayName)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .buttonStyle(.plain)
                .disabled(draft.exercises.contains { $0.reference.catalogID == exerciseID })
            }
            .navigationTitle("Add Exercise")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { isExercisePickerPresented = false }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func binding(for exercise: GymPlannedExercise) -> Binding<Bool> {
        Binding(
            get: {
                draft.exercises.first(where: { $0.id == exercise.id })?.isOptional ?? false
            },
            set: { isOptional in
                guard let sectionIndex = draft.sections.indices.first else { return }
                guard let index = draft.sections[sectionIndex].exercises.firstIndex(where: { $0.id == exercise.id }) else { return }
                var updated = draft.sections[sectionIndex].exercises[index]
                updated.isOptional = isOptional
                draft.sections[sectionIndex].exercises[index] = updated
            }
        )
    }

    private func addExercise(_ exerciseID: GymExerciseID) {
        draft.appendExercise(exerciseID)
    }

    private func removeExercises(at offsets: IndexSet) {
        draft.removeExercises(at: offsets)
    }

    private func moveExercises(from source: IndexSet, to destination: Int) {
        draft.moveExercises(from: source, to: destination)
    }

    private func save() async {
        guard canSave else { return }
        isSaving = true
        defer { isSaving = false }
        do {
            if draft.prescription.repRangeUpper < draft.prescription.repRangeLower {
                draft.prescription.repRangeUpper = draft.prescription.repRangeLower
            }
            let reference = try await gymPlanRepository.saveDraft(draft, ownerID: ownerID)
            onSave(reference)
        } catch {
            errorMessage = "Couldn’t save this plan."
        }
    }
}
