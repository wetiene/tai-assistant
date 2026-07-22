import Foundation

enum GymPlanReference: Equatable, Sendable, Hashable {
    case starter(GymProgramTemplateID)
    case custom(UUID)

    var storageKey: String {
        switch self {
        case .starter(let id):
            return "starter:\(id.rawValue)"
        case .custom(let id):
            return "custom:\(id.uuidString)"
        }
    }

    var isStarter: Bool {
        if case .starter = self { return true }
        return false
    }

    static func decode(storageKey: String) -> GymPlanReference? {
        if storageKey.hasPrefix("starter:") {
            let raw = String(storageKey.dropFirst("starter:".count))
            guard let id = GymProgramTemplateID(rawValue: raw) else { return nil }
            return .starter(id)
        }
        if storageKey.hasPrefix("custom:") {
            let raw = String(storageKey.dropFirst("custom:".count))
            guard let id = UUID(uuidString: raw) else { return nil }
            return .custom(id)
        }
        if let legacy = GymProgramTemplateID(rawValue: storageKey) {
            return .starter(legacy)
        }
        return nil
    }
}

extension GymPlanReference: Codable {
    private enum CodingKeys: String, CodingKey {
        case kind
        case templateID
        case planID
    }

    private enum Kind: String, Codable {
        case starter
        case custom
    }

    init(from decoder: Decoder) throws {
        if let single = try? decoder.singleValueContainer(),
           let raw = try? single.decode(String.self),
           let decoded = GymPlanReference.decode(storageKey: raw)
        {
            self = decoded
            return
        }

        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(Kind.self, forKey: .kind)
        switch kind {
        case .starter:
            let templateID = try container.decode(GymProgramTemplateID.self, forKey: .templateID)
            self = .starter(templateID)
        case .custom:
            let planID = try container.decode(UUID.self, forKey: .planID)
            self = .custom(planID)
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .starter(let templateID):
            try container.encode(Kind.starter, forKey: .kind)
            try container.encode(templateID, forKey: .templateID)
        case .custom(let planID):
            try container.encode(Kind.custom, forKey: .kind)
            try container.encode(planID, forKey: .planID)
        }
    }
}

struct GymPlanWorkoutTarget: Equatable, Sendable, Hashable {
    var reference: GymPlanReference
    var sectionIndex: Int
}

struct GymPlanSummary: Identifiable, Equatable, Sendable {
    var id: String { reference.storageKey }
    var reference: GymPlanReference
    var title: String
    var exerciseCount: Int
    var sectionCount: Int
    var workingSetsPerExercise: Int
    var repRangeLabel: String
    var isStarter: Bool
    var isCustom: Bool
    var isEditedStarter: Bool
    var lifecycleStatus: GymPlanLifecycleStatus
    var importedAt: Date?
    var suggestedDurationWeeks: Int?
    var sectionNames: [String]
}

struct GymPlanDraft: Equatable, Sendable {
    var reference: GymPlanReference?
    var title: String
    var sections: [GymPlanSectionDraft]
    var prescription: GymProgramPrescription
    var generalInstructions: [String]
    var suggestedDurationWeeks: Int?
    var lifecycleStatus: GymPlanLifecycleStatus
    var importedAt: Date?

    var exercises: [GymPlannedExercise] {
        get {
            sections
                .sorted { $0.orderIndex < $1.orderIndex }
                .flatMap(\.exercises)
                .sorted { $0.orderIndex < $1.orderIndex }
        }
        set {
            guard let first = sections.first else {
                sections = [
                    GymPlanSectionDraft(
                        name: "Workout",
                        orderIndex: 0,
                        exercises: newValue,
                        prescription: nil
                    )
                ]
                return
            }
            var updated = first
            updated.exercises = newValue
            if sections.count == 1 {
                sections = [updated]
            } else {
                sections[0] = updated
            }
        }
    }

    static func blank() -> GymPlanDraft {
        GymPlanDraft(
            reference: nil,
            title: "New Workout Plan",
            sections: [
                GymPlanSectionDraft(name: "Workout", orderIndex: 0, exercises: [], prescription: nil)
            ],
            prescription: .default,
            generalInstructions: [],
            suggestedDurationWeeks: nil,
            lifecycleStatus: .inactive,
            importedAt: nil
        )
    }

    static func fromImport(_ importDraft: GymPlanImportDraft) -> GymPlanDraft {
        importDraft.asPlanDraft()
    }

    mutating func moveExercises(inSection sectionIndex: Int, from source: IndexSet, to destination: Int) {
        guard sections.indices.contains(sectionIndex) else { return }
        sections[sectionIndex].exercises.move(fromOffsets: source, toOffset: destination)
        sections[sectionIndex].reindexExercises()
    }

    mutating func removeExercises(inSection sectionIndex: Int, at offsets: IndexSet) {
        guard sections.indices.contains(sectionIndex) else { return }
        sections[sectionIndex].exercises.remove(atOffsets: offsets)
        sections[sectionIndex].reindexExercises()
    }

    mutating func appendExercise(_ exerciseID: GymExerciseID, toSection sectionIndex: Int = 0) {
        guard sections.indices.contains(sectionIndex) else { return }
        let definition = GymExerciseCatalog.definition(for: exerciseID)
        sections[sectionIndex].exercises.append(GymPlannedExercise(definition: definition, orderIndex: sections[sectionIndex].exercises.count))
        sections[sectionIndex].reindexExercises()
    }

    mutating func moveExercises(from source: IndexSet, to destination: Int) {
        moveExercises(inSection: 0, from: source, to: destination)
    }

    mutating func removeExercises(at offsets: IndexSet) {
        removeExercises(inSection: 0, at: offsets)
    }

    mutating func reindexExerciseOrder() {
        for index in sections.indices {
            sections[index].reindexExercises()
        }
    }
}

struct GymResolvablePlan: Equatable, Sendable {
    var reference: GymPlanReference
    var title: String
    var sectionName: String?
    var sectionIndex: Int
    var exercises: [GymPlannedExercise]
    var prescription: GymProgramPrescription
    var generalInstructions: [String]

    var candidateExerciseIDs: [GymExerciseID] {
        exercises.flatMap(\.candidateIDs)
    }

    var candidateStableIDs: [String] {
        exercises.flatMap(\.candidateStableIDs)
    }
}

enum GymPlanRepositoryError: Error, Equatable {
    case planNotFound
    case cannotDeleteStarter
    case invalidDraft
    case sectionNotFound
}
