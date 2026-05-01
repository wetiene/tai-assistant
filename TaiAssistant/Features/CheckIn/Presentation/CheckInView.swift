import SwiftUI
import UIKit

struct CheckInView: View {
    let mealRepository: MealRepository
    let ownerID: String
    let interpreter: any CheckInInterpreting
    var onMealsSaved: (() -> Void)? = nil

    @State private var session = CheckInSessionDraft()
    @State private var isCameraPresented = false
    @State private var isInterpreting = false
    @State private var isSaving = false
    @State private var isPhotoPreviewPresented = false
    @State private var errorMessage: String?
    @State private var isConfirmPressed = false
    @State private var isTaiNoteExpanded = false
    @State private var dayProgress = DayProgress()
    @FocusState private var isComposerFocused: Bool

    private enum CheckInUIState {
        case typing
        case processing
        case result
    }

    private var uiState: CheckInUIState {
        if isInterpreting {
            return .processing
        }
        if !session.interpretedMeals.isEmpty {
            return .result
        }
        return .typing
    }

    private let shortcuts = [
        "Usual breakfast",
        "Protein shake",
        "Yesterday lunch",
        "Family dinner"
    ]

    private struct DayProgress {
        var consumedCalories: Int = 0
        var targetCalories: Int = 2100
        var consumedProtein: Int = 0
        var proteinTarget: Int = 150
    }

    init(
        mealRepository: MealRepository,
        ownerID: String,
        interpreter: any CheckInInterpreting = MockCheckInInterpreter(),
        onMealsSaved: (() -> Void)? = nil
    ) {
        self.mealRepository = mealRepository
        self.ownerID = ownerID
        self.interpreter = interpreter
        self.onMealsSaved = onMealsSaved
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DSSpacing.xl) {
                Text("Tell Tai what happened")
                    .font(.title.weight(.bold))
                    .foregroundStyle(DSColor.textPrimary)

                composerCard

                switch uiState {
                case .typing:
                    shortcutsSection
                case .processing:
                    processingSection
                case .result:
                    interpretedMealsSection
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
        .alert("Check In", isPresented: Binding(
            get: { errorMessage != nil },
            set: { isPresented in
                if !isPresented {
                    errorMessage = nil
                }
            }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
        .onAppear {
            print("USING CHECKINVIEW")
            Task {
                await refreshDayProgress()
            }
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
                    isComposerFocused = false
                    Task {
                        await inferMeals()
                    }
                } label: {
                    if isInterpreting {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Label("Check In", systemImage: "sparkles")
                    }
                }
                .buttonStyle(CoralGradientButtonStyle(isCompact: true))
                .disabled(
                    isInterpreting ||
                    (session.userInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && session.selectedPhotoData == nil)
                )
            }

            selectedPhotoThumbnail
        }
    }

    private var processingSection: some View {
        PrimaryCard(cornerRadius: 24) {
            HStack(spacing: DSSpacing.sm) {
                ProgressView()
                Text("Interpreting check in...")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(DSColor.textPrimary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private var selectedPhotoThumbnail: some View {
        if let photoData = session.selectedPhotoData, let image = UIImage(data: photoData) {
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
                        session.selectedPhotoData = nil
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
        if let photoData = session.selectedPhotoData, let image = UIImage(data: photoData) {
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
        VStack(alignment: .leading, spacing: DSSpacing.lg) {
            aiSummarySection

            if !session.interpretedMeals.isEmpty {
                Text("Inferred meals")
                    .font(.body.weight(.medium))
                    .foregroundStyle(DSColor.textPrimary)
            }
            ForEach($session.interpretedMeals) { $meal in
                CheckInMealCard(draft: $meal)
            }
        }
    }

    @ViewBuilder
    private var aiSummarySection: some View {
        if !session.interpretedMeals.isEmpty {
            VStack(alignment: .leading, spacing: DSSpacing.xs) {
                Text(understoodAsText)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(DSColor.textPrimary.opacity(0.88))
                    .lineLimit(2)

                HStack(alignment: .firstTextBaseline, spacing: DSSpacing.xs) {
                    Image(systemName: "sparkles")
                        .font(.caption)
                        .foregroundStyle(DSColor.coralEnd)
                    Text(taiNoteText)
                        .font(.body.weight(.medium))
                        .foregroundStyle(DSColor.textPrimary)
                        .lineLimit(isTaiNoteExpanded ? nil : 3)
                        .onTapGesture {
                            if shouldShowTaiNoteExpansion {
                                withAnimation(.easeInOut(duration: 0.15)) {
                                    isTaiNoteExpanded.toggle()
                                }
                            }
                        }
                }
            }
            .padding(.horizontal, DSSpacing.sm)
            .padding(.vertical, DSSpacing.xs + 2)
            .background(DSColor.warmSurface.opacity(0.55))
            .overlay(alignment: .leading) {
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(DSColor.coralGradient.opacity(0.35))
                    .frame(width: 3)
                    .padding(.vertical, 6)
                    .padding(.leading, 2)
            }
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    private var understoodAsText: String {
        let meals = session.interpretedMeals
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
        if let notes = session.interpretationNotes?.trimmingCharacters(in: .whitespacesAndNewlines), !notes.isEmpty {
            return notes
        }

        let allItems = session.interpretedMeals.flatMap(\.items)
        let itemNames = allItems.map { $0.name.lowercased() }
        let totalProtein = session.interpretedMeals.reduce(0) { $0 + $1.proteinGrams }
        let totalCarbs = session.interpretedMeals.reduce(0) { $0 + $1.carbsGrams }
        let totalCalories = session.interpretedMeals.reduce(0) { $0 + $1.calories }

        let isOverCaloriesToday = dayProgress.consumedCalories > dayProgress.targetCalories
        let isLowProteinToday = dayProgress.consumedProtein < dayProgress.proteinTarget
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
        let input = session.userInput.lowercased()
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
        if !session.interpretedMeals.isEmpty {
            Button(action: saveInterpretedMeals) {
                if isSaving {
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

    private func inferMeals() async {
        guard !isInterpreting else { return }
        isInterpreting = true
        isTaiNoteExpanded = false
        defer { isInterpreting = false }
        do {
            let interpretation = try await interpreter.interpret(
                input: session.userInput,
                photoData: session.selectedPhotoData
            )
            session.interpretedMeals = interpretation.meals
            session.interpretationNotes = interpretation.uiNotes
            await refreshDayProgress()
        } catch {
            errorMessage = "Could not interpret this check in. Please try again."
        }
    }

    private func handleCapturedImage(_ image: UIImage) {
        guard let data = CheckInPhotoUploadPreprocessor.prepareMealUploadJPEG(from: image) else {
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
                session = CheckInSessionDraft()
                onMealsSaved?()
                await refreshDayProgress()
            } catch {
                errorMessage = "Could not save check in meals. Please retry."
            }
        }
    }

    private func refreshDayProgress() async {
        let calendar = Calendar.current
        let dayStart = calendar.startOfDay(for: .now)
        let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) ?? .now
        do {
            let meals = try await mealRepository.fetchMealLogs(ownerID: ownerID, from: dayStart, to: dayEnd)
            let consumedCalories = meals.flatMap(\.items).reduce(0) { $0 + $1.calories }
            let consumedProtein = Int(meals.flatMap(\.items).reduce(0.0) { $0 + $1.proteinGrams }.rounded())
            await MainActor.run {
                dayProgress.consumedCalories = consumedCalories
                dayProgress.consumedProtein = consumedProtein
            }
        } catch {
            // Keep prior day progress values if refresh fails.
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
                .font(.title3.weight(.semibold))
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
