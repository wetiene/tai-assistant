import Foundation
import UIKit

enum StrengthConversationTestFixtures {
    /// Valid tiny JPEG payloads for deterministic multi-photo UI and unit tests.
    static let multiPhotoEvidence: [Data] = [
        syntheticJPEG(seed: 1),
        syntheticJPEG(seed: 2),
    ]

    private static func syntheticJPEG(seed: UInt8) -> Data {
        let side = CGFloat(24 + Int(seed) * 4)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format)
        let image = renderer.image { context in
            UIColor(
                red: CGFloat(seed) / 255.0,
                green: 0.35,
                blue: 0.65,
                alpha: 1
            ).setFill()
            context.fill(CGRect(x: 0, y: 0, width: side, height: side))
        }
        return image.jpegData(compressionQuality: 0.85) ?? Data([0xFF, 0xD8, 0xFF, 0xD9])
    }
}
