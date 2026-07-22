import Foundation

/// Deterministic workout duration estimate from prescribed volume and rest assumptions.
enum StrengthWorkoutDurationEstimator {
  /// Time to complete one working set including setup at the station.
  static let workingSetExecutionSeconds: TimeInterval = 45
  /// Rest between working sets of the same exercise.
  static let restBetweenWorkingSetsSeconds: TimeInterval = 90
  /// Time to move between exercises (equipment change, logging).
  static let exerciseTransitionSeconds: TimeInterval = 120
  /// Minimum displayed duration for any non-empty session.
  static let minimumDurationMinutes = 20

  static func estimatedDurationMinutes(for plan: GymResolvablePlan) -> Int {
    let exerciseDurations = plan.exercises.map { exerciseDurationSeconds(for: $0, prescription: plan.prescription) }
    guard !exerciseDurations.isEmpty else { return minimumDurationMinutes }

    let workingAndRest = exerciseDurations.reduce(0, +)
    let transitions = TimeInterval(max(0, plan.exercises.count - 1)) * exerciseTransitionSeconds
    let totalSeconds = workingAndRest + transitions
    return max(minimumDurationMinutes, Int(ceil(totalSeconds / 60)))
  }

  static func exerciseDurationSeconds(
    for exercise: GymPlannedExercise,
    prescription: GymProgramPrescription
  ) -> TimeInterval {
    let workingSets = exercise.effectiveSets(planPrescription: prescription)
    guard workingSets > 0 else { return 0 }

    let execution = TimeInterval(workingSets) * workingSetExecutionSeconds
    let rest = TimeInterval(max(0, workingSets - 1)) * restBetweenWorkingSetsSeconds
    return execution + rest
  }
}
