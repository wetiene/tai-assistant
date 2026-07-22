import Foundation

struct StrengthExerciseHistorySession: Equatable, Sendable {
    var completedAt: Date
    var sets: [StrengthExerciseHistorySet]
}

struct StrengthExerciseHistorySet: Equatable, Sendable {
    var weight: Double
    var reps: Int
    var setNumber: Int
}

enum StrengthExerciseHistoryLoader {
    static func loadRecentSessions(
        exerciseID: String,
        from sessions: [WorkoutSessionLog],
        limit: Int = 6
    ) -> [StrengthExerciseHistorySession] {
        let completed = sessions
            .filter { $0.status == .completed }
            .sorted { ($0.completedAt ?? $0.startedAt) > ($1.completedAt ?? $1.startedAt) }

        var results: [StrengthExerciseHistorySession] = []
        for session in completed {
            let matchingSets = session.sets
                .filter { $0.exerciseID == exerciseID }
                .sorted { $0.setNumber < $1.setNumber }
            guard !matchingSets.isEmpty else { continue }

            let historySets = matchingSets.map {
                StrengthExerciseHistorySet(weight: $0.weightValue, reps: $0.repetitions, setNumber: $0.setNumber)
            }
            results.append(
                StrengthExerciseHistorySession(
                    completedAt: session.completedAt ?? session.startedAt,
                    sets: historySets
                )
            )
            if results.count >= limit { break }
        }
        return results
    }

    static func latestWeight(
        exerciseID: String,
        from sessions: [WorkoutSessionLog]
    ) -> (weight: Double, unit: String)? {
        for session in sessions.filter({ $0.status == .completed }).sorted(by: {
            ($0.completedAt ?? $0.startedAt) > ($1.completedAt ?? $1.startedAt)
        }) {
            if let set = session.sets.filter({ $0.exerciseID == exerciseID }).sorted(by: { $0.setNumber < $1.setNumber }).last {
                return (set.weightValue, set.weightUnit)
            }
        }
        return nil
    }

    static func daysSinceLastSession(
        exerciseID: String,
        from sessions: [WorkoutSessionLog],
        now: Date = .now,
        calendar: Calendar = .current
    ) -> Int? {
        guard let latest = loadRecentSessions(exerciseID: exerciseID, from: sessions, limit: 1).first else {
            return nil
        }
        let start = calendar.startOfDay(for: latest.completedAt)
        let today = calendar.startOfDay(for: now)
        return calendar.dateComponents([.day], from: start, to: today).day
    }
}
