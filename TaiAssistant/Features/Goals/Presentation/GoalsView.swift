import SwiftUI

struct GoalsView: View {
    let goalRepository: GoalRepository
    let aiService: AIService
    let ownerID: String
    let localeIdentifier: String
    let timeZoneIdentifier: String

    @State private var goalPrompt = ""
    @State private var draft: GoalDraft?
    @State private var conversationRows: [GoalsContextRow] = []
    /// User-authored lines sent via the composer, joined for `GoalProfile.notes` on save (same intent as prior single `goalPrompt` field).
    @State private var accumulatedUserNotes: String = ""
    @State private var isSaving = false
    @State private var saveMessage: String?
    @State private var saveError: String?
    @State private var isInterpreting = false
    @FocusState private var isGoalPromptFocused: Bool

    private let contextSummaryMaxHeight: CGFloat = 100

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DSSpacing.xxl) {
                PrimaryCard(cornerRadius: 24, useWarmBackground: true) {
                    Label("Goal Studio", systemImage: "target")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(DSColor.coralEnd)
                    Text("Set one clear phase")
                        .font(.title3.weight(.bold))
                        .foregroundStyle(DSColor.textPrimary)
                    Text("Describe your strategy in your own words.")
                        .font(.caption)
                        .foregroundStyle(DSColor.textSecondary)
                }

                goalsContextSection

                goalsInputSection

                if let draft {
                    extractedTargetsSection(draft)
                }

                if let saveMessage {
                    Text(saveMessage)
                        .foregroundStyle(.green)
                }

                if let saveError {
                    Text(saveError)
                        .foregroundStyle(.red)
                }
            }
            .padding(DSSpacing.lg)
        }
        .scrollDismissesKeyboard(.interactively)
        .onTapGesture {
            isGoalPromptFocused = false
        }
        .background(DSColor.background.ignoresSafeArea())
        .navigationTitle("Goals")
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button {
                    isGoalPromptFocused = false
                } label: {
                    Label("Done", systemImage: "keyboard.chevron.compact.down")
                        .font(.subheadline.weight(.semibold))
                }
            }
        }
    }

    @ViewBuilder
    private var goalsContextSection: some View {
        let rows = conversationRows
        Group {
            if !rows.isEmpty {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: DSSpacing.xs) {
                            ForEach(rows) { row in
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(row.role == .user ? "You" : "Tai")
                                        .font(.caption2.weight(.semibold))
                                        .foregroundStyle(DSColor.textSecondary)
                                    goalsContextBubble(row.body)
                                        .id(row.id)
                                }
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

    private func goalsContextBubble(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(DSColor.textSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, DSSpacing.sm)
            .padding(.vertical, DSSpacing.xs)
            .background(DSColor.surface)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var goalsInputSection: some View {
        PrimaryCard(cornerRadius: 20) {
                Label("Custom strategy", systemImage: "square.and.pencil")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(DSColor.textSecondary)

                ZStack(alignment: .bottomTrailing) {
                    TextEditor(text: $goalPrompt)
                        .font(.body)
                        .frame(minHeight: 98)
                        .focused($isGoalPromptFocused)
                        .padding(.leading, DSSpacing.sm)
                        .padding(.vertical, DSSpacing.sm)
                        .padding(.trailing, 56)
                        .scrollContentBackground(.hidden)

                    Button {
                        Task { await submitComposerPrompt() }
                    } label: {
                        Group {
                            if isInterpreting {
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
                        isInterpreting ||
                        goalPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    )
                }
                .frame(minHeight: 98)
                .background(DSColor.surface)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(DSColor.coralStart.opacity(0.24), lineWidth: 1)
                )
        }
    }

    private func extractedTargetsSection(_ draft: GoalDraft) -> some View {
        VStack(alignment: .leading, spacing: DSSpacing.lg) {
            DashboardCard(title: "Extracted targets ready", icon: "checkmark.seal.fill", tint: .green) {
                Text(draft.title)
                    .font(.headline)
                if !draft.taiUiNotes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(draft.taiUiNotes)
                        .font(.subheadline)
                        .foregroundStyle(DSColor.textPrimary)
                }
                Text(draft.summary)
                    .font(.subheadline)
                    .foregroundStyle(DSColor.textSecondary)
            }

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: DSSpacing.sm) {
                GoalMetricTile(label: "Calories", value: "\(draft.calories)", unit: "kcal", tint: .orange, icon: "flame.fill")
                GoalMetricTile(label: "Protein", value: "\(draft.proteinGrams)", unit: "g", tint: .mint, icon: "fish.fill")
                GoalMetricTile(label: "Carbs", value: "\(draft.carbsGrams)", unit: "g", tint: .blue, icon: "leaf.fill")
                GoalMetricTile(label: "Fat", value: "\(draft.fatGrams)", unit: "g", tint: .yellow, icon: "drop.fill")
            }

            Button(isSaving ? "Saving..." : "Save goal") {
                Task {
                    await saveDraft(draft)
                }
            }
            .buttonStyle(CoralGradientButtonStyle())
            .disabled(isSaving)
        }
    }

    private func submitComposerPrompt() async {
        let trimmed = goalPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isInterpreting else { return }

        saveError = nil
        saveMessage = nil
        isInterpreting = true
        defer { isInterpreting = false }

        do {
            let response = try await aiService.interpretGoal(
                request: AIInterpretGoalRequest(
                    prompt: trimmed,
                    context: AIInterpretGoalContext(
                        ownerID: ownerID,
                        localeIdentifier: localeIdentifier,
                        timeZoneIdentifier: timeZoneIdentifier
                    )
                )
            )
            let newDraft = GoalDraft.fromAIResponse(response)
            draft = newDraft

            conversationRows.append(GoalsContextRow(role: .user, body: trimmed))
            conversationRows.append(GoalsContextRow(role: .tai, body: Self.taiContextFromAI(response)))

            if accumulatedUserNotes.isEmpty {
                accumulatedUserNotes = trimmed
            } else {
                accumulatedUserNotes += "\n\n" + trimmed
            }

            goalPrompt = ""
        } catch {
            let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            saveError = message
        }
    }

    private static func taiContextFromAI(_ response: AIInterpretGoalResponse) -> String {
        let macro = "\(response.calorieTarget) kcal · P\(Int(response.proteinTarget.rounded()))g · C\(Int(response.carbsTarget.rounded()))g · F\(Int(response.fatTarget.rounded()))g"
        let note = response.uiNotes.trimmingCharacters(in: .whitespacesAndNewlines)
        if note.isEmpty {
            return macro
        }
        return "\(note)\n\n\(macro)"
    }

    private func saveDraft(_ draft: GoalDraft) async {
        guard !isSaving else { return }
        isSaving = true
        defer { isSaving = false }

        do {
            let existing = try await goalRepository.fetchGoalProfiles(ownerID: ownerID)
            let notesWithMeta = accumulatedUserNotes + "\n\n[Tai goalType=\(draft.goalType); confidence=\(String(format: "%.3f", draft.confidence))]"
            let profile = existing.first ?? GoalProfile(ownerID: ownerID, title: draft.title, notes: notesWithMeta)
            profile.title = draft.title
            profile.notes = notesWithMeta
            profile.updatedAt = .now
            try await goalRepository.upsertGoalProfile(profile)

            let targets = DailyTargets(
                calories: draft.calories,
                proteinGrams: Double(draft.proteinGrams),
                carbsGrams: Double(draft.carbsGrams),
                fatGrams: Double(draft.fatGrams),
                fiberGrams: draft.fiberGrams,
                waterMilliliters: draft.waterMilliliters
            )
            try await goalRepository.saveDailyTargets(targets, goalProfileID: profile.id)

            saveMessage = "Goal saved. Dashboard guidance now uses these targets."
            goalPrompt = ""
            self.draft = nil
            conversationRows = []
            accumulatedUserNotes = ""
        } catch {
            saveError = "Could not save goal in scaffold mode. Please try again."
        }
    }
}

// MARK: - Conversation context (Check In–style rows)

private struct GoalsContextRow: Identifiable {
    enum Role {
        case user
        case tai
    }

    let id: UUID
    let role: Role
    let body: String

    init(role: Role, body: String) {
        self.id = UUID()
        self.role = role
        self.body = body
    }
}

private struct GoalMetricTile: View {
    let label: String
    let value: String
    let unit: String
    let tint: Color
    let icon: String

    var body: some View {
        PrimaryCard(cornerRadius: 16) {
            Label(label, systemImage: icon)
                .font(.caption.weight(.semibold))
                .foregroundStyle(tint)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(DSColor.textPrimary)
                Text(unit)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(DSColor.textSecondary)
            }
        }
    }
}

private struct GoalDraft {
    let title: String
    /// Training / lifestyle line from the model (`activityIntent`).
    let summary: String
    let taiUiNotes: String
    let calories: Int
    let proteinGrams: Int
    let carbsGrams: Int
    let fatGrams: Int
    let fiberGrams: Double
    let waterMilliliters: Int
    let goalType: String
    let confidence: Double

    static func fromAIResponse(_ response: AIInterpretGoalResponse) -> GoalDraft {
        GoalDraft(
            title: response.title,
            summary: response.activityIntent.trimmingCharacters(in: .whitespacesAndNewlines),
            taiUiNotes: response.uiNotes,
            calories: max(0, response.calorieTarget),
            proteinGrams: max(0, Int(response.proteinTarget.rounded())),
            carbsGrams: max(0, Int(response.carbsTarget.rounded())),
            fatGrams: max(0, Int(response.fatTarget.rounded())),
            fiberGrams: max(0, Double(response.fiberTarget)),
            waterMilliliters: max(0, response.waterTarget),
            goalType: response.goalType,
            confidence: response.confidence
        )
    }
}
