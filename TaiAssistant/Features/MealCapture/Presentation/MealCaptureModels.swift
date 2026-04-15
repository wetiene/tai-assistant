import Foundation

struct MealCaptureItemDraft: Identifiable {
    var id = UUID()
    var name: String
    var amount: Double
    var unit: String
    var calories: Int
    var proteinGrams: Double
    var carbsGrams: Double
    var fatGrams: Double
    var fiberGrams: Double
}

struct MealCaptureDraft {
    var mealTitle: String
    var eatenAt: Date
    var timing: MealTiming
    var totalCalories: Int
    var totalProteinGrams: Double
    var totalCarbsGrams: Double
    var totalFatGrams: Double
    var detectedItems: [MealCaptureItemDraft]
    var correctionPrompt: String = ""

    mutating func recalculateTotalsFromItems() {
        totalCalories = detectedItems.reduce(0) { $0 + $1.calories }
        totalProteinGrams = detectedItems.reduce(0) { $0 + $1.proteinGrams }
        totalCarbsGrams = detectedItems.reduce(0) { $0 + $1.carbsGrams }
        totalFatGrams = detectedItems.reduce(0) { $0 + $1.fatGrams }
    }

    mutating func moveItemUp(id: UUID) {
        guard let index = detectedItems.firstIndex(where: { $0.id == id }), index > 0 else { return }
        detectedItems.swapAt(index, index - 1)
    }

    mutating func moveItemDown(id: UUID) {
        guard let index = detectedItems.firstIndex(where: { $0.id == id }), index < (detectedItems.count - 1) else { return }
        detectedItems.swapAt(index, index + 1)
    }
}

protocol MealEstimating {
    func estimateMeal(from imageData: Data) async throws -> MealCaptureDraft
}
