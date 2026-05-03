import SwiftUI
import UIKit

struct CheckInView: View {
    @State private var viewModel: CheckInViewModel

    @State private var isCameraPresented = false
    @State private var isPhotoPreviewPresented = false
    @State private var isConfirmPressed = false
    @State private var isTaiNoteExpanded = false
    @FocusState private var isComposerFocused: Bool

    init(
        mealRepository: MealRepository,
        ownerID: String,
        interpreter: any CheckInInterpreting = MockCheckInInterpreter(),
        onMealsSaved: (() -> Void)? = nil
    ) {
        _viewModel = State(
            initialValue: CheckInViewModel(
                mealRepository: mealRepository,
                ownerID: ownerID,
                interpreter: interpreter,
                onMealsSaved: onMealsSaved
            )
        )
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DSSpacing.xl) {
                Text("Checkin with Tai")
                    .font(.title.weight(.bold))
                    .foregroundStyle(DSColor.textPrimary)

                contextSummarySection
                composerCard
                if !viewModel.session.interpretedMeals.isEmpty {
                    interpretedMealsSection
                }
                if !viewModel.session.interpretedMeals.isEmpty {
                    inlineConfirmSection
                }
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
        .sheet(isPresented: $isPhotoPreviewPresented) {
            selectedPhotoPreview
        }
        #if DEBUG
        .sheet(isPresented: Binding(
            get: { viewModel.aiInterpretFailureDebugText != nil },
            set: { isPresented in
                if !isPresented {
                    viewModel.aiInterpretFailureDebugText = nil
                }
            }
        )) {
            CheckInAIDebugErrorSheet(
                text: viewModel.aiInterpretFailureDebugText ?? "",
                onDismiss: { viewModel.aiInterpretFailureDebugText = nil }
            )
        }
        #endif
        .alert("Check In", isPresented: Binding(
            get: { viewModel.errorMessage != nil },
            set: { isPresented in
                if !isPresented {
                    viewModel.errorMessage = nil
                }
            }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
        .onAppear {
            Task {
                await viewModel.refreshDayProgress()
            }
        }
    }

    private var composerCard: some View {
        @Bindable var vm = viewModel
        return PrimaryCard(cornerRadius: 24) {
            ZStack(alignment: .bottomTrailing) {
                TextField("Add details or photo...", text: $vm.session.userInput, axis: .vertical)
                    .lineLimit(1...4)
                    .focused($isComposerFocused)
                    .padding(.leading, DSSpacing.sm)
                    .padding(.vertical, DSSpacing.sm)
                    .padding(.trailing, 56)

                Button {
                    Task {
                        isTaiNoteExpanded = false
                        await viewModel.onUpdateMealTapped()
                    }
                } label: {
                    Group {
                        if viewModel.isInterpreting {
                            ProgressView()
                                .tint(.white)
                        } else {
                            Image(systemName: "sparkles")
                                .font(.system(size: 15, weight: .semibold))
                        }
                    }
                    .foregroundStyle(.white)
                    .frame(width: 38, height: 38)
                    .background(
                        LinearGradient(
                            colors: [DSColor.coralStart, DSColor.coralEnd],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .clipShape(Circle())
                    .shadow(color: DSColor.coralEnd.opacity(0.28), radius: 10, x: 0, y: 5)
                }
                .buttonStyle(.plain)
                .padding(.trailing, DSSpacing.xs)
                .padding(.bottom, 4)
                .disabled(
                    viewModel.isInterpreting ||
                    (vm.session.userInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && vm.session.selectedPhotoData == nil && vm.session.interpretedMeals.isEmpty)
                )
            }
            .frame(minHeight: 46)
            .background(DSColor.surface)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(DSColor.coralStart.opacity(0.24), lineWidth: 1)
            )

            HStack(spacing: DSSpacing.sm) {
                Button {
                    isCameraPresented = true
                } label: {
                    Label(vm.session.selectedPhotoData == nil ? "Take Photo" : "Retake Photo", systemImage: "camera.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(DSColor.coralEnd)
                        .padding(.horizontal, DSSpacing.md)
                        .padding(.vertical, DSSpacing.sm)
                        .background(DSColor.warmSurface)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }

            selectedPhotoThumbnail
        }
    }

    @ViewBuilder
    private var selectedPhotoThumbnail: some View {
        if let photoData = viewModel.session.selectedPhotoData, let image = UIImage(data: photoData) {
            HStack(spacing: DSSpacing.sm) {
                ZStack(alignment: .topTrailing) {
                    Button {
                        isPhotoPreviewPresented = true
                    } label: {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 56, height: 56)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .stroke(DSColor.coralStart.opacity(0.28), lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)

                    Button(action: {
                        viewModel.session.selectedPhotoData = nil
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 18))
                            .foregroundColor(.white)
                            .background(Color.black.opacity(0.6))
                            .clipShape(Circle())
                    }
                    .frame(width: 24, height: 24)
                    .contentShape(Circle())
                    .offset(x: 8, y: -8)
                }

                Text("Photo attached")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(DSColor.textSecondary)

                Spacer()
            }
        }
    }

    @ViewBuilder
    private var selectedPhotoPreview: some View {
        if let photoData = viewModel.session.selectedPhotoData, let image = UIImage(data: photoData) {
            NavigationStack {
                ZStack {
                    Color.black.ignoresSafeArea()
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .padding(DSSpacing.lg)
                }
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Done") {
                            isPhotoPreviewPresented = false
                        }
                    }
                }
            }
        } else {
            Color.clear
                .presentationDetents([.medium])
        }
    }

    private var contextSummarySection: some View {
        let rows = viewModel.contextRows
        let contextSummaryMaxHeight: CGFloat = 100
        let rowHeight: CGFloat = 36
        let spacing = DSSpacing.xs
        
        return Group {
            if !rows.isEmpty {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: spacing) {
                            ForEach(rows) { row in
                                contextSummaryRow(row.text)
                                    .id(row.id)
                            }
                        }
                    }
                    .onAppear {
                        guard let lastID = rows.last?.id else { return }
                        proxy.scrollTo(lastID, anchor: .bottom)
                    }
                    .onChange(of: rows.count) { _, _ in
                        guard let lastID = rows.last?.id else { return }
                        withAnimation(.easeOut(duration: 0.18)) {
                            proxy.scrollTo(lastID, anchor: .bottom)
                        }
                    }
                }
                .frame(maxHeight: contextSummaryMaxHeight)
            }
        }
    }

    private func contextSummaryRow(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(DSColor.textSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, DSSpacing.sm)
            .padding(.vertical, DSSpacing.xs)
            .background(DSColor.surface)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var interpretedMealsSection: some View {
        @Bindable var vm = viewModel
        return VStack(alignment: .leading, spacing: DSSpacing.lg) {
            if !vm.session.interpretedMeals.isEmpty {
                Text("Inferred meals")
                    .font(.body.weight(.medium))
                    .foregroundStyle(DSColor.textPrimary)
            }
            ForEach($vm.session.interpretedMeals) { $meal in
                CheckInMealCard(draft: $meal, viewModel: viewModel)
            }
        }
    }

    private var understoodAsText: String {
        let meals = viewModel.session.interpretedMeals
        guard !meals.isEmpty else { return "your meal" }

        if meals.count == 1, let meal = meals.first {
            let cleanedItems = dedupedItemNames(from: meal.items)
            if cleanedItems.count <= 1 {
                return meal.label
            }
            return naturalJoin(cleanedItems.prefix(3).map { $0 })
        }

        let labels = meals.prefix(2).map(\.label)
        if meals.count > 2 {
            return "\(naturalJoin(labels)) + \(meals.count - 2) more"
        }
        return naturalJoin(labels)
    }

    private var taiNoteText: String {
        if let notes = viewModel.session.interpretationNotes?.trimmingCharacters(in: .whitespacesAndNewlines), !notes.isEmpty {
            return notes
        }

        let allItems = viewModel.session.interpretedMeals.flatMap(\.items)
        let itemNames = allItems.map { $0.name.lowercased() }
        let totalProtein = viewModel.session.interpretedMeals.reduce(0) { $0 + $1.proteinGrams }
        let totalCarbs = viewModel.session.interpretedMeals.reduce(0) { $0 + $1.carbsGrams }
        let totalCalories = viewModel.session.interpretedMeals.reduce(0) { $0 + $1.calories }

        let isOverCaloriesToday = viewModel.dayProgress.consumedCalories > viewModel.dayProgress.targetCalories
        let isLowProteinToday = viewModel.dayProgress.consumedProtein < viewModel.dayProgress.proteinTarget
        let isProteinPositiveMeal = totalProtein >= 25 || totalProtein >= totalCarbs
        let isHighCarbOrCalorieMeal = totalCarbs > totalProtein + 20 || totalCalories >= 600
        let isSuggestionInput = isSuggestionRequestInput

        let alcoholKeywords = ["wine", "beer", "whiskey", "vodka", "gin", "rum", "tequila", "champagne", "cider", "cocktail", "alcohol"]
        let hasAlcohol = itemNames.contains { name in
            alcoholKeywords.contains { name.contains($0) }
        }

        if isSuggestionInput {
            if isOverCaloriesToday && isLowProteinToday {
                return "For this option, choose a lighter high-protein choice since calories are tight."
            }
            if isOverCaloriesToday {
                return "For this option, keep calories lighter and prioritise protein."
            }
            return "For this option, keep it balanced with protein and fibre."
        }

        if isOverCaloriesToday && isLowProteinToday {
            return "You're over calories but still short on protein — choose a lighter, protein-focused option."
        }

        if hasAlcohol {
            return "Alcohol adds calories quickly — keep your next meal lighter and prioritise protein."
        }
        if isProteinPositiveMeal {
            if isOverCaloriesToday {
                return "Good protein choice — keep the next meal protein-rich and lighter on calories."
            }
            return "Good protein choice — keep your next meal protein-rich and balanced."
        }
        if isHighCarbOrCalorieMeal {
            if isOverCaloriesToday {
                return "Calories are tight today — keep your next meal lighter and protein-focused."
            }
            return "Carb-heavy — keep your next meal lighter on carbs and add protein."
        }
        return "Looks good — keep your next meal balanced with protein and fibre."
    }

    private var shouldShowTaiNoteExpansion: Bool {
        taiNoteText.count > 130
    }

    private var isSuggestionRequestInput: Bool {
        let input = viewModel.session.userInput.lowercased()
        let phrases = [
            "what do you suggest",
            "what should i eat",
            "i want",
            "can i have",
            "suggest"
        ]
        return phrases.contains { input.contains($0) }
    }

    private func dedupedItemNames(from items: [CheckInMealItemDraft]) -> [String] {
        var seen = Set<String>()
        var output: [String] = []
        for item in items {
            let trimmed = item.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let key = trimmed.lowercased()
            if seen.insert(key).inserted {
                output.append(trimmed.lowercased())
            }
        }
        return output
    }

    private func naturalJoin(_ parts: [String]) -> String {
        switch parts.count {
        case 0:
            return "your meal"
        case 1:
            return parts[0]
        case 2:
            return "\(parts[0]) and \(parts[1])"
        default:
            let allButLast = parts.dropLast().joined(separator: ", ")
            return "\(allButLast), and \(parts.last ?? "")"
        }
    }

    @ViewBuilder
    private var inlineConfirmSection: some View {
        if !viewModel.session.interpretedMeals.isEmpty {
            Button(action: { viewModel.saveInterpretedMeals() }) {
                if viewModel.isSaving {
                    HStack(spacing: DSSpacing.xs) {
                        ProgressView()
                            .tint(.white)
                        Text("Adding...")
                            .font(.body.weight(.semibold))
                    }
                } else {
                    Label(isSuggestionRequestInput ? "Add this option" : "Add to today", systemImage: "checkmark")
                        .font(.body.weight(.semibold))
                }
            }
            .buttonStyle(CoralGradientButtonStyle())
            .frame(maxWidth: .infinity)
            .scaleEffect(isConfirmPressed ? 0.98 : 1.0)
            .opacity(isConfirmPressed ? 0.94 : 1.0)
            .animation(.easeOut(duration: 0.12), value: isConfirmPressed)
            .simultaneousGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in isConfirmPressed = true }
                    .onEnded { _ in isConfirmPressed = false }
            )
        }
    }

    private func handleCapturedImage(_ image: UIImage) {
        guard let data = CheckInPhotoUploadPreprocessor.prepareMealUploadJPEG(from: image) else {
            viewModel.errorMessage = "Could not process this photo. Please try again."
            return
        }
        viewModel.session.selectedPhotoData = data
    }
}

#if DEBUG
private struct CheckInAIDebugErrorSheet: View {
    let text: String
    let onDismiss: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                Text(text)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(DSSpacing.md)
            }
            .navigationTitle("AI check-in failed")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { onDismiss() }
                }
            }
        }
    }
}
#endif

private struct CheckInMealCard: View {
    @Binding var draft: CheckInMealDraft
    var viewModel: CheckInViewModel

    @FocusState private var isMealLabelFocused: Bool
    @State private var showsCorrectionHelper = false

    private var showsAmbiguityBlock: Bool { draft.shouldShowAmbiguityUI }

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
                .font(.title3.weight(.semibold))
                .textFieldStyle(.roundedBorder)
                .focused($isMealLabelFocused)
                .onChange(of: draft.label) { _, _ in
                    viewModel.registerUserEditedMealLabel(for: draft.id)
                    if draft.isUserConfirmed {
                        showsCorrectionHelper = false
                    }
                }

            HStack(spacing: DSSpacing.xs) {
                Button("Not right?") {
                    showsCorrectionHelper = true
                    isMealLabelFocused = true
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(DSColor.textSecondary)
                .buttonStyle(.plain)

                Spacer()
            }

            if showsCorrectionHelper && !draft.isUserConfirmed {
                Text("Tell Tai what this actually was")
                    .font(.caption)
                    .foregroundStyle(DSColor.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if showsAmbiguityBlock {
                if !draft.alternatives.isEmpty {
                    ambiguityChipsRow
                } else if draft.isLowConfidence {
                    Text("Check this looks right")
                        .font(.caption)
                        .foregroundStyle(DSColor.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            HStack(spacing: DSSpacing.sm) {
                StatPill(title: "kcal", value: "\(draft.calories)")
                StatPill(title: "P", value: "\(draft.proteinGrams)g")
                StatPill(title: "C", value: "\(draft.carbsGrams)g")
                StatPill(title: "F", value: "\(draft.fatGrams)g")
            }

            Text("Confidence \(Int((draft.confidence * 100).rounded()))%")
                .font(.caption2)
                .foregroundStyle(DSColor.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            if draft.macrosNeedReview {
                VStack(alignment: .leading, spacing: DSSpacing.xs) {
                    Text("Estimate may be based on earlier details.")
                        .font(.caption)
                        .foregroundStyle(DSColor.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Button {
                        Task {
                            await viewModel.updateEstimate(for: draft.id)
                        }
                    } label: {
                        Text("Update estimate")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(DSColor.textSecondary)
                            .padding(.horizontal, DSSpacing.sm)
                            .padding(.vertical, DSSpacing.xs)
                            .background(DSColor.warmSurface)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var ambiguityChipsRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: DSSpacing.xs) {
                ForEach(Array(draft.alternatives.enumerated()), id: \.offset) { _, alt in
                    Button {
                        viewModel.selectAlternative(alt, for: draft.id)
                    } label: {
                        Text(alt)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(DSColor.textPrimary)
                            .lineLimit(1)
                            .padding(.horizontal, DSSpacing.sm)
                            .padding(.vertical, DSSpacing.xs)
                            .background(DSColor.warmSurface)
                            .overlay(
                                Capsule()
                                    .stroke(DSColor.textSecondary.opacity(0.22), lineWidth: 1)
                            )
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 2)
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
                .font(.caption)
                .foregroundStyle(DSColor.textSecondary)
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
