import SwiftUI

struct PreviewFeatureBadge: View {
  var body: some View {
    Text("Preview")
      .font(.caption2.weight(.bold))
      .foregroundStyle(DSColor.textSecondary)
      .padding(.horizontal, DSSpacing.xs)
      .padding(.vertical, 2)
      .background(DSColor.warmSurface)
      .clipShape(Capsule())
      .accessibilityLabel("Preview feature")
  }
}
