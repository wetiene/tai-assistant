import Foundation

struct StrengthPhotoAssistResult: Equatable, Sendable {
    var interpretation: GymPhotoInterpretationSnapshot
    var suggestedWeight: Double?
    var weightUnit: String
    var detectedExerciseID: String?
    var detectedExerciseName: String?
    var matchesActiveExercise: Bool
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
        guard let exercise = session.currentExerciseInstance else {
            throw StrengthGymPhotoAssistError.noActiveExercise
        }

        let unit = weightUnitPreference ?? session.weightUnit
        let allowedExerciseIDs = Set(session.exercises.map(\.exerciseID))
        let request = AIInterpretGymPhotoRequest(
            image: AIInterpretMealImageInput(
                base64Data: jpeg.base64EncodedString(),
                mimeType: "image/jpeg",
                uploadReference: nil
            ),
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
                expectedExerciseID: exercise.exerciseID,
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
        let interpretation = GymPhotoInterpretationMapper.map(
            response,
            allowedExerciseIDs: allowedExerciseIDs
        )

        let topCandidate = interpretation.exerciseCandidates.first
        let detectedID = topCandidate?.exerciseID
        let detectedName = topCandidate?.displayName
        let matchesActive = detectedID == nil || detectedID == exercise.exerciseID

        return StrengthPhotoAssistResult(
            interpretation: interpretation,
            suggestedWeight: interpretation.detectedWeight?.value,
            weightUnit: interpretation.detectedWeight?.unit ?? unit,
            detectedExerciseID: detectedID,
            detectedExerciseName: detectedName,
            matchesActiveExercise: matchesActive
        )
    }
}
