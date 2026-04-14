import SwiftUI

struct AskTaiEntrySheet: View {
    let assistantName: String
    let dismiss: () -> Void
    @State private var draftPrompt = ""

    private let suggestionPrompts = AskPrompt.defaultPrompts

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
                        prompt: "Plan a high-protein dinner from my remaining macros",
                        action: { draftPrompt = "Plan a high-protein dinner from my remaining macros" }
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
                                    action: { draftPrompt = prompt.text }
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
                        dismiss()
                    } label: {
                        HStack(spacing: DSSpacing.sm) {
                            Text(draftPrompt.isEmpty ? "Start strategy conversation" : draftPrompt)
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
        }
    }
}

private struct AskPrompt: Identifiable {
    let id: String
    let title: String
    let text: String
    let icon: String
    let tint: Color

    static let defaultPrompts: [AskPrompt] = [
        AskPrompt(
            id: "protein-dinner",
            title: "Dinner move",
            text: "Plan a high-protein dinner from my remaining macros",
            icon: "fork.knife.circle.fill",
            tint: .mint
        ),
        AskPrompt(
            id: "social",
            title: "Social plan",
            text: "How do I stay on track for drinks tonight?",
            icon: "wineglass.fill",
            tint: .purple
        ),
        AskPrompt(
            id: "grocery",
            title: "Grocery sprint",
            text: "Give me a fast grocery strategy for tomorrow",
            icon: "cart.fill",
            tint: .blue
        ),
        AskPrompt(
            id: "prep",
            title: "Prep now",
            text: "What should I prep now so evening decisions are easy?",
            icon: "takeoutbag.and.cup.and.straw.fill",
            tint: .orange
        )
    ]
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
    let prompt: AskPrompt
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
