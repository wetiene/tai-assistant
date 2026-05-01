import UIKit

/// Resizes, re-encodes as JPEG, and strips EXIF by rendering to a new bitmap before compression.
enum CheckInPhotoUploadPreprocessor {
    /// Longest edge cap (points / pixels at scale 1).
    private static let maxLongestSide: CGFloat = 1568
    /// Initial quality in the 0.7–0.75 range; may be reduced to meet byte budget.
    private static let initialJPEGQuality: CGFloat = 0.72
    private static let minJPEGQuality: CGFloat = 0.48
    private static let qualityStep: CGFloat = 0.04
    /// Binary JPEG budget so base64 + JSON framing stays comfortably under typical ~500 KB HTTP bodies.
    private static let targetMaxJPEGBytes = 370_000

    struct EncodingResult {
        let jpegData: Data
        let originalByteCount: Int
        let preparedByteCount: Int
        let encodeSeconds: TimeInterval
    }

    /// Used when capturing a photo for check-in (same rules as upload path).
    static func prepareMealUploadJPEG(from image: UIImage) -> Data? {
        guard let normalized = normalizedUpright(image) else { return nil }
        return encodeJPEGMeetingBudget(scaledImage: resizedIfNeeded(normalized))
    }

    /// Full metrics for logging plus upload-ready JPEG.
    static func prepareMealUploadJPEGWithMetrics(fromOriginalJPEGData photoData: Data) -> EncodingResult? {
        let originalByteCount = photoData.count
        let t0 = Date()
        guard let image = UIImage(data: photoData) else { return nil }
        guard let jpegData = prepareMealUploadJPEG(from: image) else { return nil }
        let elapsed = Date().timeIntervalSince(t0)
        return EncodingResult(
            jpegData: jpegData,
            originalByteCount: originalByteCount,
            preparedByteCount: jpegData.count,
            encodeSeconds: elapsed
        )
    }

    private static func normalizedUpright(_ image: UIImage) -> UIImage? {
        if image.imageOrientation == .up { return image }
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = image.scale
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: image.size, format: format)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: image.size))
        }
    }

    private static func resizedIfNeeded(_ image: UIImage) -> UIImage {
        resizeToMaxLongestPixelEdge(image, maxPixels: maxLongestSide)
    }

    private static func encodeJPEGMeetingBudget(scaledImage: UIImage) -> Data? {
        var working = scaledImage
        var sideLimit = maxLongestSide
        for _ in 0 ..< 5 {
            var q = initialJPEGQuality
            while q >= minJPEGQuality - 0.001 {
                if let data = working.jpegData(compressionQuality: q), data.count <= targetMaxJPEGBytes {
                    return data
                }
                q -= qualityStep
            }
            sideLimit *= 0.88
            guard sideLimit >= 640 else { break }
            working = resizeToMaxLongestPixelEdge(working, maxPixels: sideLimit)
        }
        return working.jpegData(compressionQuality: minJPEGQuality)
    }

    /// Scales so the longest edge in **pixels** is at most `maxPixels` (new image uses scale 1).
    private static func resizeToMaxLongestPixelEdge(_ image: UIImage, maxPixels: CGFloat) -> UIImage {
        let pxW = image.size.width * image.scale
        let pxH = image.size.height * image.scale
        guard pxW > 0, pxH > 0 else { return image }
        let longestPx = max(pxW, pxH)
        guard longestPx > maxPixels else { return image }
        let factor = maxPixels / longestPx
        let newW = max(1, (pxW * factor).rounded(.down))
        let newH = max(1, (pxH * factor).rounded(.down))
        let newSize = CGSize(width: newW, height: newH)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: newSize, format: format)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }
}
