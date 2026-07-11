import SwiftUI

struct CheckInChooserView: View {
    var isAskTaiPreview: Bool = true
    var analytics: any AnalyticsClient = NoOpAnalyticsClient()
    var onMealSelected: () -> Void
    var onAskTaiSelected: () -> Void

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: DSSpacing.lg) {
                Text("What would you like to check in?")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(DSColor.textPrimary)
                    .padding(.top, DSSpacing.sm)

                chooserRow(
                    title: "Meal",
                    subtitle: "Log a meal or snack",
                    icon: "fork.knife",
                    showsPreviewBadge: false
                ) {
                    analytics.track(.checkInMealSelected)
                    onMealSelected()
                }

                chooserRow(
                    title: isAskTaiPreview ? "Ask Tai Preview" : "Ask Tai",
                    subtitle: "Ask a question",
                    icon: "bubble.left.and.bubble.right.fill",
                    showsPreviewBadge: isAskTaiPreview
                ) {
                    analytics.track(.checkInAskTaiSelected)
                    onAskTaiSelected()
                }

                Spacer(minLength: 0)
            }
            .padding(DSSpacing.lg)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(DSColor.background.ignoresSafeArea())
            .navigationTitle("Check In")
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
        .onAppear {
            analytics.track(.checkInChooserViewed)
        }
    }

    private func chooserRow(
        title: String,
        subtitle: String,
        icon: String,
        showsPreviewBadge: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: DSSpacing.md) {
                Image(systemName: icon)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: 48, height: 48)
                    .background(DSColor.coralGradient)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: DSSpacing.sm) {
                        Text(title)
                            .font(.headline)
                            .foregroundStyle(DSColor.textPrimary)
                        if showsPreviewBadge {
                            PreviewFeatureBadge()
                        }
                    }
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(DSColor.textSecondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(DSColor.textSecondary)
            }
            .padding(DSSpacing.lg)
            .background(DSColor.surface)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(DSColor.cardStroke, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityHint(subtitle)
    }
}

#Preview("Check In chooser") {
    CheckInChooserView(
        isAskTaiPreview: true,
        onMealSelected: {},
        onAskTaiSelected: {}
    )
}

#Preview("Check In chooser dark") {
    CheckInChooserView(
        isAskTaiPreview: true,
        onMealSelected: {},
        onAskTaiSelected: {}
    )
    .preferredColorScheme(.dark)
}
