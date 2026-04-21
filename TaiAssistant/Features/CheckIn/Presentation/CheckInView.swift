import SwiftUI
import UIKit

struct CheckInView: View {
    let mealRepository: MealRepository
    let ownerID: String
    let interpreter: any CheckInInterpreting

    @State private var session = CheckInSessionDraft()
    @State private var isCameraPresented = false
    @State private var isInterpreting = false
    @State private var isSaving = false
    @State private var saveMessage: String?
    @State private var errorMessage: String?
    @FocusState private var isComposerFocused: Bool

    private let shortcuts = [
        "Usual breakfast",
        "Protein shake",
        "Yesterday lunch",
        "Family dinner"
    ]

    init(
        mealRepository: MealRepository,
        ownerID: String,
        interpreter: any CheckInInterpreting = MockCheckInInterpreter()
    ) {
        self.mealRepository = mealRepository
        self.ownerID = ownerID
        self.interpreter = interpreter
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DSSpacing.xl) {
                Text("Tell Tai what happened")
                    .font(.title.weight(.bold))
                    .foregroundStyle(DSColor.textPrimary)

                composerCard
                shortcutsSection
                interpretedMealsSection
            }
            .padding(.horizontal, DSSpacing.lg)
            .padding(.top, DSSpacing.lg)
            .padding(.bottom, 120)
        }
        .scrollDismissesKeyboard(.interactively)
        .onTapGesture {
            isComposerFocused = false
        }
        .background(DSColor.background.ignoresSafeArea())
        .navigationTitle("Check In")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            bottomConfirmBar
        }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button {
                    isComposerFocused = false
                } label: {
                    Label("Done", systemImage: "keyboard.chevron.compact.down")
                        .font(.subheadline.weight(.semibold))
                }
            }
        }
        .fullScreenCover(isPresented: $isCameraPresented) {
            CheckInCameraView { image in
                handleCapturedImage(image)
                isCameraPresented = false
            }
        }
        .alert("Check In", isPresented: Binding(
            get: { errorMessage != nil || saveMessage != nil },
            set: { isPresented in
                if !isPresented {
                    errorMessage = nil
                    saveMessage = nil
                }
            }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? saveMessage ?? "")
        }
        .overlay {
            if isInterpreting || isSaving {
                ProgressView(isSaving ? "Saving meals..." : "Interpreting check in...")
                    .padding(DSSpacing.lg)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
        }
        .onAppear {
            print("USING CHECKINVIEW")
        }
    }

    @ViewBuilder
    private var bottomConfirmBar: some View {
        if !session.interpretedMeals.isEmpty {
            Button(action: saveInterpretedMeals) {
                bottomConfirmButtonLabel
            }
            .buttonStyle(CoralGradientButtonStyle())
            .padding(.horizontal, DSSpacing.lg)
            .background(.ultraThinMaterial)
            .padding(.top, DSSpacing.sm)
            .padding(.bottom, 120)
        }
    }

    @ViewBuilder
    private var bottomConfirmButtonLabel: some View {
        if isSaving {
            ProgressView()
                .tint(.white)
        } else {
            Label(session.confirmTitle, systemImage: "checkmark.circle.fill")
        }
    }

    private var composerCard: some View {
        PrimaryCard(cornerRadius: 24) {
            TextEditor(text: $session.userInput)
                .frame(minHeight: 154)
                .focused($isComposerFocused)
                .scrollContentBackground(.hidden)
                .padding(DSSpacing.sm)
                .background(Color.white.opacity(0.7))
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(DSColor.coralStart.opacity(0.24), lineWidth: 1)
                )

            HStack(spacing: DSSpacing.sm) {
                Button {
                    isCameraPresented = true
                } label: {
                    Label(session.selectedPhotoData == nil ? "Take Photo" : "Retake Photo", systemImage: "camera.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(DSColor.coralEnd)
                        .padding(.horizontal, DSSpacing.md)
                        .padding(.vertical, DSSpacing.sm)
                        .background(DSColor.warmSurface)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)

                Spacer()

                Button {
                    Task {
                        await inferMeals()
                    }
                } label: {
                    Label("Check In", systemImage: "sparkles")
                }
                .buttonStyle(CoralGradientButtonStyle(isCompact: true))
                .disabled(session.userInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && session.selectedPhotoData == nil)
            }
        }
    }

    private var shortcutsSection: some View {
        VStack(alignment: .leading, spacing: DSSpacing.sm) {
            Text("Quick shortcuts")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(DSColor.textSecondary)
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: DSSpacing.sm) {
                ForEach(shortcuts, id: \.self) { shortcut in
                    Button {
                        session.userInput = shortcut
                    } label: {
                        Text(shortcut)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(DSColor.textPrimary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(DSSpacing.md)
                            .background(DSColor.surface)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var interpretedMealsSection: some View {
        VStack(alignment: .leading, spacing: DSSpacing.md) {
            if !session.interpretedMeals.isEmpty {
                Text("Inferred meals")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(DSColor.textPrimary)
            }
            ForEach($session.interpretedMeals) { $meal in
                CheckInMealCard(draft: $meal)
            }
        }
    }

    private func inferMeals() async {
        guard !isInterpreting else { return }
        isInterpreting = true
        defer { isInterpreting = false }
        do {
            let interpretation = try await interpreter.interpret(
                input: session.userInput,
                photoData: session.selectedPhotoData
            )
            session.interpretedMeals = interpretation.meals
            session.interpretationNotes = interpretation.uiNotes
        } catch {
            errorMessage = "Could not interpret this check in. Please try again."
        }
    }

    private func handleCapturedImage(_ image: UIImage) {
        guard let data = image.jpegData(compressionQuality: 0.85) else {
            errorMessage = "Could not process this photo. Please try again."
            return
        }
        session.selectedPhotoData = data
    }

    private func saveInterpretedMeals() {
        guard !isSaving else { return }
        Task {
            isSaving = true
            defer { isSaving = false }
            do {
                for draft in session.interpretedMeals {
                    let mealLog = MealLog(
                        ownerID: ownerID,
                        eatenAt: draft.eatenAt,
                        timing: draft.timing,
                        notes: draft.label
                    )
                    mealLog.items = draft.items.map { item in
                        MealItem(
                            name: item.name,
                            amount: item.amount,
                            unit: item.unit,
                            calories: item.calories,
                            proteinGrams: item.proteinGrams,
                            carbsGrams: item.carbsGrams,
                            fatGrams: item.fatGrams,
                            fiberGrams: item.fiberGrams
                        )
                    }
                    try await mealRepository.createMealLog(mealLog)
                }
                saveMessage = "Saved \(session.interpretedMeals.count) meal\(session.interpretedMeals.count == 1 ? "" : "s")."
                session = CheckInSessionDraft()
            } catch {
                errorMessage = "Could not save check in meals. Please retry."
            }
        }
    }
}

private struct CheckInMealCard: View {
    @Binding var draft: CheckInMealDraft

    var body: some View {
        PrimaryCard(cornerRadius: 20) {
            HStack {
                TimingChip(timing: $draft.timing)
                Spacer()
                DatePicker("", selection: $draft.eatenAt, displayedComponents: .hourAndMinute)
                    .labelsHidden()
                    .font(.caption)
            }

            TextField("Meal label", text: $draft.label)
                .font(.headline.weight(.semibold))
                .textFieldStyle(.roundedBorder)

            HStack(spacing: DSSpacing.sm) {
                StatPill(title: "kcal", value: "\(draft.calories)")
                StatPill(title: "P", value: "\(draft.proteinGrams)g")
                StatPill(title: "C", value: "\(draft.carbsGrams)g")
                StatPill(title: "F", value: "\(draft.fatGrams)g")
            }
        }
    }
}

private struct TimingChip: View {
    @Binding var timing: MealTiming

    var body: some View {
        Menu {
            ForEach(MealTiming.allCases, id: \.self) { option in
                Button(option.rawValue.capitalized) {
                    timing = option
                }
            }
        } label: {
            Label(timing.rawValue.capitalized, systemImage: "clock")
                .font(.caption.weight(.semibold))
                .foregroundStyle(DSColor.coralEnd)
                .padding(.horizontal, DSSpacing.sm + 2)
                .padding(.vertical, DSSpacing.xs + 2)
                .background(DSColor.warmSurface)
                .clipShape(Capsule())
        }
    }
}

private struct StatPill: View {
    let title: String
    let value: String

    var body: some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.caption.weight(.semibold))
                .foregroundStyle(DSColor.textPrimary)
            Text(title)
                .font(.caption2)
                .foregroundStyle(DSColor.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, DSSpacing.sm)
        .background(DSColor.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}
