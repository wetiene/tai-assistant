import Foundation

enum GymPlanImportMapper {
    static func makeImportDraft(from response: AIInterpretWorkoutPlanResponse, sourceType: GymPlanImportSourceType) -> GymPlanImportDraft {
        let suggested = response.suggestedPlan
        let defaultPrescription = GymProgramPrescription(
            workingSetsPerExercise: 3,
            repRangeLower: 8,
            repRangeUpper: 12,
            coachingNote: suggested.generalInstructions.joined(separator: " ")
        )

        let sections = suggested.sections
            .sorted { $0.orderIndex < $1.orderIndex }
            .map { section -> GymPlanSectionDraft in
                let exercises = section.exercises
                    .sorted { $0.orderIndex < $1.orderIndex }
                    .enumerated()
                    .map { index, proposed -> GymPlannedExercise in
                        mapExercise(proposed, orderIndex: index, defaultPrescription: defaultPrescription)
                    }
                return GymPlanSectionDraft(
                    name: section.name,
                    orderIndex: section.orderIndex,
                    exercises: exercises,
                    prescription: nil
                )
            }

        return GymPlanImportDraft(
            id: UUID(),
            title: suggested.name,
            sections: sections,
            prescription: defaultPrescription,
            generalInstructions: suggested.generalInstructions,
            suggestedDurationWeeks: suggested.suggestedDurationWeeks,
            unresolvedItems: response.unresolvedItems.map {
                GymPlanImportUnresolvedItem(
                    sourceText: $0.sourceText,
                    reason: $0.reason,
                    suggestedMatches: $0.suggestedMatches.map {
                        GymPlanImportMatchSuggestion(exerciseID: $0.exerciseID, confidence: $0.confidence)
                    }
                )
            },
            warnings: response.warnings,
            confidence: response.confidence,
            requiresUserConfirmation: response.requiresUserConfirmation,
            sourceType: sourceType
        )
    }

    static func knownExerciseCatalog() -> [AIWorkoutPlanKnownExercise] {
        GymExerciseID.allCases.map {
            AIWorkoutPlanKnownExercise(id: $0.rawValue, name: $0.displayName)
        }
    }

    private static func mapExercise(
        _ proposed: AIWorkoutPlanExerciseProposal,
        orderIndex: Int,
        defaultPrescription: GymProgramPrescription
    ) -> GymPlannedExercise {
        let catalogID = proposed.matchedExerciseID.flatMap(GymExerciseID.init(rawValue:))
        let isUnresolved = catalogID == nil && proposed.matchConfidence < 0.85
        let reference: GymPlanExerciseReference
        if let catalogID {
            reference = GymPlanExerciseReference(
                catalogExerciseID: catalogID.rawValue,
                customName: proposed.displayName,
                sourceName: proposed.sourceName
            )
        } else {
            reference = .custom(name: proposed.displayName, sourceName: proposed.sourceName)
        }

        var alternatives: [GymExerciseID] = []
        if let catalogID, catalogID == .reverseGripLatPulldown {
            alternatives = [.assistedChinUp]
        }

        return GymPlannedExercise(
            reference: reference,
            isOptional: proposed.isOptional,
            alternativeExerciseIDs: alternatives,
            orderIndex: orderIndex,
            targetSets: proposed.targetSets ?? defaultPrescription.workingSetsPerExercise,
            minimumRepetitions: proposed.minimumRepetitions ?? defaultPrescription.repRangeLower,
            maximumRepetitions: proposed.maximumRepetitions ?? defaultPrescription.repRangeUpper,
            notes: proposed.notes,
            matchConfidence: proposed.matchConfidence,
            isUnresolved: isUnresolved
        )
    }
}

@MainActor
enum GymPlanImportService {
    static func interpret(
        source: GymPlanImportSource,
        aiService: AIService,
        requestContext: GymPlanImportRequestContext? = nil
    ) async throws -> GymPlanImportDraft {
        var mutableSource = source
        defer { mutableSource.clearTransientPayload() }

        let trimmedText = source.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if source.type == .text, trimmedText.isEmpty {
            throw GymPlanImportError.invalidSource
        }

        let knownExercises = GymPlanImportMapper.knownExerciseCatalog()
        let context = requestContext ?? GymPlanImportRequestContext(
            requestURL: resolvedWorkoutPlanURL(for: aiService),
            sourceType: source.type,
            schemaVersion: 1,
            sourceTextCharacterCount: trimmedText.count,
            knownExerciseCount: knownExercises.count,
            tokenPresent: false,
            tokenLength: 0,
            tokenFingerprint: nil
        )

        let request = AIInterpretWorkoutPlanRequest(
            schemaVersion: context.schemaVersion,
            source: AIWorkoutPlanSourcePayload(from: mutableSource),
            context: AIWorkoutPlanInterpretContext(
                localeIdentifier: Locale.current.identifier,
                preferredWeightUnit: Locale.current.usesMetricSystem ? "kg" : "lb",
                knownExercises: knownExercises
            )
        )

        do {
            let response = try await aiService.interpretWorkoutPlan(request: request)
            return try mapResponse(response, sourceType: source.type)
        } catch {
            let importError = GymPlanImportErrorMapper.map(error)
            let serviceDiagnostics = (aiService as? AIProxyDiagnosticsReporting)?.lastCallDiagnostics
            let diagnostics = GymPlanImportErrorMapper.diagnostics(
                for: importError,
                context: context,
                serviceDiagnostics: serviceDiagnostics
            )
            GymPlanImportDiagnostics.log(diagnostics)
            throw importError
        }
    }

    private static func mapResponse(
        _ response: AIInterpretWorkoutPlanResponse,
        sourceType: GymPlanImportSourceType
    ) -> GymPlanImportDraft {
        GymPlanImportMapper.makeImportDraft(from: response, sourceType: sourceType)
    }

    private static func resolvedWorkoutPlanURL(for aiService: AIService) -> String? {
        (aiService as? AIProxyDiagnosticsReporting)?.lastCallDiagnostics?.requestURL
            ?? URL(
                string: RuntimeAppConfig.default.aiInterpretWorkoutPlanPath,
                relativeTo: RuntimeAppConfig.default.aiProxyBaseURL
            )?.absoluteString
    }
}

private extension AIWorkoutPlanSourcePayload {
    init(from source: GymPlanImportSource) {
        switch source.type {
        case .text:
            self.init(type: "text", text: source.text, attachment: nil)
        case .image:
            self.init(
                type: "image",
                text: nil,
                attachment: AIWorkoutPlanAttachmentPayload(
                    base64Data: source.attachmentData?.base64EncodedString(),
                    mimeType: source.mimeType
                )
            )
        case .pdf:
            self.init(
                type: "pdf",
                text: nil,
                attachment: AIWorkoutPlanAttachmentPayload(
                    base64Data: source.attachmentData?.base64EncodedString(),
                    mimeType: source.mimeType ?? "application/pdf"
                )
            )
        }
    }
}
