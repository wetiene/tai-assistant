import Foundation

enum GymPhotoInterpretationMapper {
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
            detectedWeight: response.detectedWeight.map {
                GymDetectedWeightSnapshot(
                    value: $0.value,
                    unit: $0.unit,
                    confidence: $0.confidence,
                    reason: $0.reason
                )
            },
            limitations: response.limitations,
            requiresConfirmation: response.requiresConfirmation
        )
    }
}
