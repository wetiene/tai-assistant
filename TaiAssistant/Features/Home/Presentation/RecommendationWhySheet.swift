import SwiftUI

struct RecommendationWhySheet: View {
    let recommendation: CoachRecommendation
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
                        Text(recommendation.focusTitle)
                            .font(.headline)
                            .foregroundStyle(DSColor.coralEnd)
                        Text(recommendation.reason.summary)
                            .font(.body)
                            .foregroundStyle(DSColor.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    evidenceSection(
                        title: "What I used",
                        points: recommendation.reason.evidencePoints,
                        icon: "checkmark.circle.fill",
                        tint: DSColor.coralEnd
                    )

                    evidenceSection(
                        title: "What I don’t know yet",
                        points: recommendation.reason.unknowns,
                        icon: "questionmark.circle.fill",
                        tint: DSColor.textSecondary
                    )

                    Text("Based on today’s confirmed logs only — not sleep, weight, workouts or location.")
                        .font(.caption)
                        .foregroundStyle(DSColor.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
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
        .accessibilityLabel("Why \(assistantName) recommended \(recommendation.focusTitle)")
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

#Preview("Why this") {
    RecommendationWhySheet(
        recommendation: CoachRecommendation(
            focusTitle: "Add protein next",
            actionTitle: "Check In",
            destination: .checkInMeal,
            reason: RecommendationReason(
                summary: "Protein is the largest remaining macro gap based on today’s confirmed meals.",
                evidencePoints: [
                    "Today you have logged 62g of protein against a 170g target.",
                    "About 108g protein remains."
                ],
                unknowns: [
                    "Upcoming meals are not known until you check them in."
                ]
            )
        ),
        assistantName: "Tai"
    )
}
