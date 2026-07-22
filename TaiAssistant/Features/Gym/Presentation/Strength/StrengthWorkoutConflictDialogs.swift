import SwiftUI

/// Shell-level workout start conflict presentation.
struct StrengthWorkoutConflictDialogs: ViewModifier {
    @Bindable var router: StrengthWorkoutEntryRouter

    func body(content: Content) -> some View {
        content
            .confirmationDialog(
                "Workout in progress",
                isPresented: $router.isConflictDialogPresented,
                titleVisibility: .visible
            ) {
                if let conflict = router.pendingConflict {
                    Button("Resume \(conflict.activeSessionTitle)") {
                        Task { await router.resolveConflict(.resumeCurrent) }
                    }
                    .disabled(router.isResolvingConflict)

                    Button("Finish \(conflict.activeSessionTitle) and Start \(conflict.requestedPlanTitle)") {
                        Task { await router.resolveConflict(.finishCurrentAndStartSelected) }
                    }
                    .disabled(router.isResolvingConflict)

                    Button("Abandon \(conflict.activeSessionTitle) and Start \(conflict.requestedPlanTitle)", role: .destructive) {
                        router.requestAbandonConfirmation()
                    }
                    .disabled(router.isResolvingConflict)

                    Button("Cancel", role: .cancel) {
                        router.cancelConflict()
                    }
                }
            } message: {
                if let conflict = router.pendingConflict {
                    Text(conflictMessage(conflict))
                }
            }
            .alert(
                "Abandon workout?",
                isPresented: $router.isAbandonConfirmationPresented
            ) {
                Button("Abandon and Start", role: .destructive) {
                    Task { await router.resolveConflict(.discardCurrentAndStartSelected) }
                }
                .disabled(router.isResolvingConflict)
                Button("Cancel", role: .cancel) {
                    router.cancelAbandonConfirmation()
                }
            } message: {
                if let conflict = router.pendingConflict {
                    Text("This will permanently discard your in-progress \(conflict.activeSessionTitle) workout and start \(conflict.requestedPlanTitle).")
                }
            }
    }

    private func conflictMessage(_ conflict: GymWorkoutStartConflict) -> String {
        var lines = [
            "You already have \(conflict.activeSessionTitle) in progress."
        ]
        if let progress = conflict.activeProgressSummary {
            lines.append("Progress: \(progress).")
        }
        lines.append("You tried to start \(conflict.requestedPlanTitle).")
        return lines.joined(separator: " ")
    }
}

extension View {
    func strengthWorkoutConflictDialogs(router: StrengthWorkoutEntryRouter) -> some View {
        modifier(StrengthWorkoutConflictDialogs(router: router))
    }
}
