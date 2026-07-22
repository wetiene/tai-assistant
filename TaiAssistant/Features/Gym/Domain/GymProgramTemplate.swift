import Foundation

/// Reusable program templates — architecture supports additional templates without code changes to the capability.
enum GymProgramTemplateID: String, Codable, CaseIterable, Sendable {
    case upperBody
    case lowerBody

    var title: String {
        switch self {
        case .upperBody: return "Upper Body"
        case .lowerBody: return "Lower Body"
        }
    }
}

struct GymProgramPrescription: Codable, Equatable, Sendable {
    var workingSetsPerExercise: Int
    var repRangeLower: Int
    var repRangeUpper: Int
    var coachingNote: String

    static let `default` = GymProgramPrescription(
        workingSetsPerExercise: 3,
        repRangeLower: 8,
        repRangeUpper: 12,
        coachingNote: "Work close to fatigue with good technique."
    )

    var repRangeLabel: String {
        "\(repRangeLower)–\(repRangeUpper) reps"
    }
}

struct GymPlannedExercise: Codable, Equatable, Sendable, Identifiable {
    var reference: GymPlanExerciseReference
    var isOptional: Bool
    var alternativeExerciseIDs: [GymExerciseID]
    var orderIndex: Int
    var targetSets: Int?
    var minimumRepetitions: Int?
    var maximumRepetitions: Int?
    var notes: String?
    var matchConfidence: Double?
    var isUnresolved: Bool

    var id: String { reference.stableID }

    var exerciseID: GymExerciseID? { reference.catalogID }
    var displayName: String { reference.displayName }
    var sourceName: String? { reference.sourceName }

    init(
        reference: GymPlanExerciseReference,
        isOptional: Bool = false,
        alternativeExerciseIDs: [GymExerciseID] = [],
        orderIndex: Int,
        targetSets: Int? = nil,
        minimumRepetitions: Int? = nil,
        maximumRepetitions: Int? = nil,
        notes: String? = nil,
        matchConfidence: Double? = nil,
        isUnresolved: Bool = false
    ) {
        self.reference = reference
        self.isOptional = isOptional
        self.alternativeExerciseIDs = alternativeExerciseIDs
        self.orderIndex = orderIndex
        self.targetSets = targetSets
        self.minimumRepetitions = minimumRepetitions
        self.maximumRepetitions = maximumRepetitions
        self.notes = notes
        self.matchConfidence = matchConfidence
        self.isUnresolved = isUnresolved
    }

    init(definition: GymExerciseDefinition, orderIndex: Int) {
        self.init(
            reference: .fromCatalog(definition.exerciseID),
            isOptional: definition.isOptional,
            alternativeExerciseIDs: definition.alternativeExerciseIDs,
            orderIndex: orderIndex
        )
    }

    var candidateIDs: [GymExerciseID] {
        if let catalogID = reference.catalogID {
            return [catalogID] + alternativeExerciseIDs
        }
        return alternativeExerciseIDs
    }

    var candidateStableIDs: [String] {
        if let catalogID = reference.catalogID {
            return [catalogID.rawValue] + alternativeExerciseIDs.map(\.rawValue)
        }
        return [reference.stableID]
    }

    func effectiveSets(planPrescription: GymProgramPrescription) -> Int {
        targetSets ?? planPrescription.workingSetsPerExercise
    }

    func effectiveRepRange(planPrescription: GymProgramPrescription) -> (lower: Int, upper: Int) {
        (
            minimumRepetitions ?? planPrescription.repRangeLower,
            maximumRepetitions ?? planPrescription.repRangeUpper
        )
    }

    private enum CodingKeys: String, CodingKey {
        case reference, isOptional, alternativeExerciseIDs, orderIndex
        case targetSets, minimumRepetitions, maximumRepetitions, notes
        case matchConfidence, isUnresolved
        case exerciseID, displayName
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let decodedReference = try container.decodeIfPresent(GymPlanExerciseReference.self, forKey: .reference) {
            reference = decodedReference
        } else {
            let legacyID = try container.decode(GymExerciseID.self, forKey: .exerciseID)
            let legacyName = try container.decode(String.self, forKey: .displayName)
            reference = GymPlanExerciseReference(
                catalogExerciseID: legacyID.rawValue,
                customName: legacyName,
                sourceName: legacyName
            )
        }
        isOptional = try container.decodeIfPresent(Bool.self, forKey: .isOptional) ?? false
        alternativeExerciseIDs = try container.decodeIfPresent([GymExerciseID].self, forKey: .alternativeExerciseIDs) ?? []
        orderIndex = try container.decode(Int.self, forKey: .orderIndex)
        targetSets = try container.decodeIfPresent(Int.self, forKey: .targetSets)
        minimumRepetitions = try container.decodeIfPresent(Int.self, forKey: .minimumRepetitions)
        maximumRepetitions = try container.decodeIfPresent(Int.self, forKey: .maximumRepetitions)
        notes = try container.decodeIfPresent(String.self, forKey: .notes)
        matchConfidence = try container.decodeIfPresent(Double.self, forKey: .matchConfidence)
        isUnresolved = try container.decodeIfPresent(Bool.self, forKey: .isUnresolved) ?? false
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(reference, forKey: .reference)
        try container.encode(isOptional, forKey: .isOptional)
        try container.encode(alternativeExerciseIDs, forKey: .alternativeExerciseIDs)
        try container.encode(orderIndex, forKey: .orderIndex)
        try container.encodeIfPresent(targetSets, forKey: .targetSets)
        try container.encodeIfPresent(minimumRepetitions, forKey: .minimumRepetitions)
        try container.encodeIfPresent(maximumRepetitions, forKey: .maximumRepetitions)
        try container.encodeIfPresent(notes, forKey: .notes)
        try container.encodeIfPresent(matchConfidence, forKey: .matchConfidence)
        try container.encode(isUnresolved, forKey: .isUnresolved)
    }
}

struct GymWorkoutTemplate: Codable, Equatable, Sendable {
    let templateID: GymProgramTemplateID
    let title: String
    let exercises: [GymPlannedExercise]
    let prescription: GymProgramPrescription

    var candidateExerciseIDs: [GymExerciseID] {
        exercises.flatMap(\.candidateIDs)
    }
}

enum GymProgramTemplateLibrary {
    static func template(for id: GymProgramTemplateID) -> GymWorkoutTemplate {
        switch id {
        case .upperBody: return upperBody
        case .lowerBody: return lowerBody
        }
    }

    static func resolvableStarter(_ id: GymProgramTemplateID) -> GymResolvablePlan {
        let template = template(for: id)
        return GymResolvablePlan(
            reference: .starter(id),
            title: template.title,
            sectionName: template.title,
            sectionIndex: 0,
            exercises: template.exercises,
            prescription: template.prescription,
            generalInstructions: []
        )
    }

    static func starterSummary(for id: GymProgramTemplateID) -> GymPlanSummary {
        let template = template(for: id)
        return GymPlanSummary(
            reference: .starter(id),
            title: template.title,
            exerciseCount: template.exercises.count,
            sectionCount: 1,
            workingSetsPerExercise: template.prescription.workingSetsPerExercise,
            repRangeLabel: template.prescription.repRangeLabel,
            isStarter: true,
            isCustom: false,
            isEditedStarter: false,
            lifecycleStatus: .inactive,
            importedAt: nil,
            suggestedDurationWeeks: nil,
            sectionNames: [template.title]
        )
    }

    static let upperBody = GymWorkoutTemplate(
        templateID: .upperBody,
        title: GymProgramTemplateID.upperBody.title,
        exercises: [
            GymExerciseDefinition(exerciseID: .supineChestPress),
            GymExerciseDefinition(exerciseID: .seatedShoulderPress),
            GymExerciseDefinition(
                exerciseID: .reverseGripLatPulldown,
                alternativeExerciseIDs: [.assistedChinUp]
            ),
            GymExerciseDefinition(exerciseID: .seatedRow),
            GymExerciseDefinition(exerciseID: .bicepCurl, isOptional: true),
            GymExerciseDefinition(exerciseID: .tricepPushdown, isOptional: true),
        ].enumerated().map { GymPlannedExercise(definition: $0.element, orderIndex: $0.offset) },
        prescription: .default
    )

    static let lowerBody = GymWorkoutTemplate(
        templateID: .lowerBody,
        title: GymProgramTemplateID.lowerBody.title,
        exercises: [
            GymExerciseDefinition(exerciseID: .legPress),
            GymExerciseDefinition(exerciseID: .kettlebellSquats),
            GymExerciseDefinition(exerciseID: .stationaryLunges),
            GymExerciseDefinition(exerciseID: .gluteTrainer),
            GymExerciseDefinition(exerciseID: .legExtension, isOptional: true),
            GymExerciseDefinition(exerciseID: .legCurl, isOptional: true),
        ].enumerated().map { GymPlannedExercise(definition: $0.element, orderIndex: $0.offset) },
        prescription: .default
    )
}
