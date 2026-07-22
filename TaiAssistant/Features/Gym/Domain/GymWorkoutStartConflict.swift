import Foundation

/// Presented when the user tries to start a workout while another session is in progress.
struct GymWorkoutStartConflict: Equatable, Sendable {
    var activeSessionTitle: String
    var activePlanReference: GymPlanReference
    var requestedPlanReference: GymPlanReference
    var requestedPlanTitle: String
    var requestedWorkoutTarget: GymPlanWorkoutTarget
}

enum GymWorkoutStartConflictResolution: Equatable, Sendable {
    case resumeCurrent
    case finishCurrentAndStartSelected
    case discardCurrentAndStartSelected
    case cancel
}
