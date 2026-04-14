import SwiftUI

struct FloatingAskTaiButton: View {
    let assistantName: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: DSSpacing.sm) {
                Image(systemName: "sparkles")
                    .font(.subheadline.weight(.bold))
                Text("Ask \(assistantName)")
                    .font(.headline.weight(.semibold))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, DSSpacing.lg)
            .padding(.vertical, DSSpacing.md)
            .background(DSColor.coralGradient)
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .stroke(Color.white.opacity(0.35), lineWidth: 1)
            )
            .shadow(color: DSColor.coralEnd.opacity(0.35), radius: 12, y: 6)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("floatingAskTaiButton")
    }
}
