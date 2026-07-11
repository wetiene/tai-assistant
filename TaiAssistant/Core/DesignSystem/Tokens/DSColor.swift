import SwiftUI
import UIKit

enum DSColor {
    static let background = Color(.systemGroupedBackground)
    static let surface = Color(.secondarySystemGroupedBackground)
    static let textPrimary = Color.primary
    static let textSecondary = Color.secondary
    static let accent = Color.blue
    static let coralStart = Color(red: 1.0, green: 0.49, blue: 0.42)
    static let coralEnd = Color(red: 1.0, green: 0.35, blue: 0.47)
    static let destructiveCoral = Color(red: 0.92, green: 0.34, blue: 0.42)
    static let warmSurface = Color(
        uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor.secondarySystemGroupedBackground
                : UIColor(red: 1.0, green: 0.96, blue: 0.94, alpha: 1.0)
        }
    )
    static let cardStroke = Color.primary.opacity(0.08)
    static let cardShadow = Color.black.opacity(0.08)

    static var coralGradient: LinearGradient {
        LinearGradient(
            colors: [coralStart, coralEnd],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}
