import Foundation

enum StrengthWeightIncrement {
  private static let lowerBodyExerciseIDs: Set<String> = [
    GymExerciseID.legPress.rawValue,
    GymExerciseID.kettlebellSquats.rawValue,
    GymExerciseID.stationaryLunges.rawValue,
    GymExerciseID.gluteTrainer.rawValue,
    GymExerciseID.legExtension.rawValue,
    GymExerciseID.legCurl.rawValue,
  ]

  static func defaultIncrement(for exerciseID: String) -> Double {
    lowerBodyExerciseIDs.contains(exerciseID) ? 5 : 2.5
  }

  static func nextWeight(from current: Double, exerciseID: String) -> Double {
    let increment = defaultIncrement(for: exerciseID)
    return roundedWeight(current + increment)
  }

  static func previousWeight(from current: Double, exerciseID: String) -> Double {
    let increment = defaultIncrement(for: exerciseID)
    return roundedWeight(max(0, current - increment))
  }

  private static func roundedWeight(_ value: Double) -> Double {
    (value * 100).rounded() / 100
  }
}
