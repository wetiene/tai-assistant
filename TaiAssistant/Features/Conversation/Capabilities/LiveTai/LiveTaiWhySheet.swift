import SwiftUI

/// Why disclosure for Live Tai replies — Evidence metadata, not a structured coaching card.
struct LiveTaiWhySheet: View {
    let evidence: LiveTaiEvidencePayload
    let assistantName: String
    var onDismiss: (() -> Void)? = nil

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: DSSpacing.xl) {
                    VStack(alignment: .leading, spacing: DSSpacing.sm) {
                        Text("Why this?")
                            .font(.title2.weight(.bold))
                            .foregroundStyle(DSColor.textPrimary)
                        if let summary = evidence.summary, !summary.isEmpty {
                            Text(summary)
                                .font(.body)
                                .foregroundStyle(DSColor.textPrimary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        if let confidence = evidence.confidence, !confidence.isEmpty {
                            Text("Confidence: \(confidence)")
                                .font(.subheadline)
                                .foregroundStyle(DSColor.textSecondary)
                        }
                    }

                    if !evidence.evidence.isEmpty {
                        evidenceSection(
                            title: "What I used",
                            points: evidence.evidence.map { item in
                                if let detail = item.detail, !detail.isEmpty {
                                    return "\(item.label): \(detail)"
                                }
                                return item.label
                            },
                            icon: "checkmark.circle.fill",
                            tint: DSColor.coralEnd
                        )
                    }

                    if !evidence.limitationsShown.isEmpty {
                        evidenceSection(
                            title: "What limited this answer",
                            points: evidence.limitationsShown,
                            icon: "questionmark.circle.fill",
                            tint: DSColor.textSecondary
                        )
                    }

                    if evidence.requiresUserDecision {
                        Text("Tai suggested a change but will not update your saved data unless you confirm.")
                            .font(.caption)
                            .foregroundStyle(DSColor.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(DSSpacing.lg)
            }
            .background(DSColor.background.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        onDismiss?()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .accessibilityLabel("Why \(assistantName) answered this way")
    }

    @ViewBuilder
    private func evidenceSection(
        title: String,
        points: [String],
        icon: String,
        tint: Color
    ) -> some View {
        VStack(alignment: .leading, spacing: DSSpacing.sm) {
            Label(title, systemImage: icon)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(tint)

            ForEach(Array(points.enumerated()), id: \.offset) { _, point in
                HStack(alignment: .top, spacing: DSSpacing.sm) {
                    Circle()
                        .fill(tint.opacity(0.85))
                        .frame(width: 6, height: 6)
                        .padding(.top, 7)
                    Text(point)
                        .font(.subheadline)
                        .foregroundStyle(DSColor.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}
