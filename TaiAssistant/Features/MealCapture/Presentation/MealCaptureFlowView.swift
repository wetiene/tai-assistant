import PhotosUI
import SwiftUI
import UIKit

struct MealCaptureFlowView: View {
    let mealRepository: MealRepository
    let ownerID: String
    let estimator: MealEstimating
    let onSaved: () -> Void
    let dismiss: () -> Void

    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var selectedImage: UIImage?
    @State private var draft: MealCaptureDraft?
    @State private var correctionInput = ""
    @State private var isCameraPresented = false
    @State private var isEstimating = false
    @State private var isSaving = false
    @State private var errorMessage: String?

    init(
        mealRepository: MealRepository,
        ownerID: String,
        estimator: MealEstimating = MockMealEstimator(),
        onSaved: @escaping () -> Void,
        dismiss: @escaping () -> Void
    ) {
        self.mealRepository = mealRepository
        self.ownerID = ownerID
        self.estimator = estimator
        self.onSaved = onSaved
        self.dismiss = dismiss
    }

    var body: some View {
        NavigationStack {
            Group {
                if draft == nil {
                    captureView
                } else {
                    refinementView
                }
            }
            .background(DSColor.background.ignoresSafeArea())
            .navigationTitle(draft == nil ? "Log Meal" : "Fine Tune Meal")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close", action: dismiss)
                }
            }
            .sheet(isPresented: $isCameraPresented) {
                CameraImagePicker { image in
                    handleCapturedImage(image)
                }
                .ignoresSafeArea()
            }
            .onChange(of: selectedPhotoItem) { _, newItem in
                guard let newItem else { return }
                Task {
                    await handleSelectedPhotoItem(newItem)
                }
            }
            .alert("Meal Capture", isPresented: Binding(
                get: { errorMessage != nil },
                set: { isPresented in
                    if !isPresented { errorMessage = nil }
                }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
            .overlay {
                if isEstimating || isSaving {
                    ProgressView(isSaving ? "Saving meal..." : "Estimating meal...")
                        .padding(DSSpacing.lg)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
            }
        }
    }

    private var captureView: some View {
        VStack(spacing: DSSpacing.lg) {
            Spacer()

            PrimaryCard(cornerRadius: 24) {
                Label("Photo-based meal logging", systemImage: "camera.fill")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(DSColor.textPrimary)
                Text("Capture or pick a meal photo. Tai creates a fast estimate, then you fine tune and save.")
                    .font(.subheadline)
                    .foregroundStyle(DSColor.textSecondary)
            }

            Button {
                if UIImagePickerController.isSourceTypeAvailable(.camera) {
                    isCameraPresented = true
                } else {
                    errorMessage = "Camera is unavailable on this device."
                }
            } label: {
                Label("Take Photo", systemImage: "camera")
            }
            .buttonStyle(CoralGradientButtonStyle())

            PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                Label("Choose from Library", systemImage: "photo.on.rectangle")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(DSColor.textPrimary)
                    .padding(.horizontal, DSSpacing.xl)
                    .padding(.vertical, DSSpacing.md)
                    .frame(maxWidth: .infinity)
                    .background(DSColor.surface)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(Color.white.opacity(0.45), lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)

            Spacer()
        }
        .padding(DSSpacing.lg)
    }

    private var refinementView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DSSpacing.lg) {
                if let image = selectedImage {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(height: 180)
                        .frame(maxWidth: .infinity)
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                }

                PrimaryCard(cornerRadius: 20) {
                    TextField("Meal title", text: binding(for: \.mealTitle, default: "Meal"))
                        .font(.headline.weight(.semibold))
                    Picker("Meal timing", selection: binding(for: \.timing, default: .other)) {
                        ForEach(MealTiming.allCases, id: \.self) { timing in
                            Text(timing.rawValue.capitalized).tag(timing)
                        }
                    }
                    DatePicker("Eaten at", selection: binding(for: \.eatenAt, default: .now), displayedComponents: [.date, .hourAndMinute])
                }

                DashboardCard(title: "Estimated Nutrition", icon: "sparkles", tint: .orange) {
                    HStack(spacing: DSSpacing.md) {
                        MacroChip(label: "Calories", value: "\(binding(for: \.totalCalories, default: 0).wrappedValue)")
                        MacroChip(label: "Protein", value: "\(Int(binding(for: \.totalProteinGrams, default: 0).wrappedValue.rounded()))g")
                        MacroChip(label: "Carbs", value: "\(Int(binding(for: \.totalCarbsGrams, default: 0).wrappedValue.rounded()))g")
                        MacroChip(label: "Fat", value: "\(Int(binding(for: \.totalFatGrams, default: 0).wrappedValue.rounded()))g")
                    }
                }

                PrimaryCard(cornerRadius: 20) {
                    Text("Natural language correction")
                        .font(.subheadline.weight(.semibold))
                    TextField("Example: swap rice for quinoa", text: $correctionInput)
                        .textFieldStyle(.roundedBorder)
                    Button("Apply correction") {
                        applyNaturalLanguageCorrection()
                    }
                    .buttonStyle(CoralGradientButtonStyle(isCompact: true))
                }

                PrimaryCard(cornerRadius: 20) {
                    HStack {
                        Text("Manual nutrition override")
                            .font(.subheadline.weight(.semibold))
                        Spacer()
                    }
                    ManualIntRow(title: "Calories", value: binding(for: \.totalCalories, default: 0))
                    ManualDoubleRow(title: "Protein (g)", value: binding(for: \.totalProteinGrams, default: 0))
                    ManualDoubleRow(title: "Carbs (g)", value: binding(for: \.totalCarbsGrams, default: 0))
                    ManualDoubleRow(title: "Fat (g)", value: binding(for: \.totalFatGrams, default: 0))
                }

                PrimaryCard(cornerRadius: 20) {
                    HStack {
                        Text("Detected items")
                            .font(.subheadline.weight(.semibold))
                        Spacer()
                        Button {
                            addItemRow()
                        } label: {
                            Label("Add", systemImage: "plus")
                        }
                        .buttonStyle(.bordered)
                    }

                    ForEach(itemIDs, id: \.self) { itemID in
                        MealItemEditorRow(
                            name: itemBinding(itemID: itemID, keyPath: \.name, default: ""),
                            grams: itemBinding(itemID: itemID, keyPath: \.amount, default: 0),
                            calories: itemBinding(itemID: itemID, keyPath: \.calories, default: 0),
                            protein: itemBinding(itemID: itemID, keyPath: \.proteinGrams, default: 0),
                            carbs: itemBinding(itemID: itemID, keyPath: \.carbsGrams, default: 0),
                            fat: itemBinding(itemID: itemID, keyPath: \.fatGrams, default: 0),
                            moveUp: { moveItemUp(itemID) },
                            moveDown: { moveItemDown(itemID) },
                            remove: { removeItem(itemID) }
                        )
                    }
                }

                Button {
                    Task {
                        await saveMeal()
                    }
                } label: {
                    Label("Save Meal", systemImage: "checkmark.circle.fill")
                }
                .buttonStyle(CoralGradientButtonStyle())
                .disabled(isSaving || draft == nil)
            }
            .padding(DSSpacing.lg)
        }
    }

    private var itemIDs: [UUID] {
        draft?.detectedItems.map(\.id) ?? []
    }

    private func binding<T>(for keyPath: WritableKeyPath<MealCaptureDraft, T>, default defaultValue: T) -> Binding<T> {
        Binding(
            get: { draft?[keyPath: keyPath] ?? defaultValue },
            set: { newValue in
                guard draft != nil else { return }
                draft?[keyPath: keyPath] = newValue
            }
        )
    }

    private func itemBinding<T>(
        itemID: UUID,
        keyPath: WritableKeyPath<MealCaptureItemDraft, T>,
        default defaultValue: T
    ) -> Binding<T> {
        Binding(
            get: {
                guard
                    let draft,
                    let index = draft.detectedItems.firstIndex(where: { $0.id == itemID })
                else { return defaultValue }
                return draft.detectedItems[index][keyPath: keyPath]
            },
            set: { newValue in
                guard
                    let index = draft?.detectedItems.firstIndex(where: { $0.id == itemID })
                else { return }
                draft?.detectedItems[index][keyPath: keyPath] = newValue
                draft?.recalculateTotalsFromItems()
            }
        )
    }

    private func handleCapturedImage(_ image: UIImage) {
        selectedImage = image
        guard let imageData = image.jpegData(compressionQuality: 0.85) else {
            errorMessage = "Could not process this photo. Please try again."
            return
        }
        Task {
            await estimateMeal(using: imageData)
        }
    }

    private func handleSelectedPhotoItem(_ photoItem: PhotosPickerItem) async {
        do {
            guard let data = try await photoItem.loadTransferable(type: Data.self),
                  let image = UIImage(data: data) else {
                errorMessage = "Could not load that image. Please try another photo."
                return
            }
            selectedImage = image
            await estimateMeal(using: data)
        } catch {
            errorMessage = "Image selection failed. Please retry."
        }
    }

    private func estimateMeal(using imageData: Data) async {
        guard !isEstimating else { return }
        isEstimating = true
        defer { isEstimating = false }
        do {
            draft = try await estimator.estimateMeal(from: imageData)
            correctionInput = ""
        } catch {
            errorMessage = "Meal estimation failed. Try another photo."
        }
    }

    private func applyNaturalLanguageCorrection() {
        guard let currentDraft = draft else { return }
        draft = MealCaptureDraftCorrectionEngine.apply(correctionInput, to: currentDraft)
        correctionInput = ""
    }

    private func addItemRow() {
        guard draft != nil else { return }
        draft?.detectedItems.append(
            MealCaptureItemDraft(
                name: "New item",
                amount: 50,
                unit: "g",
                calories: 80,
                proteinGrams: 5,
                carbsGrams: 6,
                fatGrams: 2,
                fiberGrams: 1
            )
        )
        draft?.recalculateTotalsFromItems()
    }

    private func removeItem(_ itemID: UUID) {
        draft?.detectedItems.removeAll { $0.id == itemID }
        draft?.recalculateTotalsFromItems()
    }

    private func moveItemUp(_ itemID: UUID) {
        draft?.moveItemUp(id: itemID)
    }

    private func moveItemDown(_ itemID: UUID) {
        draft?.moveItemDown(id: itemID)
    }

    private func saveMeal() async {
        guard let draft, !isSaving else { return }
        isSaving = true
        defer { isSaving = false }

        let noteLines = [draft.mealTitle, draft.correctionPrompt]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let mealNotes = noteLines.joined(separator: " • ")

        let mealLog = MealLog(
            ownerID: ownerID,
            eatenAt: draft.eatenAt,
            timing: draft.timing,
            notes: mealNotes
        )
        mealLog.items = draft.detectedItems.map { item in
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

        do {
            try await mealRepository.createMealLog(mealLog)
            selectedImage = nil
            selectedPhotoItem = nil
            self.draft = nil
            correctionInput = ""
            onSaved()
            dismiss()
        } catch {
            errorMessage = "Could not save meal. Please retry."
        }
    }
}

private struct MacroChip: View {
    let label: String
    let value: String

    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.subheadline.monospacedDigit().weight(.semibold))
                .foregroundStyle(DSColor.textPrimary)
            Text(label)
                .font(.caption)
                .foregroundStyle(DSColor.textSecondary)
        }
        .padding(.vertical, DSSpacing.sm)
        .padding(.horizontal, DSSpacing.sm)
        .frame(maxWidth: .infinity)
        .background(DSColor.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private struct ManualDoubleRow: View {
    let title: String
    @Binding var value: Double

    var body: some View {
        HStack {
            Text(title)
                .font(.subheadline.weight(.medium))
            Spacer()
            TextField(title, value: $value, format: .number)
                .textFieldStyle(.roundedBorder)
                .keyboardType(.decimalPad)
                .frame(width: 120)
        }
    }
}

private struct ManualIntRow: View {
    let title: String
    @Binding var value: Int

    var body: some View {
        HStack {
            Text(title)
                .font(.subheadline.weight(.medium))
            Spacer()
            TextField(title, value: $value, format: .number)
                .textFieldStyle(.roundedBorder)
                .keyboardType(.numberPad)
                .frame(width: 120)
        }
    }
}

private struct MealItemEditorRow: View {
    @Binding var name: String
    @Binding var grams: Double
    @Binding var calories: Int
    @Binding var protein: Double
    @Binding var carbs: Double
    @Binding var fat: Double
    let moveUp: () -> Void
    let moveDown: () -> Void
    let remove: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: DSSpacing.sm) {
            HStack {
                TextField("Item name", text: $name)
                    .textFieldStyle(.roundedBorder)
                Button(action: moveUp) {
                    Image(systemName: "arrow.up")
                }
                .buttonStyle(.bordered)
                Button(action: moveDown) {
                    Image(systemName: "arrow.down")
                }
                .buttonStyle(.bordered)
                Button(role: .destructive, action: remove) {
                    Image(systemName: "trash")
                }
                .buttonStyle(.bordered)
            }

            HStack {
                TextField("g", value: $grams, format: .number)
                    .textFieldStyle(.roundedBorder)
                    .keyboardType(.decimalPad)
                TextField("kcal", value: $calories, format: .number)
                    .textFieldStyle(.roundedBorder)
                    .keyboardType(.numberPad)
                TextField("P", value: $protein, format: .number)
                    .textFieldStyle(.roundedBorder)
                    .keyboardType(.decimalPad)
                TextField("C", value: $carbs, format: .number)
                    .textFieldStyle(.roundedBorder)
                    .keyboardType(.decimalPad)
                TextField("F", value: $fat, format: .number)
                    .textFieldStyle(.roundedBorder)
                    .keyboardType(.decimalPad)
            }
        }
        .padding(DSSpacing.sm)
        .background(DSColor.background)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private struct CameraImagePicker: UIViewControllerRepresentable {
    let onImagePicked: (UIImage) -> Void

    final class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        let parent: CameraImagePicker

        init(parent: CameraImagePicker) {
            self.parent = parent
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            picker.dismiss(animated: true)
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            if let image = info[.originalImage] as? UIImage {
                parent.onImagePicked(image)
            }
            picker.dismiss(animated: true)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.delegate = context.coordinator
        if UIImagePickerController.isSourceTypeAvailable(.camera) {
            picker.sourceType = .camera
            picker.cameraCaptureMode = .photo
        } else {
            picker.sourceType = .photoLibrary
        }
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}
}
