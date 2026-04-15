import SwiftUI

struct AskTaiEntrySheet: View {
    let assistantName: String
    let askTaiGuidance: any AskTaiGuidanceService
    let initialPrompt: String?
    let dismiss: () -> Void
    @State private var draftPrompt = ""
    @State private var responseRoute: AskTaiResponseRoute?

    private let suggestionPrompts = AskTaiPromptPreset.defaultPrompts
    private let featuredPrompt = "Plan a high-protein dinner from my remaining macros"

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: DSSpacing.xxl) {
                    VStack(alignment: .leading, spacing: DSSpacing.xs) {
                        Text("Ask \(assistantName)")
                            .font(.largeTitle.weight(.bold))
                            .foregroundStyle(DSColor.textPrimary)
                        Text("Choose your next decision")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(DSColor.textSecondary)
                    }

                    BestAskCard(
                        title: "Best next ask",
                        prompt: featuredPrompt,
                        action: { openResponse(with: featuredPrompt) }
                    )

                    VStack(alignment: .leading, spacing: DSSpacing.md) {
                        Text("Quick decision tiles")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(DSColor.textSecondary)

                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: DSSpacing.sm) {
                            ForEach(suggestionPrompts) { prompt in
                                AskDecisionTile(
                                    prompt: prompt,
                                    isSelected: draftPrompt == prompt.text,
                                    action: { openResponse(with: prompt.text) }
                                )
                            }
                        }
                    }
                }
                .padding(.horizontal, DSSpacing.lg)
                .padding(.top, DSSpacing.lg)
                .padding(.bottom, 110)
            }
            .background(DSColor.background.ignoresSafeArea())
            .safeAreaInset(edge: .bottom) {
                HStack(spacing: DSSpacing.sm) {
                    Button {
                        // Voice-ready affordance only for now.
                    } label: {
                        Image(systemName: "mic.fill")
                            .font(.headline)
                            .foregroundStyle(DSColor.coralEnd)
                            .frame(width: 42, height: 42)
                            .background(DSColor.warmSurface)
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)

                    Button {
                        let prompt = draftPrompt.isEmpty ? featuredPrompt : draftPrompt
                        openResponse(with: prompt)
                    } label: {
                        HStack(spacing: DSSpacing.sm) {
                            Text(draftPrompt.isEmpty ? "Start strategy response" : draftPrompt)
                                .lineLimit(1)
                            Spacer()
                            Image(systemName: "arrow.up.circle.fill")
                                .font(.title3)
                        }
                    }
                    .buttonStyle(CoralGradientButtonStyle())
                }
                .padding(.horizontal, DSSpacing.lg)
                .padding(.vertical, DSSpacing.md)
                .background(.ultraThinMaterial)
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done", action: dismiss)
                }
            }
            .navigationDestination(item: $responseRoute) { route in
                AskTaiResponseView(assistantName: assistantName, prompt: route.prompt, guidance: askTaiGuidance)
            }
            .onAppear {
                if draftPrompt.isEmpty, let initialPrompt {
                    draftPrompt = initialPrompt
                }
            }
        }
    }

    private func openResponse(with prompt: String) {
        draftPrompt = prompt
        responseRoute = AskTaiResponseRoute(prompt: prompt)
    }
}

private struct AskTaiResponseRoute: Hashable, Identifiable {
    let prompt: String
    var id: String { prompt }
}

private struct BestAskCard: View {
    let title: String
    let prompt: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: DSSpacing.md) {
                Label(title, systemImage: "sparkles")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.86))
                HStack(spacing: DSSpacing.md) {
                    Image(systemName: "takeoutbag.and.cup.and.straw.fill")
                        .font(.title2)
                        .foregroundStyle(.white)
                    Text(prompt)
                        .font(.headline.weight(.semibold))
                        .multilineTextAlignment(.leading)
                        .foregroundStyle(.white)
                    Spacer()
                    Image(systemName: "arrow.right.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.white.opacity(0.9))
                }
            }
            .padding(DSSpacing.xl)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(DSColor.coralGradient)
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(Color.white.opacity(0.26), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

private struct AskDecisionTile: View {
    let prompt: AskTaiPromptPreset
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            PrimaryCard(cornerRadius: 16, useWarmBackground: isSelected) {
                Label(prompt.title, systemImage: prompt.icon)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(prompt.tint)
                Text(prompt.text)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(DSColor.textPrimary)
                    .multilineTextAlignment(.leading)
                    .lineLimit(3)
            }
        }
        .buttonStyle(.plain)
    }
}
