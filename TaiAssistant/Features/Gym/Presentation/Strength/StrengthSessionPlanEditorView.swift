import SwiftUI

/// Session-scoped plan editor. Changes apply to today's workout only — not the underlying program.
struct StrengthSessionPlanEditorView: View {
    @Binding var plan: GymResolvablePlan
    var onDone: () -> Void
    var onCancel: () -> Void

    var body: some View {
        List {
            Section {
                Text("Edits apply to this workout only. Your saved program is unchanged.")
                    .font(.caption)
                    .foregroundStyle(DSColor.textSecondary)
            }

            Section("Today's exercises") {
                ForEach(sortedExercises, id: \.id) { exercise in
                    Text(exercise.displayName)
                        .font(.body)
                }
                .onDelete(perform: deleteExercises)
            }
        }
        .navigationTitle("Edit Today's Plan")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel", action: onCancel)
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Done", action: onDone)
                    .fontWeight(.semibold)
            }
        }
    }

    private var sortedExercises: [GymPlannedExercise] {
        plan.exercises.sorted { $0.orderIndex < $1.orderIndex }
    }

    private func deleteExercises(at offsets: IndexSet) {
        var exercises = sortedExercises
        exercises.remove(atOffsets: offsets)
        for index in exercises.indices {
            exercises[index].orderIndex = index
        }
        plan.exercises = exercises
    }
}
