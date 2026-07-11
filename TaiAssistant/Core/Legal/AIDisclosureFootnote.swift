import SwiftUI

struct AIDisclosureFootnote: View {
  var showsPrivacyLink: Bool = true

  var body: some View {
    VStack(alignment: .leading, spacing: DSSpacing.xs) {
      Text("Meal and goal descriptions, and meal photos, may be sent to OpenAI via our backend to generate nutrition estimates or macro targets.")
        .font(.caption2)
        .foregroundStyle(DSColor.textSecondary)
        .fixedSize(horizontal: false, vertical: true)

      if showsPrivacyLink {
        Link("Privacy Policy", destination: AppLegalLinks.privacyPolicyURL)
          .font(.caption2.weight(.semibold))
          .accessibilityIdentifier("privacyPolicyLink")
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .accessibilityIdentifier("aiDisclosureFootnote")
  }
}
