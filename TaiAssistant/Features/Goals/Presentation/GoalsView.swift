import SwiftUI

struct GoalsView: View {
    let goalRepository: GoalRepository
    let ownerID: String

    @State private var goalPrompt = ""
    @State private var draft: GoalDraft?
    @State private var isSaving = false
    @State private var saveMessage: String?
    @State private var saveError: String?
    @FocusState private var isGoalPromptFocused: Bool

    private let samplePrompts = GoalPreset.defaultPresets

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
                    Text("Choose a preset or type your own strategy.")
                        .font(.caption)
                        .foregroundStyle(DSColor.textSecondary)
                }

                if draft == nil {
                    inputStep
                } else if let draft {
                    confirmationStep(draft)
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

    private var inputStep: some View {
        VStack(alignment: .leading, spacing: DSSpacing.lg) {
            PrimaryCard(cornerRadius: 20) {
                Label("Goal presets", systemImage: "square.grid.2x2.fill")
                    .font(.headline.weight(.semibold))

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: DSSpacing.sm)], spacing: DSSpacing.sm) {
                    ForEach(samplePrompts) { preset in
                        GoalPresetChip(
                            preset: preset,
                            isSelected: goalPrompt == preset.prompt,
                            action: { goalPrompt = preset.prompt }
                        )
                    }
                }
            }

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

                    Button(action: previewDraft) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 15, weight: .semibold))
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
                    .disabled(goalPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
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
    }

    private func confirmationStep(_ draft: GoalDraft) -> some View {
        VStack(alignment: .leading, spacing: DSSpacing.lg) {
            DashboardCard(title: "Extracted targets ready", icon: "checkmark.seal.fill", tint: .green) {
                Text(draft.title)
                    .font(.headline)
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

            VStack(spacing: DSSpacing.sm) {
                Button(isSaving ? "Saving..." : "Save goal") {
                    Task {
                        await saveDraft(draft)
                    }
                }
                .buttonStyle(CoralGradientButtonStyle())
                .disabled(isSaving)

                Button("Edit prompt") {
                    self.draft = nil
                }
                .buttonStyle(.bordered)
            }
        }
    }

    private func previewDraft() {
        saveError = nil
        saveMessage = nil
        draft = GoalDraft.fromPrompt(goalPrompt)
    }

    private func saveDraft(_ draft: GoalDraft) async {
        guard !isSaving else { return }
        isSaving = true
        defer { isSaving = false }

        do {
            let existing = try await goalRepository.fetchGoalProfiles(ownerID: ownerID)
            let profile = existing.first ?? GoalProfile(ownerID: ownerID, title: draft.title, notes: goalPrompt)
            profile.title = draft.title
            profile.notes = goalPrompt
            profile.updatedAt = .now
            try await goalRepository.upsertGoalProfile(profile)

            let targets = DailyTargets(
                calories: draft.calories,
                proteinGrams: Double(draft.proteinGrams),
                carbsGrams: Double(draft.carbsGrams),
                fatGrams: Double(draft.fatGrams),
                fiberGrams: 30,
                waterMilliliters: 2600
            )
            try await goalRepository.saveDailyTargets(targets, goalProfileID: profile.id)

            saveMessage = "Goal saved. Dashboard guidance now uses these targets."
            goalPrompt = ""
            self.draft = nil
        } catch {
            saveError = "Could not save goal in scaffold mode. Please try again."
        }
    }
}

private struct GoalPreset: Identifiable {
    let id: String
    let title: String
    let caption: String
    let icon: String
    let prompt: String

    static let defaultPresets: [GoalPreset] = [
        GoalPreset(
            id: "lean-cut",
            title: "Lean Cut",
            caption: "High protein, social guardrails",
            icon: "flame.fill",
            prompt: "Help me run a lean cut while keeping strength. Keep protein high and alcohol to weekends only."
        ),
        GoalPreset(
            id: "maintenance",
            title: "Maintenance",
            caption: "Predictable weekdays, light dinners",
            icon: "bolt.heart.fill",
            prompt: "I want a maintenance plan for busy weekdays with predictable breakfasts and lighter dinners."
        ),
        GoalPreset(
            id: "recomp",
            title: "Recomp",
            caption: "Fuel lifting 4x per week",
            icon: "figure.strengthtraining.traditional",
            prompt: "Build a recomposition target with enough carbs for lifting 4x per week."
        )
    ]
}

private struct GoalPresetChip: View {
    let preset: GoalPreset
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: DSSpacing.xs) {
                Label(preset.title, systemImage: preset.icon)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(isSelected ? .white : DSColor.textPrimary)
                Text(preset.caption)
                    .font(.caption)
                    .foregroundStyle(isSelected ? .white.opacity(0.85) : DSColor.textSecondary)
                    .lineLimit(2)
            }
            .padding(DSSpacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                Group {
                    if isSelected {
                        DSColor.coralGradient
                    } else {
                        LinearGradient(colors: [DSColor.surface], startPoint: .top, endPoint: .bottom)
                    }
                }
            )
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
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
    let summary: String
    let calories: Int
    let proteinGrams: Int
    let carbsGrams: Int
    let fatGrams: Int

    static func fromPrompt(_ prompt: String) -> GoalDraft {
        let normalized = prompt.lowercased()
        if normalized.contains("cut") || normalized.contains("lean") {
            return GoalDraft(
                title: "Lean cut with high protein",
                summary: "Fat loss focus with higher protein and controlled social alcohol.",
                calories: 1900,
                proteinGrams: 170,
                carbsGrams: 150,
                fatGrams: 60
            )
        }

        if normalized.contains("maintenance") {
            return GoalDraft(
                title: "Balanced maintenance",
                summary: "Steady energy with predictable weekday structure and moderate dinner load.",
                calories: 2200,
                proteinGrams: 150,
                carbsGrams: 230,
                fatGrams: 75
            )
        }

        return GoalDraft(
            title: "Performance-focused recomposition",
            summary: "Support training performance while gradually improving body composition.",
            calories: 2300,
            proteinGrams: 165,
            carbsGrams: 245,
            fatGrams: 70
        )
    }
}
