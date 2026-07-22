import SwiftUI
import PhotosUI

private enum GymPlansRoute: Hashable {
    case importSource
    case pasteText
    case review(GymPlanImportDraft, String?)
    case browseTemplates
}

struct GymPlansView: View {
    let gymPlanRepository: GymPlanRepository
    let aiService: AIService
    let ownerID: String
    var importRequestContext: GymPlanImportRequestContext?
    var pendingImportReview: (draft: GymPlanImportDraft, sourceText: String?)?
    var onStartWorkout: (GymPlanWorkoutTarget) -> Void
    var onDismiss: () -> Void

    @State private var library: GymPlanLibrarySnapshot?
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var editingDraft: GymPlanDraft?
    @State private var isCreatingPlan = false
    @State private var navigationPath: [GymPlansRoute] = []
    @State private var pasteText = ""
    @State private var isAnalysing = false
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var didPresentPendingImport = false
    @State private var isPhotoPickerPresented = false
    @State private var importFailureAllowsRetry = false

    var body: some View {
        NavigationStack(path: $navigationPath) {
            List {
                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .font(.subheadline)
                            .foregroundStyle(DSColor.destructiveCoral)
                    }
                }

                Section {
                    Button {
                        navigationPath.append(.importSource)
                    } label: {
                        Label("Import Trainer Plan", systemImage: "square.and.arrow.down")
                    }
                    Button {
                        navigationPath.append(.pasteText)
                    } label: {
                        Label("Paste Plan", systemImage: "doc.text")
                    }
                    Button {
                        editingDraft = .blank()
                        isCreatingPlan = true
                    } label: {
                        Label("Create Manually", systemImage: "pencil")
                    }
                } header: {
                    Text("Add a program")
                }

                if let active = library?.activePlan {
                    Section("Current plan") {
                        planRow(active, isActive: true)
                    }
                } else if library?.hasUserPlans != true {
                    Section {
                        Text("Import your trainer’s program to get started. Built-in templates are available under Browse Templates.")
                            .font(.subheadline)
                            .foregroundStyle(DSColor.textSecondary)
                    }
                }

                if let previous = library?.previousPlans, !previous.isEmpty {
                    Section("Previous plans") {
                        ForEach(previous) { summary in
                            planRow(summary, isActive: false)
                        }
                        .onDelete(perform: deletePreviousPlans)
                    }
                }

                Section {
                    Button("Browse Templates") {
                        navigationPath.append(.browseTemplates)
                    }
                } footer: {
                    Text("Example Upper/Lower templates for testing — not your trainer program.")
                        .font(.caption)
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Gym Plans")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done", action: onDismiss)
                }
            }
            .navigationDestination(for: GymPlansRoute.self) { route in
                switch route {
                case .importSource:
                    GymPlanImportSourcePickerView(
                        onPaste: { navigationPath.append(.pasteText) },
                        onPhoto: { isPhotoPickerPresented = true },
                        onFile: { errorMessage = "PDF import is not available in this build yet." },
                        onCancel: { navigationPath.removeLast() }
                    )
                    .photosPicker(
                        isPresented: $isPhotoPickerPresented,
                        selection: $selectedPhoto,
                        matching: .images
                    )
                    .onChange(of: selectedPhoto) { _, item in
                        guard item != nil else { return }
                        Task { await analyseSelectedPhoto(item) }
                    }
                case .pasteText:
                    GymPlanImportPasteView(
                        pastedText: $pasteText,
                        isAnalysing: isAnalysing,
                        errorMessage: errorMessage,
                        showsRetry: importFailureAllowsRetry,
                        onAnalyse: { Task { await analysePastedText() } },
                        onRetry: { Task { await analysePastedText() } },
                        onCancel: { navigationPath.removeLast() }
                    )
                case .review(let draft, let sourceText):
                    GymPlanImportReviewView(
                        importDraft: draft,
                        sourceText: sourceText,
                        gymPlanRepository: gymPlanRepository,
                        ownerID: ownerID,
                        hasActivePlan: library?.activePlan != nil,
                        onSaved: {
                            navigationPath = []
                            pasteText = ""
                            Task { await reload() }
                        },
                        onCancel: { navigationPath.removeLast() },
                        onReanalyse: { source in
                            try await GymPlanImportService.interpret(
                                source: source,
                                aiService: aiService,
                                requestContext: importRequestContext
                            )
                        }
                    )
                case .browseTemplates:
                    templateList
                }
            }
            .task { await reload() }
            .task(id: pendingImportReview?.draft.id) {
                guard !didPresentPendingImport, let pending = pendingImportReview else { return }
                didPresentPendingImport = true
                navigationPath = [.review(pending.draft, pending.sourceText)]
            }
            .refreshable { await reload() }
            .sheet(isPresented: Binding(
                get: { editingDraft != nil },
                set: { presented in
                    if !presented {
                        editingDraft = nil
                        isCreatingPlan = false
                    }
                }
            )) {
                if let draft = editingDraft {
                    NavigationStack {
                        GymPlanEditorView(
                            draft: draft,
                            gymPlanRepository: gymPlanRepository,
                            ownerID: ownerID,
                            isNewPlan: isCreatingPlan,
                            onSave: { _ in
                                isCreatingPlan = false
                                editingDraft = nil
                                Task { await reload() }
                            },
                            onDuplicate: { reference in
                                Task {
                                    _ = try? await gymPlanRepository.duplicatePlan(reference: reference, ownerID: ownerID)
                                    await reload()
                                }
                            },
                            onResetStarter: { templateID in
                                Task {
                                    try? await gymPlanRepository.resetStarterPlan(templateID: templateID, ownerID: ownerID)
                                    editingDraft = nil
                                    await reload()
                                }
                            },
                            onCancel: {
                                isCreatingPlan = false
                                editingDraft = nil
                            }
                        )
                    }
                }
            }
            .overlay {
                if isLoading && library == nil {
                    ProgressView("Loading plans…")
                }
                if isAnalysing {
                    ProgressView("Analysing program…")
                        .padding()
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                }
            }
        }
    }

    private var templateList: some View {
        List {
            ForEach(gymPlanRepository.fetchTemplateSummaries()) { summary in
                VStack(alignment: .leading, spacing: DSSpacing.xs) {
                    Text(summary.title).font(.headline)
                    Text("Example template · \(summary.exerciseCount) exercises")
                        .font(.caption)
                        .foregroundStyle(DSColor.textSecondary)
                    Button("Start example workout") {
                        onStartWorkout(GymPlanWorkoutTarget(reference: summary.reference, sectionIndex: 0))
                    }
                    .font(.subheadline.weight(.semibold))
                }
                .padding(.vertical, DSSpacing.xs)
            }
        }
        .navigationTitle("Browse Templates")
    }

    @ViewBuilder
    private func planRow(_ summary: GymPlanSummary, isActive: Bool) -> some View {
        VStack(alignment: .leading, spacing: DSSpacing.xs) {
            HStack {
                Text(summary.title)
                    .font(.headline)
                Spacer()
                if isActive {
                    Text("Active")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(DSColor.coralEnd)
                } else if summary.lifecycleStatus == .archived {
                    Text("Archived")
                        .font(.caption2)
                        .foregroundStyle(DSColor.textSecondary)
                }
            }
            if let importedAt = summary.importedAt {
                Text("Imported \(importedAt.formatted(date: .abbreviated, time: .omitted))")
                    .font(.caption2)
                    .foregroundStyle(DSColor.textSecondary)
            }
            if let weeks = summary.suggestedDurationWeeks {
                Text("Suggested \(weeks)-week program")
                    .font(.caption2)
                    .foregroundStyle(DSColor.textSecondary)
            }
            Text("\(summary.sectionCount) sections · \(summary.exerciseCount) exercises · \(summary.repRangeLabel)")
                .font(.caption)
                .foregroundStyle(DSColor.textSecondary)

            HStack(spacing: DSSpacing.md) {
                Button("Edit") {
                    Task { await openEditor(for: summary.reference) }
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(DSColor.coralEnd)
                .buttonStyle(.plain)

                if summary.sectionCount > 1 {
                    Menu("Start workout") {
                        ForEach(summary.sectionNames.indices, id: \.self) { index in
                            Button(summary.sectionNames[index]) {
                                onStartWorkout(GymPlanWorkoutTarget(reference: summary.reference, sectionIndex: index))
                            }
                        }
                    }
                    .font(.subheadline.weight(.semibold))
                } else {
                    Button("Start workout") {
                        onStartWorkout(GymPlanWorkoutTarget(reference: summary.reference, sectionIndex: 0))
                    }
                    .font(.subheadline.weight(.semibold))
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.vertical, DSSpacing.xs)
    }

    private func reload() async {
        isLoading = true
        defer { isLoading = false }
        do {
            library = try await gymPlanRepository.fetchLibrary(ownerID: ownerID)
            errorMessage = nil
        } catch {
            errorMessage = "Couldn’t load workout plans."
        }
    }

    private func analysePastedText() async {
        isAnalysing = true
        defer { isAnalysing = false }
        do {
            let draft = try await GymPlanImportService.interpret(
                source: .pastedText(pasteText),
                aiService: aiService,
                requestContext: importRequestContext
            )
            errorMessage = nil
            importFailureAllowsRetry = false
            navigationPath.append(.review(draft, pasteText))
        } catch let error as GymPlanImportError {
            errorMessage = error.userFacingMessage
            importFailureAllowsRetry = error.allowsRetry
        } catch {
            errorMessage = GymPlanImportError.transport(underlying: error).userFacingMessage
            importFailureAllowsRetry = true
        }
    }

    private func analyseSelectedPhoto(_ item: PhotosPickerItem?) async {
        guard let item else { return }
        isAnalysing = true
        defer {
            isAnalysing = false
            selectedPhoto = nil
            isPhotoPickerPresented = false
        }
        do {
            guard let data = try await item.loadTransferable(type: Data.self) else {
                errorMessage = GymPlanImportImageSupport.ValidationError.empty.errorDescription
                return
            }
            var source = try GymPlanImportImageSupport.makeSource(from: data)
            let draft = try await GymPlanImportService.interpret(
                source: source,
                aiService: aiService,
                requestContext: importRequestContext
            )
            source.clearTransientPayload()
            errorMessage = nil
            importFailureAllowsRetry = false
            navigationPath.append(.review(draft, nil))
        } catch let error as GymPlanImportImageSupport.ValidationError {
            errorMessage = error.errorDescription
            importFailureAllowsRetry = false
        } catch let error as GymPlanImportError {
            errorMessage = error.userFacingMessage
            importFailureAllowsRetry = error.allowsRetry
        } catch {
            errorMessage = GymPlanImportError.transport(underlying: error).userFacingMessage
            importFailureAllowsRetry = true
        }
    }

    private func openEditor(for reference: GymPlanReference) async {
        do {
            let draft = try await gymPlanRepository.loadDraft(reference: reference, ownerID: ownerID)
            isCreatingPlan = false
            editingDraft = draft
        } catch {
            errorMessage = "Couldn’t open this plan."
        }
    }

    private func deletePreviousPlans(at offsets: IndexSet) {
        guard let previous = library?.previousPlans else { return }
        let targets = offsets.compactMap { previous.indices.contains($0) ? previous[$0] : nil }
        Task {
            for summary in targets where summary.isCustom {
                try? await gymPlanRepository.deletePlan(reference: summary.reference, ownerID: ownerID)
            }
            await reload()
        }
    }
}

extension GymPlanImportDraft: Hashable {
    static func == (lhs: GymPlanImportDraft, rhs: GymPlanImportDraft) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}
