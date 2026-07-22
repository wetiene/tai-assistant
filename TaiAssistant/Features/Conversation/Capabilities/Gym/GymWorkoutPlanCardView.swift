import SwiftUI

struct GymWorkoutPlanCardView: View {
    let payload: GymWorkoutPlanCardPayload
    var isInteractive: Bool
    var onTakePhoto: () -> Void
    var onFinishWorkout: () -> Void
    var onManagePlans: () -> Void

    var body: some View {
        PrimaryCard(cornerRadius: 20) {
            VStack(alignment: .leading, spacing: DSSpacing.sm) {
                HStack {
                    Text("Workout")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(DSColor.coralEnd)
                        .padding(.horizontal, DSSpacing.sm)
                        .padding(.vertical, 4)
                        .background(DSColor.warmSurface)
                        .clipShape(Capsule())
                    Spacer()
                    if !payload.isActive {
                        Label("Finished", systemImage: "checkmark.circle.fill")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(DSColor.coralEnd)
                    }
                }

                Text(payload.title)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(DSColor.textPrimary)

                Text("\(payload.workingSetsPerExercise) working sets · \(payload.repRangeLabel)")
                    .font(.caption)
                    .foregroundStyle(DSColor.textSecondary)

                Text(payload.coachingNote)
                    .font(.caption)
                    .foregroundStyle(DSColor.textSecondary)

                VStack(alignment: .leading, spacing: DSSpacing.xs) {
                    ForEach(payload.exercises) { exercise in
                        HStack(spacing: DSSpacing.sm) {
                            Image(systemName: exercise.isCurrent && payload.isActive ? "arrow.right.circle.fill" : "circle")
                                .foregroundStyle(exercise.isCurrent && payload.isActive ? DSColor.coralEnd : DSColor.textSecondary)
                                .font(.caption)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(exercise.displayName + (exercise.isOptional ? " (optional)" : ""))
                                    .font(.subheadline.weight(exercise.isCurrent ? .semibold : .regular))
                                    .foregroundStyle(DSColor.textPrimary)
                                Text("\(exercise.completedSets)/\(exercise.workingSets) sets")
                                    .font(.caption2)
                                    .foregroundStyle(DSColor.textSecondary)
                            }
                            Spacer()
                        }
                    }
                }
                .padding(.top, DSSpacing.xs)

                if isInteractive && payload.isActive {
                    VStack(spacing: DSSpacing.sm) {
                        Button(action: onTakePhoto) {
                            Label("Take photo of setup", systemImage: "camera.fill")
                                .font(.subheadline.weight(.semibold))
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(CoralGradientButtonStyle())

                        Button("Finish workout", action: onFinishWorkout)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(DSColor.textSecondary)
                            .buttonStyle(.plain)

                        Button("Gym Plans", action: onManagePlans)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(DSColor.coralEnd)
                            .buttonStyle(.plain)
                    }
                    .padding(.top, DSSpacing.sm)
                }
            }
        }
        .frame(maxWidth: 340, alignment: .leading)
    }
}
