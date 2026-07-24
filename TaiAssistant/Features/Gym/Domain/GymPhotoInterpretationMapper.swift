import Foundation

enum GymPhotoInterpretationMapper {
    static let minimumExerciseConfidence = 0.45
    static let minimumWeightConfidence = 0.55
    static let exerciseAmbiguityGap = 0.12

    struct ExerciseResolution: Equatable, Sendable {
        var detectedExerciseID: String?
        var detectedExerciseName: String?
        var requiresExerciseSelection: Bool
        var selectableCandidates: [GymExerciseCandidateSnapshot]
    }

    static func map(
        _ response: AIInterpretGymPhotoResponse,
        allowedExerciseIDs: Set<String>
    ) -> GymPhotoInterpretationSnapshot {
        let filteredCandidates = response.exerciseCandidates
            .filter { allowedExerciseIDs.contains($0.exerciseID) }
            .map {
                GymExerciseCandidateSnapshot(
                    exerciseID: $0.exerciseID,
                    displayName: GymExerciseCatalog.displayName(for: $0.exerciseID),
                    confidence: $0.confidence,
                    reason: $0.reason
                )
            }
        return GymPhotoInterpretationSnapshot(
            exerciseCandidates: filteredCandidates,
            detectedWeight: acceptedWeightSnapshot(from: response.detectedWeight),
            limitations: response.limitations,
            requiresConfirmation: response.requiresConfirmation
        )
    }

    static func resolveExerciseMatch(
        from interpretation: GymPhotoInterpretationSnapshot
    ) -> ExerciseResolution {
        let ranked = interpretation.exerciseCandidates.sorted { $0.confidence > $1.confidence }
        guard !ranked.isEmpty else {
            return ExerciseResolution(
                detectedExerciseID: nil,
                detectedExerciseName: nil,
                requiresExerciseSelection: false,
                selectableCandidates: []
            )
        }

        let confident = ranked.filter { $0.confidence >= minimumExerciseConfidence }
        if confident.count == 1 {
            let match = confident[0]
            return ExerciseResolution(
                detectedExerciseID: match.exerciseID,
                detectedExerciseName: match.displayName,
                requiresExerciseSelection: false,
                selectableCandidates: ranked
            )
        }

        if confident.count >= 2 {
            let top = confident[0]
            let second = confident[1]
            if top.confidence - second.confidence >= exerciseAmbiguityGap {
                return ExerciseResolution(
                    detectedExerciseID: top.exerciseID,
                    detectedExerciseName: top.displayName,
                    requiresExerciseSelection: false,
                    selectableCandidates: ranked
                )
            }
            return ExerciseResolution(
                detectedExerciseID: nil,
                detectedExerciseName: nil,
                requiresExerciseSelection: true,
                selectableCandidates: confident
            )
        }

        if ranked.count == 1 {
            let only = ranked[0]
            return ExerciseResolution(
                detectedExerciseID: only.exerciseID,
                detectedExerciseName: only.displayName,
                requiresExerciseSelection: false,
                selectableCandidates: ranked
            )
        }

        return ExerciseResolution(
            detectedExerciseID: nil,
            detectedExerciseName: nil,
            requiresExerciseSelection: true,
            selectableCandidates: ranked
        )
    }

    static func resolveSuggestedWeight(
        from interpretation: GymPhotoInterpretationSnapshot,
        fallbackUnit: String
    ) -> (value: Double?, unit: String) {
        guard let detected = interpretation.detectedWeight else {
            return (nil, fallbackUnit)
        }
        return (detected.value, detected.unit)
    }

    private static func acceptedWeightSnapshot(
        from detectedWeight: AIInterpretGymDetectedWeight?
    ) -> GymDetectedWeightSnapshot? {
        guard let detectedWeight,
              detectedWeight.confidence >= minimumWeightConfidence,
              detectedWeight.value > 0
        else { return nil }
        return GymDetectedWeightSnapshot(
            value: detectedWeight.value,
            unit: detectedWeight.unit,
            confidence: detectedWeight.confidence,
            reason: detectedWeight.reason
        )
    }
}
