import SwiftUI

struct FloatingAskTaiButton: View {
    let assistantName: String
    var isDeemphasized: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: DSSpacing.sm) {
                Image(systemName: "sparkles")
                    .font(.subheadline.weight(.semibold))
                Text("Ask \(assistantName)")
                    .font(.headline.weight(.semibold))
            }
            .foregroundStyle(DSColor.coralEnd.opacity(1.0))
            .padding(.horizontal, DSSpacing.md + 2)
            .frame(height: 48)
            .background {
                ZStack {
                    Capsule()
                        .fill(Color.white.opacity(0.93))
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [
                                    DSColor.coralStart.opacity(0.28),
                                    DSColor.warmSurface.opacity(0.985)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                }
            }
            .clipShape(Capsule())
            .shadow(color: Color.black.opacity(0.095), radius: 6, y: 3)
            .shadow(color: DSColor.coralEnd.opacity(0.06), radius: 4, y: 1.5)
        }
        .buttonStyle(FloatingAskTaiButtonStyle())
        .opacity(isDeemphasized ? 0.88 : 1.0)
        .scaleEffect(isDeemphasized ? 0.96 : 1.0)
        .animation(.easeInOut(duration: 0.2), value: isDeemphasized)
        .contentShape(Capsule())
        .accessibilityLabel("Ask \(assistantName)")
        .accessibilityIdentifier("floatingAskTaiButton")
    }
}

private struct FloatingAskTaiButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .opacity(configuration.isPressed ? 0.9 : 1.0)
            .animation(.easeOut(duration: 0.14), value: configuration.isPressed)
    }
}
