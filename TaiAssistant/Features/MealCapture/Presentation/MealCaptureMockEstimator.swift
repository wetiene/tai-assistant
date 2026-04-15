import Foundation

struct MockMealEstimator: MealEstimating {
    func estimateMeal(from imageData: Data) async throws -> MealCaptureDraft {
        try await Task.sleep(nanoseconds: 700_000_000)

        let templates = [
            MealCaptureDraft(
                mealTitle: "Chicken Rice Bowl",
                eatenAt: .now,
                timing: .lunch,
                totalCalories: 640,
                totalProteinGrams: 48,
                totalCarbsGrams: 62,
                totalFatGrams: 20,
                detectedItems: [
                    MealCaptureItemDraft(
                        name: "Grilled chicken thigh",
                        amount: 140,
                        unit: "g",
                        calories: 300,
                        proteinGrams: 35,
                        carbsGrams: 0,
                        fatGrams: 18,
                        fiberGrams: 0
                    ),
                    MealCaptureItemDraft(
                        name: "Jasmine rice",
                        amount: 180,
                        unit: "g",
                        calories: 230,
                        proteinGrams: 4,
                        carbsGrams: 51,
                        fatGrams: 0.5,
                        fiberGrams: 1
                    ),
                    MealCaptureItemDraft(
                        name: "Steamed broccoli",
                        amount: 90,
                        unit: "g",
                        calories: 35,
                        proteinGrams: 3,
                        carbsGrams: 7,
                        fatGrams: 0.4,
                        fiberGrams: 3
                    ),
                    MealCaptureItemDraft(
                        name: "Sesame dressing",
                        amount: 20,
                        unit: "g",
                        calories: 75,
                        proteinGrams: 0.8,
                        carbsGrams: 4,
                        fatGrams: 6,
                        fiberGrams: 0
                    )
                ]
            ),
            MealCaptureDraft(
                mealTitle: "Salmon Avocado Plate",
                eatenAt: .now,
                timing: .dinner,
                totalCalories: 710,
                totalProteinGrams: 44,
                totalCarbsGrams: 36,
                totalFatGrams: 44,
                detectedItems: [
                    MealCaptureItemDraft(
                        name: "Baked salmon",
                        amount: 170,
                        unit: "g",
                        calories: 370,
                        proteinGrams: 38,
                        carbsGrams: 0,
                        fatGrams: 23,
                        fiberGrams: 0
                    ),
                    MealCaptureItemDraft(
                        name: "Roasted sweet potato",
                        amount: 150,
                        unit: "g",
                        calories: 165,
                        proteinGrams: 3,
                        carbsGrams: 33,
                        fatGrams: 0.3,
                        fiberGrams: 5
                    ),
                    MealCaptureItemDraft(
                        name: "Avocado",
                        amount: 80,
                        unit: "g",
                        calories: 128,
                        proteinGrams: 2,
                        carbsGrams: 7,
                        fatGrams: 12,
                        fiberGrams: 6
                    ),
                    MealCaptureItemDraft(
                        name: "Olive oil drizzle",
                        amount: 8,
                        unit: "g",
                        calories: 72,
                        proteinGrams: 0,
                        carbsGrams: 0,
                        fatGrams: 8,
                        fiberGrams: 0
                    )
                ]
            )
        ]

        let selectedTemplate = templates[imageData.count % templates.count]
        return selectedTemplate
    }
}

enum MealCaptureDraftCorrectionEngine {
    static func apply(_ prompt: String, to draft: MealCaptureDraft) -> MealCaptureDraft {
        var updated = draft
        let normalized = prompt.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return draft }
        var didMutateItems = false

        if let swapPayload = parseSwap(from: normalized) {
            if let index = updated.detectedItems.firstIndex(where: { $0.name.lowercased().contains(swapPayload.from) }) {
                updated.detectedItems[index].name = swapPayload.to.capitalized
                didMutateItems = true
            }
        } else if normalized.hasPrefix("remove ") {
            let candidate = normalized.replacingOccurrences(of: "remove ", with: "")
            updated.detectedItems.removeAll { $0.name.lowercased().contains(candidate) }
            didMutateItems = true
        } else if normalized.hasPrefix("add ") {
            let candidate = normalized.replacingOccurrences(of: "add ", with: "")
            updated.detectedItems.append(
                MealCaptureItemDraft(
                    name: candidate.capitalized,
                    amount: 80,
                    unit: "g",
                    calories: 120,
                    proteinGrams: 8,
                    carbsGrams: 10,
                    fatGrams: 4,
                    fiberGrams: 2
                )
            )
            didMutateItems = true
        } else if normalized.contains("less oil") || normalized.contains("lighter") {
            updated.totalFatGrams = max(0, updated.totalFatGrams - 6)
            updated.totalCalories = max(0, updated.totalCalories - 60)
        } else if normalized.contains("more protein") {
            updated.totalProteinGrams += 12
            updated.totalCalories += 60
        }

        updated.correctionPrompt = prompt
        if didMutateItems, !updated.detectedItems.isEmpty {
            updated.recalculateTotalsFromItems()
        }
        return updated
    }

    private static func parseSwap(from input: String) -> (from: String, to: String)? {
        guard input.hasPrefix("swap "), input.contains(" for ") else { return nil }
        let withoutSwap = input.replacingOccurrences(of: "swap ", with: "")
        let chunks = withoutSwap.components(separatedBy: " for ")
        guard chunks.count == 2 else { return nil }
        return (chunks[0].trimmingCharacters(in: .whitespaces), chunks[1].trimmingCharacters(in: .whitespaces))
    }
}
