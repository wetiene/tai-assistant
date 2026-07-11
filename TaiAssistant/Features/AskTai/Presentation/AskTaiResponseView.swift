import SwiftUI

struct AskTaiResponseView: View {
    let assistantName: String
    let isPreview: Bool
    private let guidance: any AskTaiGuidanceService
    @State private var response: AskTaiResponse

    init(
        assistantName: String,
        prompt: String,
        guidance: any AskTaiGuidanceService,
        isPreview: Bool = false
    ) {
        self.assistantName = assistantName
        self.isPreview = isPreview
        self.guidance = guidance
        _response = State(initialValue: guidance.response(for: prompt))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DSSpacing.xl) {
                if isPreview {
                    previewNotice
                }

                summaryCard

                VStack(alignment: .leading, spacing: DSSpacing.md) {
                    Text("Recommended moves")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(DSColor.textSecondary)

                    ForEach(response.recommendations) { recommendation in
                        AskTaiRecommendationCard(recommendation: recommendation)
                    }
                }

                fallbackCard

                followUpChipStack
            }
            .padding(.horizontal, DSSpacing.lg)
            .padding(.vertical, DSSpacing.lg)
        }
        .background(DSColor.background.ignoresSafeArea())
        .navigationTitle(isPreview ? "\(assistantName) Preview" : "\(assistantName) Strategy")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var previewNotice: some View {
        HStack(alignment: .top, spacing: DSSpacing.sm) {
            PreviewFeatureBadge()
            Text("Sample responses for testing. Live AI guidance is not available yet. Not medical advice.")
                .font(.caption)
                .foregroundStyle(DSColor.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var summaryCard: some View {
        PrimaryCard(cornerRadius: 24, useWarmBackground: true) {
            Label("Strategist summary", systemImage: "sparkles")
                .font(.caption.weight(.semibold))
                .foregroundStyle(DSColor.coralEnd)
            Text(response.summary)
                .font(.title3.weight(.semibold))
                .foregroundStyle(DSColor.textPrimary)
            Text("Prompt: \(response.prompt)")
                .font(.caption)
                .foregroundStyle(DSColor.textSecondary)
                .lineLimit(2)
        }
    }

    private var fallbackCard: some View {
        PrimaryCard(cornerRadius: 20) {
            Label("Flexible fallback", systemImage: "arrow.triangle.branch")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.blue)
            Text(response.fallbackCoaching)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(DSColor.textPrimary)
        }
    }

    private var followUpChipStack: some View {
        VStack(alignment: .leading, spacing: DSSpacing.md) {
            Text("Quick follow-up")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(DSColor.textSecondary)

            FlexibleChipWrap(items: response.followUps) { item in
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        response = guidance.response(for: item.prompt)
                    }
                } label: {
                    Text(item.label)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(DSColor.textPrimary)
                        .padding(.horizontal, DSSpacing.md)
                        .padding(.vertical, DSSpacing.sm)
                        .background(DSColor.surface)
                        .clipShape(Capsule())
                        .overlay(
                            Capsule()
                                .stroke(DSColor.coralStart.opacity(0.25), lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
            }
        }
    }
}

private struct AskTaiRecommendationCard: View {
    let recommendation: AskTaiRecommendation

    var body: some View {
        PrimaryCard(cornerRadius: 18) {
            HStack(alignment: .top, spacing: DSSpacing.md) {
                Text(recommendation.icon)
                    .font(.title3)
                    .frame(width: 28)

                VStack(alignment: .leading, spacing: DSSpacing.sm) {
                    Text(recommendation.title)
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(DSColor.textPrimary)

                    Text(recommendation.whyItFits)
                        .font(.subheadline)
                        .foregroundStyle(DSColor.textSecondary)

                    Text(recommendation.context)
                        .font(.caption)
                        .foregroundStyle(DSColor.textSecondary)

                    Text("Macro alignment: \(recommendation.macroHint)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.blue)
                }
            }
        }
    }
}

private struct FlexibleChipWrap<Item: Identifiable, Content: View>: View {
    let items: [Item]
    @ViewBuilder var content: (Item) -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: DSSpacing.sm) {
            ForEach(stride(from: 0, to: items.count, by: 2).map { $0 }, id: \.self) { start in
                HStack(spacing: DSSpacing.sm) {
                    content(items[start])
                    if start + 1 < items.count {
                        content(items[start + 1])
                    } else {
                        Spacer(minLength: 0)
                    }
                }
            }
        }
    }
}
