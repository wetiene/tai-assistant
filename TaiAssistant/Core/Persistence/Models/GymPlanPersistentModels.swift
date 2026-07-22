import Foundation
import SwiftData

@Model
final class GymWorkoutPlan {
    @Attribute(.unique) var id: UUID
    var ownerID: String
    var title: String
    /// When set, this row overrides the built-in starter template for the owner.
    var starterTemplateID: String?
    var exercisesJSON: Data
    var prescriptionJSON: Data
    var createdAt: Date
    var updatedAt: Date
    /// `draft` | `active` | `archived` | `inactive`
    var lifecycleStatusRaw: String = GymPlanLifecycleStatus.inactive.rawValue
    var importedAt: Date?
    var suggestedDurationWeeks: Int?
    /// Structured sections + metadata (`GymPlanPersistedContent`).
    var contentJSON: Data?
    var generalInstructionsJSON: Data?

    init(
        id: UUID = UUID(),
        ownerID: String,
        title: String,
        starterTemplateID: String? = nil,
        exercisesJSON: Data,
        prescriptionJSON: Data,
        createdAt: Date = .now,
        updatedAt: Date = .now,
        lifecycleStatusRaw: String = GymPlanLifecycleStatus.inactive.rawValue,
        importedAt: Date? = nil,
        suggestedDurationWeeks: Int? = nil,
        contentJSON: Data? = nil,
        generalInstructionsJSON: Data? = nil
    ) {
        self.id = id
        self.ownerID = ownerID
        self.title = title
        self.starterTemplateID = starterTemplateID
        self.exercisesJSON = exercisesJSON
        self.prescriptionJSON = prescriptionJSON
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.lifecycleStatusRaw = lifecycleStatusRaw
        self.importedAt = importedAt
        self.suggestedDurationWeeks = suggestedDurationWeeks
        self.contentJSON = contentJSON
        self.generalInstructionsJSON = generalInstructionsJSON
    }

    var lifecycleStatus: GymPlanLifecycleStatus {
        get { GymPlanLifecycleStatus(rawValue: lifecycleStatusRaw) ?? .inactive }
        set { lifecycleStatusRaw = newValue.rawValue }
    }
}

struct GymPlanPersistedContent: Codable, Equatable, Sendable {
    var sections: [GymPlanSectionDraft]
    var prescription: GymProgramPrescription
    var generalInstructions: [String]
    var suggestedDurationWeeks: Int?
}

enum GymPlanPersistenceCodec {
    static func encodeExercises(_ exercises: [GymPlannedExercise]) throws -> Data {
        try JSONEncoder().encode(exercises)
    }

    static func decodeExercises(_ data: Data) throws -> [GymPlannedExercise] {
        try JSONDecoder().decode([GymPlannedExercise].self, from: data)
    }

    static func encodePrescription(_ prescription: GymProgramPrescription) throws -> Data {
        try JSONEncoder().encode(prescription)
    }

    static func decodePrescription(_ data: Data) throws -> GymProgramPrescription {
        try JSONDecoder().decode(GymProgramPrescription.self, from: data)
    }

    static func encodeContent(_ content: GymPlanPersistedContent) throws -> Data {
        try JSONEncoder().encode(content)
    }

    static func decodeContent(_ data: Data) throws -> GymPlanPersistedContent {
        try JSONDecoder().decode(GymPlanPersistedContent.self, from: data)
    }

    static func encodeStringArray(_ values: [String]) throws -> Data {
        try JSONEncoder().encode(values)
    }

    static func decodeStringArray(_ data: Data) throws -> [String] {
        try JSONDecoder().decode([String].self, from: data)
    }

    static func content(from plan: GymWorkoutPlan) throws -> GymPlanPersistedContent {
        if let contentJSON = plan.contentJSON {
            return try decodeContent(contentJSON)
        }
        let exercises = try decodeExercises(plan.exercisesJSON)
        let prescription = try decodePrescription(plan.prescriptionJSON)
        let instructions = plan.generalInstructionsJSON.map { try? decodeStringArray($0) } ?? nil
        return GymPlanPersistedContent(
            sections: [
                GymPlanSectionDraft(
                    name: plan.title,
                    orderIndex: 0,
                    exercises: exercises,
                    prescription: nil
                )
            ],
            prescription: prescription,
            generalInstructions: instructions ?? [],
            suggestedDurationWeeks: plan.suggestedDurationWeeks
        )
    }

    static func apply(content: GymPlanPersistedContent, to plan: GymWorkoutPlan) throws {
        plan.contentJSON = try encodeContent(content)
        plan.prescriptionJSON = try encodePrescription(content.prescription)
        plan.exercisesJSON = try encodeExercises(content.sections.flatMap(\.exercises))
        plan.generalInstructionsJSON = try encodeStringArray(content.generalInstructions)
        plan.suggestedDurationWeeks = content.suggestedDurationWeeks
    }
}
