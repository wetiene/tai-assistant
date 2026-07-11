import SwiftUI

struct NutritionEstimateDisclaimer: View {
  var body: some View {
    Text("Nutrition estimates are approximate and are not medical advice.")
      .font(.caption2)
      .foregroundStyle(DSColor.textSecondary)
      .multilineTextAlignment(.center)
      .frame(maxWidth: .infinity)
      .accessibilityIdentifier("nutritionEstimateDisclaimer")
  }
}
