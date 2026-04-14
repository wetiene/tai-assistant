import SwiftUI

struct FloatingAskTaiButton: View {
    let assistantName: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label("Ask \(assistantName)", systemImage: "sparkles")
                .font(.headline)
                .foregroundStyle(.white)
                .padding(.horizontal, DSSpacing.lg)
                .padding(.vertical, DSSpacing.md)
                .background(DSColor.accent)
                .clipShape(Capsule())
                .shadow(radius: 6, y: 3)
        }
        .accessibilityIdentifier("floatingAskTaiButton")
    }
}
