import XCTest
@testable import TaiAssistant

final class StrengthSessionPersistenceEncodingTests: XCTestCase {
    override func tearDown() {
        StrengthSessionPersistence.encoding = .production
        super.tearDown()
    }

    func testEncodingFailurePropagates() {
        StrengthSessionPersistence.encoding = .init(
            encodeSession: { _ in throw EncodingError.invalidValue("test", .init(codingPath: [], debugDescription: "boom")) },
            encodeDebrief: StrengthSessionPersistence.EncodingHandlers.production.encodeDebrief,
            encodeLegacy: StrengthSessionPersistence.EncodingHandlers.production.encodeLegacy
        )

        let session = StrengthSessionBuilder.makeSession(
            plan: GymProgramTemplateLibrary.resolvableStarter(.upperBody),
            proposals: [],
            acceptedProposals: [:],
            historySessions: []
        )

        XCTAssertThrowsError(try StrengthSessionPersistence.encode(session)) { error in
            guard case StrengthSessionPersistenceError.encodingFailed(let operation, _) = error else {
                return XCTFail("Expected encodingFailed, got \(error)")
            }
            XCTAssertEqual(operation, "strength_session_snapshot")
        }
    }

    func testDebriefEncodingFailurePropagates() {
        StrengthSessionPersistence.encoding = .init(
            encodeSession: StrengthSessionPersistence.EncodingHandlers.production.encodeSession,
            encodeDebrief: { _ in throw EncodingError.invalidValue("test", .init(codingPath: [], debugDescription: "boom")) },
            encodeLegacy: StrengthSessionPersistence.EncodingHandlers.production.encodeLegacy
        )

        let debrief = StrengthDebriefBuilder.build(
            session: StrengthSessionBuilder.makeSession(
                plan: GymProgramTemplateLibrary.resolvableStarter(.upperBody),
                proposals: [],
                acceptedProposals: [:],
                historySessions: []
            )
        )

        XCTAssertThrowsError(try StrengthSessionPersistence.encodeDebrief(debrief)) { error in
            guard case StrengthSessionPersistenceError.encodingFailed(let operation, _) = error else {
                return XCTFail("Expected encodingFailed, got \(error)")
            }
            XCTAssertEqual(operation, "workout_debrief")
        }
    }
}

private extension StrengthSessionPersistence.EncodingHandlers {
    static let production = StrengthSessionPersistence.EncodingHandlers(
        encodeSession: { session in
            var encoded = session
            encoded.snapshotVersion = StrengthSessionPersistence.currentSnapshotVersion
            return try JSONEncoder().encode(WorkoutSessionSnapshotEnvelope.strength(encoded))
        },
        encodeDebrief: { debrief in
            try JSONEncoder().encode(debrief)
        },
        encodeLegacy: { legacy in
            try JSONEncoder().encode(WorkoutSessionSnapshotEnvelope.legacy(legacy))
        }
    )
}
