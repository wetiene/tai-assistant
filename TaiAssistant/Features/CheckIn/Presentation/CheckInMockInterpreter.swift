import Foundation

struct MockCheckInInterpreter: CheckInInterpreting {
    func interpret(input: String, photoData: Data?) async throws -> CheckInInterpretationResult {
        try await Task.sleep(nanoseconds: 450_000_000)

        let normalized = input.lowercased()
        let now = Date()
        var drafts: [CheckInMealDraft] = []

        if normalized.contains("breakfast") || normalized.contains("shake") {
            drafts.append(
                CheckInMealDraft(
                    id: UUID(),
                    label: normalized.contains("shake") ? "Protein shake" : "Usual breakfast",
                    timing: .breakfast,
                    eatenAt: now,
                    calories: normalized.contains("shake") ? 280 : 430,
                    proteinGrams: normalized.contains("shake") ? 34 : 33,
                    carbsGrams: normalized.contains("shake") ? 24 : 46,
                    fatGrams: normalized.contains("shake") ? 7 : 14,
                    confidence: 0.83,
                    alternatives: [],
                    items: Self.baseItems(kind: normalized.contains("shake") ? .shake : .breakfast)
                )
            )
        }

        if normalized.contains("lunch") || normalized.contains("dinner") || normalized.contains("family") {
            drafts.append(
                CheckInMealDraft(
                    id: UUID(),
                    label: normalized.contains("family") ? "Family dinner" : "Inferred meal",
                    timing: normalized.contains("dinner") || normalized.contains("family") ? .dinner : .lunch,
                    eatenAt: now,
                    calories: normalized.contains("family") ? 760 : 620,
                    proteinGrams: normalized.contains("family") ? 42 : 36,
                    carbsGrams: normalized.contains("family") ? 71 : 58,
                    fatGrams: normalized.contains("family") ? 31 : 24,
                    confidence: 0.76,
                    alternatives: [],
                    items: Self.baseItems(kind: normalized.contains("family") ? .dinner : .lunch)
                )
            )
        }

        if drafts.isEmpty {
            drafts = [
                CheckInMealDraft(
                    id: UUID(),
                    label: "Detected meal",
                    timing: .other,
                    eatenAt: now,
                    calories: photoData == nil ? 520 : 610,
                    proteinGrams: 32,
                    carbsGrams: 54,
                    fatGrams: 18,
                    confidence: photoData == nil ? 0.63 : 0.68,
                    alternatives: photoData == nil ? ["Salad plate", "Sandwich & soup"] : [],
                    items: Self.baseItems(kind: .defaultMeal)
                )
            ]
        }

        return CheckInInterpretationResult(
            meals: drafts,
            uiNotes: "Mock interpretation for check-in workflow."
        )
    }

    private enum TemplateKind {
        case breakfast
        case shake
        case lunch
        case dinner
        case defaultMeal
    }

    private static func baseItems(kind: TemplateKind) -> [CheckInMealItemDraft] {
        switch kind {
        case .shake:
            return [
                CheckInMealItemDraft(id: UUID(), name: "Whey protein", amount: 35, unit: "g", calories: 140, proteinGrams: 28, carbsGrams: 3, fatGrams: 2, fiberGrams: 0),
                CheckInMealItemDraft(id: UUID(), name: "Banana", amount: 100, unit: "g", calories: 89, proteinGrams: 1.1, carbsGrams: 23, fatGrams: 0.3, fiberGrams: 2.6),
                CheckInMealItemDraft(id: UUID(), name: "Milk", amount: 240, unit: "ml", calories: 110, proteinGrams: 8, carbsGrams: 11, fatGrams: 5, fiberGrams: 0)
            ]
        case .breakfast:
            return [
                CheckInMealItemDraft(id: UUID(), name: "Eggs", amount: 120, unit: "g", calories: 180, proteinGrams: 15, carbsGrams: 1, fatGrams: 13, fiberGrams: 0),
                CheckInMealItemDraft(id: UUID(), name: "Sourdough toast", amount: 65, unit: "g", calories: 170, proteinGrams: 6, carbsGrams: 31, fatGrams: 2.5, fiberGrams: 2),
                CheckInMealItemDraft(id: UUID(), name: "Greek yogurt", amount: 100, unit: "g", calories: 80, proteinGrams: 12, carbsGrams: 5, fatGrams: 1, fiberGrams: 0)
            ]
        case .lunch:
            return [
                CheckInMealItemDraft(id: UUID(), name: "Chicken breast", amount: 140, unit: "g", calories: 220, proteinGrams: 43, carbsGrams: 0, fatGrams: 4.5, fiberGrams: 0),
                CheckInMealItemDraft(id: UUID(), name: "Rice", amount: 160, unit: "g", calories: 210, proteinGrams: 4, carbsGrams: 45, fatGrams: 0.5, fiberGrams: 1),
                CheckInMealItemDraft(id: UUID(), name: "Vegetables", amount: 110, unit: "g", calories: 80, proteinGrams: 3, carbsGrams: 13, fatGrams: 1, fiberGrams: 4)
            ]
        case .dinner:
            return [
                CheckInMealItemDraft(id: UUID(), name: "Steak", amount: 150, unit: "g", calories: 320, proteinGrams: 35, carbsGrams: 0, fatGrams: 21, fiberGrams: 0),
                CheckInMealItemDraft(id: UUID(), name: "Potatoes", amount: 180, unit: "g", calories: 170, proteinGrams: 4, carbsGrams: 36, fatGrams: 0.2, fiberGrams: 3),
                CheckInMealItemDraft(id: UUID(), name: "Salad with dressing", amount: 130, unit: "g", calories: 140, proteinGrams: 3, carbsGrams: 10, fatGrams: 9, fiberGrams: 3)
            ]
        case .defaultMeal:
            return [
                CheckInMealItemDraft(id: UUID(), name: "Main plate", amount: 280, unit: "g", calories: 370, proteinGrams: 24, carbsGrams: 35, fatGrams: 14, fiberGrams: 4),
                CheckInMealItemDraft(id: UUID(), name: "Side", amount: 120, unit: "g", calories: 150, proteinGrams: 8, carbsGrams: 19, fatGrams: 4, fiberGrams: 3)
            ]
        }
    }
}

struct AIServiceCheckInInterpreter: CheckInInterpreting {
    private let aiService: AIService
    private let ownerID: String
    private let localeIdentifier: String
    private let timeZoneIdentifier: String

    init(
        aiService: AIService,
        ownerID: String,
        localeIdentifier: String = Locale.current.identifier,
        timeZoneIdentifier: String = TimeZone.current.identifier
    ) {
        self.aiService = aiService
        self.ownerID = ownerID
        self.localeIdentifier = localeIdentifier
        self.timeZoneIdentifier = timeZoneIdentifier
    }

    func interpret(input: String, photoData: Data?) async throws -> CheckInInterpretationResult {
        print("USING AI SERVICE")
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        let imageInput: AIInterpretMealImageInput?
        if let photoData, !photoData.isEmpty {
            guard let encoded = CheckInPhotoUploadPreprocessor.prepareMealUploadJPEGWithMetrics(fromOriginalJPEGData: photoData) else {
                throw AIServiceError.invalidRequestPayload
            }
            let origMB = Double(encoded.originalByteCount) / 1_000_000.0
            let prepMB = Double(encoded.preparedByteCount) / 1_000_000.0
            print("[CheckInPhoto] original_mb=\(String(format: "%.3f", origMB)) resized_mb=\(String(format: "%.3f", prepMB)) encode_s=\(String(format: "%.3f", encoded.encodeSeconds))")
            imageInput = AIInterpretMealImageInput(
                base64Data: encoded.jpegData.base64EncodedString(),
                mimeType: "image/jpeg",
                uploadReference: nil
            )
        } else {
            imageInput = nil
        }

        do {
            let requestStart = Date()
            print("[CheckInPhoto] request_start_unix=\(requestStart.timeIntervalSince1970)")
            defer {
                let requestEnd = Date()
                print("[CheckInPhoto] request_end_unix=\(requestEnd.timeIntervalSince1970) request_duration_s=\(String(format: "%.3f", requestEnd.timeIntervalSince(requestStart)))")
            }
            let response = try await aiService.interpretMeal(
                request: AIInterpretMealRequest(
                    text: trimmed.isEmpty ? nil : trimmed,
                    image: imageInput,
                    context: AIInterpretMealContext(
                        ownerID: ownerID,
                        localeIdentifier: localeIdentifier,
                        timeZoneIdentifier: timeZoneIdentifier
                    )
                )
            )

            return CheckInInterpretationResult(
                meals: response.interpretedMeals.map { CheckInMealDraft(aiMeal: $0) },
                uiNotes: response.uiNotes
            )
        } catch {
            print("AIServiceCheckInInterpreter error: \(error)")
            if let localizedError = error as? LocalizedError, let description = localizedError.errorDescription {
                print("AIServiceCheckInInterpreter localizedError: \(description)")
            }
            throw error
        }
    }
}
