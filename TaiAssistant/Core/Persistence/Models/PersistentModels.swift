import Foundation
import SwiftData

@Model
final class MealRecord {
    // V1 intentionally stores meal summaries only; no photo blob/file storage.
    @Attribute(.unique) var id: UUID
    var summary: String
    var date: Date

    init(id: UUID = UUID(), summary: String, date: Date) {
        self.id = id
        self.summary = summary
        self.date = date
    }
}

@Model
final class GoalRecord {
    @Attribute(.unique) var id: UUID
    var title: String
    var targetValue: Double

    init(id: UUID = UUID(), title: String, targetValue: Double) {
        self.id = id
        self.title = title
        self.targetValue = targetValue
    }
}
