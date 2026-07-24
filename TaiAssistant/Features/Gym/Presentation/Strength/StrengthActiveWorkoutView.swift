import PhotosUI
import SwiftUI

struct StrengthActiveWorkoutView: View {
    @Bindable var controller: StrengthWorkoutController
    let photoAssist: StrengthGymPhotoAssistService
    var onCompleteWorkout: () -> Void
    var onLeave: () -> Void
    var onAbandon: () -> Void

    @State private var editWeight: Double = 0
    @State private var editReps: Int = 0
    @State private var showsAbandonConfirm = false
    @State private var showsCompletionReview = false
    @State private var editingSet: StrengthSetEditorContext?
    @State private var photoReview: StrengthPhotoAssistResult?
    @State private var showsPhotoConsent = false
    @State private var showsPhotoPicker = false
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var isInterpretingPhoto = false
    @State private var completedExerciseBannerID: UUID?
    @State private var showsExercisePicker = false
    @State private var hasShownLeaveHint = false

    var body: some View {
        Group {
            if let session = controller.session {
                activeContent(session)
            } else {
                ProgressView("Loading workout…")
            }
        }
        .background(DSColor.background.ignoresSafeArea())
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    Task {
                        try? await controller.persistActiveSession()
                        onLeave()
                    }
                } label: {
                    Image(systemName: "xmark")
                }
                .accessibilityLabel("Leave Workout")
                .accessibilityIdentifier("strength.active.leave")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button(sessionIsPaused ? "Resume" : "Pause") {
                        Task { await togglePause() }
                    }
                    Button("Abandon Workout", role: .destructive) {
                        showsAbandonConfirm = true
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button("Complete Workout") {
                    if controller.hasUnresolvedWork {
                        showsCompletionReview = true
                    } else {
                        Task { await completeWorkout() }
                    }
                }
                .font(.subheadline.weight(.semibold))
                .accessibilityIdentifier("strength.active.completeWorkout")
            }
        }
        .confirmationDialog(
            "Abandon this workout?",
            isPresented: $showsAbandonConfirm,
            titleVisibility: .visible
        ) {
            Button("Abandon Workout", role: .destructive, action: onAbandon)
            Button("Cancel", role: .cancel) {}
        }
        .sheet(item: $editingSet) { context in
            if let session = controller.session,
               let exercise = session.exercises.first(where: { $0.id == context.exerciseInstanceID }),
               let set = exercise.sets.first(where: { $0.id == context.setID })
            {
                StrengthSetEditorSheet(
                    exercise: exercise,
                    set: set,
                    onSave: { weight, reps in
                        Task {
                            try? await controller.editConfirmedSet(
                                exerciseInstanceID: context.exerciseInstanceID,
                                setID: context.setID,
                                weight: weight,
                                reps: reps
                            )
                        }
                    },
                    onMarkSkipped: {
                        Task {
                            try? await controller.markSetSkipped(
                                exerciseInstanceID: context.exerciseInstanceID,
                                setID: context.setID
                            )
                        }
                    },
                    onRestore: {
                        Task {
                            try? await controller.restoreSkippedSet(
                                exerciseInstanceID: context.exerciseInstanceID,
                                setID: context.setID
                            )
                        }
                    },
                    onDeleteExtra: set.isUserAdded ? {
                        Task {
                            try? await controller.deleteExtraSet(
                                exerciseInstanceID: context.exerciseInstanceID,
                                setID: context.setID
                            )
                        }
                    } : nil,
                    onCancel: {}
                )
            }
        }
        .sheet(item: $photoReview) { result in
            StrengthPhotoAssistReviewSheet(
                result: result,
                activeExerciseName: controller.session?.currentExerciseInstance?.displayName ?? "exercise",
                onApply: {
                    Task {
                        if let weight = result.suggestedWeight {
                            editWeight = weight
                        }
                        try? await controller.applySuggestedValuesToCurrentSet(
                            weight: result.suggestedWeight,
                            reps: nil
                        )
                        syncEditorsFromCurrentSet()
                    }
                },
                onSwitchExercise: switchExerciseFromPhoto(result),
                onCancel: {}
            )
        }
        .sheet(isPresented: $showsCompletionReview) {
            if let session = controller.session {
                StrengthWorkoutCompletionReviewSheet(
                    session: session,
                    onReturn: {},
                    onSkipRemainingAndComplete: {
                        Task {
                            do {
                                _ = try await controller.skipRemainingSetsAndComplete()
                                onCompleteWorkout()
                            } catch {
                                controller.reportError("Could not complete workout.")
                            }
                        }
                    },
                    onCancel: {}
                )
            }
        }
        .photosPicker(isPresented: $showsPhotoPicker, selection: $selectedPhotoItem, matching: .images)
        .sheet(isPresented: $showsPhotoConsent) {
            AIDataProcessingConsentSheet(
                kind: .gymPhoto,
                onAccept: {
                    showsPhotoConsent = false
                    showsPhotoPicker = true
                },
                onDecline: {
                    showsPhotoConsent = false
                }
            )
        }
        .onChange(of: selectedPhotoItem) { _, item in
            guard let item else { return }
            Task { await handlePhotoSelection(item) }
        }
        .onChange(of: controller.session?.currentSetID) { _, _ in
            syncEditorsFromCurrentSet()
            detectExerciseCompletion()
        }
        .onAppear {
            syncEditorsFromCurrentSet()
        }
        .alert("Workout error", isPresented: Binding(
            get: { controller.lastError != nil },
            set: { if !$0 { controller.clearError() } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(controller.lastError ?? "")
        }
    }

    private var sessionIsPaused: Bool {
        controller.session?.isPaused == true
    }

    @ViewBuilder
    private func activeContent(_ session: StrengthWorkoutSession) -> some View {
        VStack(spacing: 0) {
            workoutHeader(session)

            if let bannerID = completedExerciseBannerID,
               let exercise = session.exercises.first(where: { $0.id == bannerID })
            {
                StrengthExerciseCompleteBanner(
                    exerciseName: exercise.displayName,
                    onNextExercise: { Task { await selectNextPlannedExercise(from: session) } },
                    onChooseExercise: { showsExercisePicker = true },
                    onStay: { completedExerciseBannerID = nil }
                )
                .padding(.horizontal, DSSpacing.lg)
                .padding(.bottom, DSSpacing.sm)
            }

            if let exercise = session.currentExerciseInstance, let set = session.currentSet, set.status == .pending {
                setCard(session: session, exercise: exercise, set: set)
            } else if let exercise = session.currentExerciseInstance {
                completedExerciseSummary(exercise)
            }

            exerciseList(session)
        }
    }

    private func workoutHeader(_ session: StrengthWorkoutSession) -> some View {
        VStack(alignment: .leading, spacing: DSSpacing.xs) {
            Text(session.title)
                .font(.headline)
                .foregroundStyle(DSColor.textPrimary)
            HStack {
                Text(StrengthSetFormatting.formatWorkoutDuration(session.elapsedActiveSeconds))
                Text("·")
                Text("\(session.completedWorkingSetCount)/\(session.totalPlannedWorkingSets) sets")
            }
            .font(.caption)
            .foregroundStyle(DSColor.textSecondary)
            if !hasShownLeaveHint {
                Text("Your workout stays active when you leave.")
                    .font(.caption2)
                    .foregroundStyle(DSColor.textSecondary)
                    .onAppear { hasShownLeaveHint = true }
            }
            if session.isPaused {
                Label("Paused", systemImage: "pause.circle.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(DSColor.coralEnd)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(DSSpacing.lg)
    }

    @ViewBuilder
    private func setCard(
        session: StrengthWorkoutSession,
        exercise: StrengthExerciseInstance,
        set: StrengthSetRecord
    ) -> some View {
        VStack(spacing: DSSpacing.lg) {
            VStack(spacing: DSSpacing.xs) {
                Text(exercise.displayName)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(DSColor.textPrimary)
                Text("Set \(set.setNumber) of \(exercise.workingSets.count)")
                    .font(.subheadline)
                    .foregroundStyle(DSColor.textSecondary)
            }

            HStack(spacing: DSSpacing.xl) {
                if exercise.plannedExercise.tracksBodyweight {
                    VStack(spacing: DSSpacing.sm) {
                        Text("Weight")
                            .font(.caption)
                            .foregroundStyle(DSColor.textSecondary)
                        Text("Bodyweight")
                            .font(.title.weight(.bold))
                    }
                    .frame(maxWidth: .infinity)
                } else {
                    valueStepper(
                        title: "Weight",
                        value: $editWeight,
                        step: StrengthWeightIncrement.defaultIncrement(for: exercise.exerciseID),
                        format: { $0 > 0 ? "\($0.formattedStrengthWeight) \(set.weightUnit)" : "Weight not set" }
                    )
                }
                valueStepper(
                    title: "Reps",
                    value: Binding(
                        get: { Double(editReps) },
                        set: { editReps = Int($0) }
                    ),
                    step: 1,
                    format: { String(Int($0)) }
                )
            }

            Button {
                Task { await confirmSet() }
            } label: {
                Text("Confirm Set")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(CoralGradientButtonStyle())
            .controlSize(.large)
            .accessibilityIdentifier("strength.active.confirmSet")

            HStack(spacing: DSSpacing.md) {
                Button {
                    requestPhoto()
                } label: {
                    Label(isInterpretingPhoto ? "Reading…" : "Photo", systemImage: "camera")
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(DSColor.coralEnd)
                .buttonStyle(.plain)
                .disabled(isInterpretingPhoto)
                .accessibilityIdentifier("strength.active.photo")

                Button("Skip Set") {
                    Task { await skipSet() }
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(DSColor.textSecondary)
                .buttonStyle(.plain)

                Spacer()

                Button("Add Set") {
                    Task { try? await controller.addExtraSet(to: exercise.id) }
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(DSColor.coralEnd)
                .buttonStyle(.plain)
            }

            let repRange = exercise.plannedExercise.effectiveRepRange(planPrescription: session.prescription)
            Text("Target: \(repRange.lower)–\(repRange.upper) reps")
                .font(.caption)
                .foregroundStyle(DSColor.textSecondary)

            if let message = session.lastCoachingMessage {
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(DSColor.coralEnd)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(DSSpacing.md)
                    .background(DSColor.coralEnd.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
        .padding(DSSpacing.lg)
        .background(DSColor.surface)
    }

    private func completedExerciseSummary(_ exercise: StrengthExerciseInstance) -> some View {
        VStack(alignment: .leading, spacing: DSSpacing.sm) {
            Text(exercise.displayName)
                .font(.title3.weight(.bold))
            Text("All sets resolved for this exercise. Tap sets below to edit, or choose another exercise.")
                .font(.subheadline)
                .foregroundStyle(DSColor.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(DSSpacing.lg)
        .background(DSColor.surface)
    }

    private func exerciseList(_ session: StrengthWorkoutSession) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DSSpacing.md) {
                Text("Exercises")
                    .font(.headline)
                    .foregroundStyle(DSColor.textPrimary)
                ForEach(session.exercises) { exercise in
                    StrengthExerciseNavigatorCard(
                        exercise: exercise,
                        session: session,
                        isCurrent: exercise.id == session.currentExerciseInstanceID,
                        onSelectExercise: {
                            Task { try? await controller.selectExercise(exerciseInstanceID: exercise.id) }
                            completedExerciseBannerID = nil
                        },
                        onSelectSet: { setID in
                            Task {
                                if let set = exercise.sets.first(where: { $0.id == setID }),
                                   set.status == .confirmed || set.status == .skipped
                                {
                                    editingSet = StrengthSetEditorContext(
                                        exerciseInstanceID: exercise.id,
                                        setID: setID
                                    )
                                } else {
                                    try? await controller.selectSet(
                                        exerciseInstanceID: exercise.id,
                                        setID: setID
                                    )
                                    syncEditorsFromCurrentSet()
                                }
                            }
                        }
                    )
                }
            }
            .padding(DSSpacing.lg)
        }
    }

    private func valueStepper(
        title: String,
        value: Binding<Double>,
        step: Double,
        format: (Double) -> String
    ) -> some View {
        VStack(spacing: DSSpacing.sm) {
            Text(title)
                .font(.caption)
                .foregroundStyle(DSColor.textSecondary)
            Text(format(value.wrappedValue))
                .font(.title.weight(.bold))
                .foregroundStyle(DSColor.textPrimary)
            HStack(spacing: DSSpacing.lg) {
                Button { value.wrappedValue = max(0, value.wrappedValue - step) } label: {
                    Image(systemName: "minus.circle.fill").font(.title)
                }
                .buttonStyle(.plain)
                Button { value.wrappedValue += step } label: {
                    Image(systemName: "plus.circle.fill").font(.title)
                }
                .buttonStyle(.plain)
            }
            .foregroundStyle(DSColor.coralEnd)
        }
        .frame(maxWidth: .infinity)
    }

    private func syncEditorsFromCurrentSet() {
        guard let set = controller.session?.currentSet else { return }
        editWeight = set.suggestedWeight ?? set.confirmedWeight ?? 0
        editReps = set.suggestedReps ?? set.plannedReps ?? set.confirmedReps ?? 0
    }

    private func detectExerciseCompletion() {
        guard let session = controller.session,
              let exercise = session.currentExerciseInstance
        else { return }
        if exercise.workingSets.allSatisfy({ $0.status == .confirmed || $0.status == .skipped }) {
            completedExerciseBannerID = exercise.id
        }
    }

    private func selectNextPlannedExercise(from session: StrengthWorkoutSession) async {
        guard let currentIndex = session.exercises.firstIndex(where: { $0.id == session.currentExerciseInstanceID }) else { return }
        let remaining = session.exercises[(currentIndex + 1)...]
        if let next = remaining.first(where: { $0.status != .skipped && $0.status != .completed }) {
            try? await controller.selectExercise(exerciseInstanceID: next.id)
            completedExerciseBannerID = nil
        }
    }

    private func requestPhoto() {
        if AIDataProcessingConsentStore.hasAccepted(version: AIDataProcessingConsentStore.gymPhotoVersion) {
            showsPhotoPicker = true
        } else {
            showsPhotoConsent = true
        }
    }

    private func handlePhotoSelection(_ item: PhotosPickerItem) async {
        isInterpretingPhoto = true
        defer {
            isInterpretingPhoto = false
            selectedPhotoItem = nil
        }
        guard let session = controller.session,
              let data = try? await item.loadTransferable(type: Data.self)
        else {
            controller.reportError("Could not load that photo.")
            return
        }
        do {
            let result = try await photoAssist.interpretPhoto(jpeg: data, session: session)
            photoReview = result
        } catch {
            controller.reportError("Could not read that photo. Try another angle or enter the weight manually.")
        }
    }

    private func switchExerciseFromPhoto(_ result: StrengthPhotoAssistResult) -> (() -> Void)? {
        guard let detectedID = result.detectedExerciseID,
              let session = controller.session,
              let match = session.exercises.first(where: { $0.exerciseID == detectedID })
        else { return nil }
        return {
            Task {
                try? await controller.selectExercise(exerciseInstanceID: match.id)
                if let weight = result.suggestedWeight {
                    editWeight = weight
                    try? await controller.applySuggestedValuesToCurrentSet(weight: weight, reps: nil)
                    syncEditorsFromCurrentSet()
                }
            }
        }
    }

    private func confirmSet() async {
        do {
            try await controller.confirmCurrentSet(weight: editWeight, reps: editReps)
            syncEditorsFromCurrentSet()
        } catch {
            controller.reportError("Could not save set.")
        }
    }

    private func skipSet() async {
        do {
            try await controller.skipCurrentSet()
            syncEditorsFromCurrentSet()
            detectExerciseCompletion()
        } catch {
            controller.reportError("Could not skip set.")
        }
    }

    private func togglePause() async {
        if sessionIsPaused {
            try? await controller.resumeSession()
        } else {
            try? await controller.pauseSession()
        }
    }

    private func completeWorkout() async {
        do {
            _ = try await controller.finishWorkout()
            onCompleteWorkout()
        } catch {
            controller.reportError("Could not complete workout.")
        }
    }
}

extension StrengthPhotoAssistResult: Identifiable {
    var id: String {
        "\(detectedExerciseID ?? "none")-\(suggestedWeight ?? -1)"
    }
}
