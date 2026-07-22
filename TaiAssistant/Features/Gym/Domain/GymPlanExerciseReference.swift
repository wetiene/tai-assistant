import Foundation

/// Stable exercise identity for imported and catalog exercises.
struct GymPlanExerciseReference: Codable, Equatable, Sendable, Hashable {
    var catalogExerciseID: String?
    var customName: String
    var sourceName: String?

    var displayName: String { customName }

    var stableID: String {
        if let catalogExerciseID, !catalogExerciseID.isEmpty {
            return catalogExerciseID
        }
        let slug = customName
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: "_")
        return slug.isEmpty ? "custom:exercise" : "custom:\(slug)"
    }

    var catalogID: GymExerciseID? {
        catalogExerciseID.flatMap(GymExerciseID.init(rawValue:))
    }

    static func fromCatalog(_ id: GymExerciseID, sourceName: String? = nil) -> GymPlanExerciseReference {
        GymPlanExerciseReference(
            catalogExerciseID: id.rawValue,
            customName: id.displayName,
            sourceName: sourceName ?? id.displayName
        )
    }

    static func custom(name: String, sourceName: String? = nil) -> GymPlanExerciseReference {
        GymPlanExerciseReference(
            catalogExerciseID: nil,
            customName: name,
            sourceName: sourceName ?? name
        )
    }
}
