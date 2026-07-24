import Foundation

struct StrengthPhotoAssistResult: Equatable, Sendable {
    var interpretation: GymPhotoInterpretationSnapshot
    var suggestedWeight: Double?
    var weightUnit: String
    var detectedExerciseID: String?
    var detectedExerciseName: String?
    var suggestedReps: Int?
    var matchesActiveExercise: Bool
    var imageClassification: PersistedImageClassification?
}

enum StrengthGymPhotoAssistError: Error, Equatable {
    case noActiveExercise
    case interpretationFailed
}

struct StrengthGymPhotoAssistService {
    let aiService: AIService

    func interpretPhoto(
        jpeg: Data,
        session: StrengthWorkoutSession,
        localeIdentifier: String = Locale.current.identifier,
        weightUnitPreference: String? = nil
    ) async throws -> StrengthPhotoAssistResult {
        try await interpretPhotos(
            jpegs: [jpeg],
            session: session,
            localeIdentifier: localeIdentifier,
            weightUnitPreference: weightUnitPreference
        )
    }

    func interpretPhotos(
        jpegs: [Data],
        session: StrengthWorkoutSession,
        localeIdentifier: String = Locale.current.identifier,
        weightUnitPreference: String? = nil
    ) async throws -> StrengthPhotoAssistResult {
        guard !jpegs.isEmpty else {
            throw StrengthGymPhotoAssistError.interpretationFailed
        }

        let unit = weightUnitPreference ?? session.weightUnit
        let allowedExerciseIDs = Set(session.exercises.map(\.exerciseID))
        let activeExercise = session.currentExerciseInstance
        let images = jpegs.map {
            AIInterpretMealImageInput(
                base64Data: $0.base64EncodedString(),
                mimeType: "image/jpeg",
                uploadReference: nil
            )
        }
        let request = AIInterpretGymPhotoRequest(
            image: images.first,
            images: images.count > 1 ? images : nil,
            context: AIInterpretGymPhotoContext(
                localeIdentifier: localeIdentifier,
                weightUnitPreference: unit,
                plannedWorkout: AIProxyGymPlannedWorkoutContext(
                    templateID: session.planReference.storageKey,
                    title: session.title,
                    exercises: session.exercises.map {
                        AIProxyGymExerciseCandidateContext(
                            exerciseID: $0.exerciseID,
                            displayName: $0.displayName,
                            isOptional: $0.plannedExercise.isOptional
                        )
                    }
                ),
                expectedExerciseID: activeExercise?.exerciseID,
                allowedExerciseCandidates: session.exercises.map {
                    AIProxyGymExerciseCandidateContext(
                        exerciseID: $0.exerciseID,
                        displayName: $0.displayName,
                        isOptional: $0.plannedExercise.isOptional
                    )
                }
            )
        )

        let response = try await aiService.interpretGymPhoto(request: request)
        switch ImageInterpretationValidator.validateGymResponse(response) {
        case .failure(let failure):
            throw failure
        case .success(let validated):
            let interpretation = GymPhotoInterpretationMapper.map(
                validated,
                allowedExerciseIDs: allowedExerciseIDs
            )
            let exerciseMatch = GymPhotoInterpretationMapper.resolveExerciseMatch(from: interpretation)
            let resolvedWeight = GymPhotoInterpretationMapper.resolveSuggestedWeight(
                from: interpretation,
                fallbackUnit: unit
            )
            let matchesActive = activeExercise == nil
                || exerciseMatch.detectedExerciseID == nil
                || exerciseMatch.detectedExerciseID == activeExercise?.exerciseID

            let suggestedReps = session.currentSet?.suggestedReps ?? session.currentSet?.plannedReps

            return StrengthPhotoAssistResult(
                interpretation: interpretation,
                suggestedWeight: resolvedWeight.value,
                weightUnit: resolvedWeight.unit,
                detectedExerciseID: exerciseMatch.detectedExerciseID,
                detectedExerciseName: exerciseMatch.detectedExerciseName,
                suggestedReps: suggestedReps,
                matchesActiveExercise: matchesActive,
                imageClassification: PersistedImageClassification.fromGymResponse(
                    validated,
                    sourceAttachmentID: nil
                )
            )
        }
    }
}
