import SwiftUI

enum AIDataProcessingConsentStore {
  private static let acceptedKey = "tai.aiDataProcessingConsent.accepted"

  static var hasAccepted: Bool {
    UserDefaults.standard.bool(forKey: acceptedKey)
  }

  static func accept() {
    UserDefaults.standard.set(true, forKey: acceptedKey)
  }
}

struct AIDataProcessingConsentSheet: View {
  let onAccept: () -> Void
  let onDecline: () -> Void

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: DSSpacing.lg) {
          Text("AI processing")
            .font(.title2.weight(.bold))
            .foregroundStyle(DSColor.textPrimary)

          Text(
            "When you check in with text or a meal photo, or describe a goal strategy, Tai sends that content to our backend for analysis. Photos are resized before upload. Meal photos are not kept on your device after you confirm a check-in."
          )
          .font(.subheadline)
          .foregroundStyle(DSColor.textSecondary)

          Text(
            "OpenAI is our third-party AI provider. Content is transmitted through our Cloudflare Worker proxy and processed to return nutrition estimates or suggested macro targets. Do not include sensitive personal information in descriptions or photos."
          )
          .font(.subheadline)
          .foregroundStyle(DSColor.textSecondary)

          Text(
            "Nutrition and goal suggestions are approximate and are not medical advice. To withdraw consent or learn how your data is handled, see our Privacy Policy."
          )
          .font(.subheadline)
          .foregroundStyle(DSColor.textSecondary)

          Link("Privacy Policy", destination: AppLegalLinks.privacyPolicyURL)
            .font(.subheadline.weight(.semibold))
        }
        .padding(DSSpacing.lg)
      }
      .background(DSColor.background.ignoresSafeArea())
      .safeAreaInset(edge: .bottom) {
        VStack(spacing: DSSpacing.sm) {
          Button("Continue") {
            AIDataProcessingConsentStore.accept()
            onAccept()
          }
          .buttonStyle(CoralGradientButtonStyle())

          Button("Not now", action: onDecline)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(DSColor.textSecondary)
        }
        .padding(DSSpacing.lg)
        .background(.ultraThinMaterial)
      }
    }
  }
}
