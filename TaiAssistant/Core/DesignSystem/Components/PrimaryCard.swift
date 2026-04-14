import SwiftUI

struct PrimaryCard<Content: View>: View {
    var cornerRadius: CGFloat = 20
    var useWarmBackground: Bool = false
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: DSSpacing.md) {
            content
        }
        .padding(DSSpacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(useWarmBackground ? DSColor.warmSurface : DSColor.surface)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(Color.white.opacity(0.5), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.08), radius: 14, y: 8)
    }
}

struct CoralGradientButtonStyle: ButtonStyle {
    var isCompact = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, isCompact ? DSSpacing.lg : DSSpacing.xl)
            .padding(.vertical, isCompact ? DSSpacing.sm + 2 : DSSpacing.md)
            .frame(maxWidth: isCompact ? nil : .infinity)
            .background(DSColor.coralGradient)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .opacity(configuration.isPressed ? 0.92 : 1.0)
            .shadow(color: DSColor.coralEnd.opacity(0.25), radius: 10, y: 5)
            .animation(.easeOut(duration: 0.16), value: configuration.isPressed)
    }
}
