import Foundation

/// Stable exercise identifiers shared by templates, AI candidates, and persistence.
enum GymExerciseID: String, Codable, CaseIterable, Sendable {
    case supineChestPress
    case seatedShoulderPress
    case reverseGripLatPulldown
    case assistedChinUp
    case seatedRow
    case bicepCurl
    case tricepPushdown
    case legPress
    case kettlebellSquats
    case stationaryLunges
    case gluteTrainer
    case legExtension
    case legCurl

    var displayName: String {
        switch self {
        case .supineChestPress: return "Supine Chest Press"
        case .seatedShoulderPress: return "Seated Shoulder Press"
        case .reverseGripLatPulldown: return "Reverse Grip Lat Pulldown"
        case .assistedChinUp: return "Assisted Chin-Up"
        case .seatedRow: return "Seated Row"
        case .bicepCurl: return "Bicep Curl"
        case .tricepPushdown: return "Tricep Pushdown"
        case .legPress: return "Leg Press"
        case .kettlebellSquats: return "Kettlebell Squats"
        case .stationaryLunges: return "Stationary Lunges"
        case .gluteTrainer: return "Glute Trainer"
        case .legExtension: return "Leg Extension"
        case .legCurl: return "Leg Curl"
        }
    }
}

struct GymExerciseDefinition: Codable, Equatable, Sendable, Identifiable {
    var id: String { exerciseID.rawValue }
    let exerciseID: GymExerciseID
    let displayName: String
    let isOptional: Bool
    /// Alternate exercise IDs the user may substitute (e.g. chin-up for lat pulldown).
    let alternativeExerciseIDs: [GymExerciseID]

    init(
        exerciseID: GymExerciseID,
        isOptional: Bool = false,
        alternativeExerciseIDs: [GymExerciseID] = []
    ) {
        self.exerciseID = exerciseID
        self.displayName = exerciseID.displayName
        self.isOptional = isOptional
        self.alternativeExerciseIDs = alternativeExerciseIDs
    }

    var candidateIDs: [GymExerciseID] {
        [exerciseID] + alternativeExerciseIDs
    }
}

enum GymExerciseCatalog {
    static func definition(for id: GymExerciseID) -> GymExerciseDefinition {
        allDefinitions[id] ?? GymExerciseDefinition(exerciseID: id)
    }

    static func displayName(for exerciseID: String) -> String {
        GymExerciseID(rawValue: exerciseID)?.displayName ?? exerciseID
    }

    private static let allDefinitions: [GymExerciseID: GymExerciseDefinition] = {
        let defs: [GymExerciseDefinition] = [
            GymExerciseDefinition(exerciseID: .supineChestPress),
            GymExerciseDefinition(exerciseID: .seatedShoulderPress),
            GymExerciseDefinition(
                exerciseID: .reverseGripLatPulldown,
                alternativeExerciseIDs: [.assistedChinUp]
            ),
            GymExerciseDefinition(exerciseID: .assistedChinUp),
            GymExerciseDefinition(exerciseID: .seatedRow),
            GymExerciseDefinition(exerciseID: .bicepCurl, isOptional: true),
            GymExerciseDefinition(exerciseID: .tricepPushdown, isOptional: true),
            GymExerciseDefinition(exerciseID: .legPress),
            GymExerciseDefinition(exerciseID: .kettlebellSquats),
            GymExerciseDefinition(exerciseID: .stationaryLunges),
            GymExerciseDefinition(exerciseID: .gluteTrainer),
            GymExerciseDefinition(exerciseID: .legExtension, isOptional: true),
            GymExerciseDefinition(exerciseID: .legCurl, isOptional: true),
        ]
        return Dictionary(uniqueKeysWithValues: defs.map { ($0.exerciseID, $0) })
    }()
}
