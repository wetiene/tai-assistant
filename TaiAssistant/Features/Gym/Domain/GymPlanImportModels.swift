import Foundation

enum GymPlanLifecycleStatus: String, Codable, Sendable, CaseIterable {
    case draft
    case active
    case archived
    case inactive
}

enum GymPlanSaveActivation: Equatable, Sendable {
    case makeActive
    case saveOnly
}

enum GymPlanImportSourceType: String, Codable, Sendable {
    case text
    case image
    case pdf
}

/// Transient import source — never persisted by default.
struct GymPlanImportSource: Equatable, Sendable {
    var type: GymPlanImportSourceType
    var text: String?
    var attachmentData: Data?
    var mimeType: String?

    static func pastedText(_ text: String) -> GymPlanImportSource {
        GymPlanImportSource(type: .text, text: text, attachmentData: nil, mimeType: nil)
    }

    static func image(_ data: Data, mimeType: String) -> GymPlanImportSource {
        GymPlanImportSource(type: .image, text: nil, attachmentData: data, mimeType: mimeType)
    }

    static func pdf(_ data: Data) -> GymPlanImportSource {
        GymPlanImportSource(type: .pdf, text: nil, attachmentData: data, mimeType: "application/pdf")
    }

    mutating func clearTransientPayload() {
        text = nil
        attachmentData = nil
        mimeType = nil
    }
}

struct GymPlanSectionDraft: Codable, Equatable, Sendable, Identifiable {
    var id: String { "\(orderIndex)-\(name)" }
    var name: String
    var orderIndex: Int
    var exercises: [GymPlannedExercise]
    var prescription: GymProgramPrescription?

    mutating func reindexExercises() {
        exercises = exercises.enumerated().map { index, exercise in
            var updated = exercise
            updated.orderIndex = index
            return updated
        }
    }
}

/// In-memory draft produced by AI import — not persisted until explicit save.
struct GymPlanImportDraft: Equatable, Sendable, Identifiable {
    var id: UUID
    var title: String
    var sections: [GymPlanSectionDraft]
    var prescription: GymProgramPrescription
    var generalInstructions: [String]
    var suggestedDurationWeeks: Int?
    var unresolvedItems: [GymPlanImportUnresolvedItem]
    var warnings: [String]
    var confidence: String
    var requiresUserConfirmation: Bool
    var sourceType: GymPlanImportSourceType

    var exerciseCount: Int {
        sections.reduce(0) { $0 + $1.exercises.count }
    }

    func asPlanDraft(reference: GymPlanReference? = nil, lifecycleStatus: GymPlanLifecycleStatus = .inactive) -> GymPlanDraft {
        GymPlanDraft(
            reference: reference,
            title: title,
            sections: sections,
            prescription: prescription,
            generalInstructions: generalInstructions,
            suggestedDurationWeeks: suggestedDurationWeeks,
            lifecycleStatus: lifecycleStatus,
            importedAt: .now
        )
    }
}

struct GymPlanImportUnresolvedItem: Codable, Equatable, Sendable, Identifiable {
    var id: String { sourceText }
    var sourceText: String
    var reason: String
    var suggestedMatches: [GymPlanImportMatchSuggestion]
}

struct GymPlanImportMatchSuggestion: Codable, Equatable, Sendable {
    var exerciseID: String
    var confidence: Double
}

struct GymPlanLibrarySnapshot: Equatable, Sendable {
    var activePlan: GymPlanSummary?
    var previousPlans: [GymPlanSummary]
    var hasUserPlans: Bool
}

/// Representative trainer program fixture for tests and mock interpretation.
enum GymTrainerProgramFixture {
    static let pastedText = """
    Upper Body:
    - Supine Chest Press
    - Seated Shoulder Press
    - Reverse Grip Lat Pulldown
    - Seated Row
    - optional Bicep Curl
    - optional Tricep Pushdown

    Lower Body:
    - Leg Press
    - Kettlebell Squats
    - Stationary Lunges
    - Glute Trainer
    - optional Leg Extension
    - optional Leg Curl

    3 sets
    8-12 repetitions
    Work close to fatigue while maintaining good form.
    """

    static let expectedSectionNames = ["Upper Body", "Lower Body"]
}
