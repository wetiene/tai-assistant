import Foundation

enum GymPlanImportImageSupport {
    static let maxByteCount = 4_000_000

    static let supportedMimeTypes: Set<String> = [
        "image/jpeg",
        "image/png",
        "image/webp",
    ]

    enum ValidationError: Equatable, LocalizedError {
        case empty
        case tooLarge
        case unsupportedFormat

        var errorDescription: String? {
            switch self {
            case .empty:
                return "Couldn’t read this image."
            case .tooLarge:
                return "This image is too large to analyse."
            case .unsupportedFormat:
                return "This image format isn’t supported. Use JPEG, PNG, or WebP."
            }
        }
    }

    static func mimeType(for data: Data) -> String? {
        guard !data.isEmpty else { return nil }
        if data.starts(with: [0xFF, 0xD8, 0xFF]) { return "image/jpeg" }
        if data.starts(with: [0x89, 0x50, 0x4E, 0x47]) { return "image/png" }
        if data.starts(with: [0x52, 0x49, 0x46, 0x46]), data.count > 12,
           String(data: data[8..<12], encoding: .ascii) == "WEBP"
        {
            return "image/webp"
        }
        return nil
    }

    static func validate(data: Data) throws -> String {
        guard !data.isEmpty else { throw ValidationError.empty }
        guard data.count <= maxByteCount else { throw ValidationError.tooLarge }
        guard let mime = mimeType(for: data), supportedMimeTypes.contains(mime) else {
            throw ValidationError.unsupportedFormat
        }
        return mime
    }

    static func makeSource(from data: Data) throws -> GymPlanImportSource {
        let mime = try validate(data: data)
        return .image(data, mimeType: mime)
    }
}
