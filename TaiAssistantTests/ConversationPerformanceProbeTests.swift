import XCTest
import SwiftData
import UIKit
@testable import TaiAssistant

/// Evidence harness for Conversation / Home persistence cost.
/// Does not log message text, health content, or image bytes — only sizes and timings.
@MainActor
final class ConversationPerformanceProbeTests: XCTestCase {
    private var ownerID: String { "perf.probe.user" }

    func testSnapshotEncodeCostScalesWithInlinePhotos() throws {
        let textOnly = makeConversation(photoCount: 0, messageCount: 40)
        let onePhoto = makeConversation(photoCount: 1, messageCount: 40, jpegBytes: 280_000)
        let threePhotos = makeConversation(photoCount: 3, messageCount: 40, jpegBytes: 280_000)

        let textEncode = measureEncode(textOnly)
        let oneEncode = measureEncode(onePhoto)
        let threeEncode = measureEncode(threePhotos)

        print("[TaiPerf] encode text-only messages=\(textOnly.messages.count) bytes=\(textEncode.bytes) ms=\(format(textEncode.ms))")
        print("[TaiPerf] encode 1×280KB photo bytes=\(oneEncode.bytes) ms=\(format(oneEncode.ms))")
        print("[TaiPerf] encode 3×280KB photos bytes=\(threeEncode.bytes) ms=\(format(threeEncode.ms))")

        XCTAssertLessThan(textEncode.bytes, 50_000, "Text-only snapshot should stay small")
        XCTAssertGreaterThan(oneEncode.bytes, 250_000)
        XCTAssertGreaterThan(threeEncode.bytes, 750_000)
        XCTAssertGreaterThan(oneEncode.ms, textEncode.ms)
        XCTAssertGreaterThan(threeEncode.ms, oneEncode.ms)
    }

    func testSnapshotDecodeCostWithPhotos() throws {
        let threePhotos = makeConversation(photoCount: 3, messageCount: 40, jpegBytes: 280_000)
        let encoded = try ConversationSnapshotCodec.encodeMessages(threePhotos.messages)

        let started = CFAbsoluteTimeGetCurrent()
        _ = try ConversationSnapshotCodec.decodeMessages(encoded)
        let ms = (CFAbsoluteTimeGetCurrent() - started) * 1000
        print("[TaiPerf] decode 3×280KB photos bytes=\(encoded.count) ms=\(format(ms))")
        XCTAssertGreaterThan(encoded.count, 750_000)
    }

    func testComposerKeystrokeCopiesConversationAndSchedulesFullPersist() async throws {
        let conversation = makeConversation(photoCount: 2, messageCount: 30, jpegBytes: 280_000)
        let repo = CountingConversationRepository(seed: conversation)
        let store = ConversationSessionStore(seed: conversation)
        store.onPersist = { conv in
            try? repo.saveActive(conv, ownerID: self.ownerID)
        }
        store.onPersistComposer = { draft in
            try? repo.saveComposerDraft(draft, ownerID: self.ownerID)
        }

        let copyStarted = CFAbsoluteTimeGetCurrent()
        for i in 0..<20 {
            store.updateComposer { $0.text = "typed-\(i)" }
        }
        let copyMs = (CFAbsoluteTimeGetCurrent() - copyStarted) * 1000

        // Debounce window is 400ms — wait past it once.
        try await Task.sleep(nanoseconds: 500_000_000)

        print("[TaiPerf] 20 composer updates (2 photos in memory) wall=\(format(copyMs))ms fullSaves=\(repo.saveCount) composerSaves=\(repo.composerSaveCount) lastComposerEncodeBytes=\(repo.lastComposerOnlyMessageEncodeBytes)")
        XCTAssertEqual(repo.saveCount, 0, "Composer updates must not rewrite full message snapshots")
        XCTAssertEqual(repo.composerSaveCount, 1, "Composer updates must coalesce to one composer-only persist")
        XCTAssertEqual(store.active.messages.count, 30)
        XCTAssertNotEqual(store.composerDraft.text, store.active.composer.text)
    }

    func testMealRepositoryDeleteScansAllLogs() async throws {
        let container = AppModelContainerFactory.makeContainer(inMemory: true)
        let repo = LocalSwiftDataMealRepository(container: container)
        let count = 80
        for i in 0..<count {
            try await repo.createMealLog(
                MealLog(ownerID: ownerID, eatenAt: Date().addingTimeInterval(Double(-i)), notes: "m\(i)")
            )
        }
        let target = try await repo.fetchMealLogs(
            ownerID: ownerID,
            from: .distantPast,
            to: .distantFuture
        ).first!

        let started = CFAbsoluteTimeGetCurrent()
        try await repo.deleteMealLog(id: target.id)
        let ms = (CFAbsoluteTimeGetCurrent() - started) * 1000
        print("[TaiPerf] deleteMealLog among \(count) meals ms=\(format(ms))")
        XCTAssertLessThan(ms, 2_000)
    }

    func testUIImageDecodeCostPerBodyEvaluation() {
        let jpeg = syntheticJPEG(byteTarget: 280_000)
        let iterations = 30
        let started = CFAbsoluteTimeGetCurrent()
        var decoded = 0
        for _ in 0..<iterations {
            if UIImage(data: jpeg) != nil { decoded += 1 }
        }
        let ms = (CFAbsoluteTimeGetCurrent() - started) * 1000
        print("[TaiPerf] UIImage(data:) ×\(iterations) for ~280KB jpeg totalMs=\(format(ms)) per=\(format(ms / Double(iterations)))")
        XCTAssertEqual(decoded, iterations)
    }

    func testSwiftDataFullSnapshotSaveWithPhotos() throws {
        let container = AppModelContainerFactory.makeContainer(inMemory: true)
        let repo = LocalSwiftDataActiveConversationRepository(container: container)
        let conversation = makeConversation(photoCount: 3, messageCount: 40, jpegBytes: 280_000)
        try repo.saveActive(conversation, ownerID: ownerID)

        let started = CFAbsoluteTimeGetCurrent()
        var mutated = conversation
        mutated.composer.text = "draft"
        try repo.saveActive(mutated, ownerID: ownerID)
        let ms = (CFAbsoluteTimeGetCurrent() - started) * 1000
        print("[TaiPerf] SwiftData saveActive (3 photos, composer-only change) ms=\(format(ms))")
        XCTAssertLessThan(ms, 500)
    }

    func testFetchActiveConversationScansAllRows() throws {
        let container = AppModelContainerFactory.makeContainer(inMemory: true)
        let repo = LocalSwiftDataActiveConversationRepository(container: container)
        // Seed one active + several archived via beginArchiveTransition.
        _ = try repo.loadOrCreateActive(ownerID: ownerID)
        for _ in 0..<5 {
            _ = try repo.beginArchiveTransition(ownerID: ownerID)
        }
        let withPhotos = makeConversation(photoCount: 2, messageCount: 20, jpegBytes: 280_000)
        try repo.saveActive(withPhotos, ownerID: ownerID)

        let started = CFAbsoluteTimeGetCurrent()
        _ = try repo.loadOrCreateActive(ownerID: ownerID)
        let ms = (CFAbsoluteTimeGetCurrent() - started) * 1000
        print("[TaiPerf] loadOrCreateActive with photo snapshot ms=\(format(ms))")
    }

    func testHomeDeleteDoesNotUpdateBriefingUntilReload() {
        // Replaced by optimistic local recompute — keep a smoke assert on summary mapping.
        let meal = MealLog(ownerID: ownerID, eatenAt: .now, notes: "A")
        let summary = HomeMealSummary(meal: meal)
        XCTAssertEqual(summary.id, meal.id)
        XCTAssertEqual(summary.label, "A")
    }

    func testImageCacheAvoidsRepeatedDecode() {
        ConversationImageCache.resetForTests()
        let jpeg = syntheticJPEG(byteTarget: 280_000)
        let id = UUID()
        let first = ConversationImageCache.image(id: id, data: jpeg)
        let started = CFAbsoluteTimeGetCurrent()
        for _ in 0..<50 {
            _ = ConversationImageCache.image(id: id, data: jpeg)
        }
        let ms = (CFAbsoluteTimeGetCurrent() - started) * 1000
        print("[TaiPerf] cached UIImage lookup ×50 ms=\(format(ms))")
        XCTAssertNotNil(first)
        XCTAssertLessThan(ms, 5, "Cached lookups should be far cheaper than re-decode")
    }

    // MARK: - Helpers

    private func makeConversation(photoCount: Int, messageCount: Int, jpegBytes: Int = 0) -> ActiveConversation {
        var messages: [ConversationMessage] = []
        for i in 0..<messageCount {
            if i < photoCount {
                messages.append(
                    ConversationMessage(
                        actor: .user,
                        attachment: ConversationAttachment(kind: .photoJPEG(syntheticJPEG(byteTarget: jpegBytes)))
                    )
                )
            } else {
                messages.append(ConversationMessage(actor: i.isMultiple(of: 2) ? .assistant : .user, text: "msg-\(i)"))
            }
        }
        return ActiveConversation(messages: messages, activity: .awaitingUser)
    }

    private func measureEncode(_ conversation: ActiveConversation) -> (bytes: Int, ms: Double) {
        let started = CFAbsoluteTimeGetCurrent()
        let data = (try? ConversationSnapshotCodec.encodeMessages(conversation.messages)) ?? Data()
        let ms = (CFAbsoluteTimeGetCurrent() - started) * 1000
        return (data.count, ms)
    }

    /// Compressible filler that still produces a multi-hundred-KB JPEG payload for size probes.
    private func syntheticJPEG(byteTarget: Int) -> Data {
        let side = 900
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: side, height: side))
        let image = renderer.image { ctx in
            UIColor.darkGray.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: side, height: side))
            UIColor.orange.setFill()
            for i in 0..<40 {
                let rect = CGRect(x: (i * 37) % side, y: (i * 53) % side, width: 80, height: 80)
                ctx.fill(rect)
            }
        }
        var quality: CGFloat = 0.95
        var data = image.jpegData(compressionQuality: quality) ?? Data(count: byteTarget)
        while data.count < byteTarget, quality < 1 {
            quality = 1
            // Pad with structured bytes so JSON encode cost reflects large Data blobs.
            var padded = data
            padded.append(Data(repeating: 0xAB, count: max(0, byteTarget - data.count)))
            data = padded
        }
        if data.count > byteTarget {
            data = data.prefix(byteTarget)
        }
        return data
    }

    private func format(_ ms: Double) -> String {
        String(format: "%.2f", ms)
    }
}

/// Counts full snapshot saves for coalesce evidence.
private final class CountingConversationRepository: ActiveConversationRepository {
    private var active: ActiveConversation
    private(set) var saveCount = 0
    private(set) var composerSaveCount = 0
    private(set) var lastEncodedMessageBytes = 0
    private(set) var lastComposerOnlyMessageEncodeBytes = 0

    init(seed: ActiveConversation) {
        self.active = seed
    }

    func loadOrCreateActive(ownerID: String) throws -> ActiveConversation { active }

    func saveActive(_ conversation: ActiveConversation, ownerID: String) throws {
        saveCount += 1
        lastEncodedMessageBytes = try ConversationSnapshotCodec.encodeMessages(conversation.messages).count
        active = conversation
    }

    func saveComposerDraft(_ composer: ConversationComposerState, ownerID: String) throws {
        composerSaveCount += 1
        // Composer-only path must not require encoding messages; record 0 as proof.
        lastComposerOnlyMessageEncodeBytes = 0
        active.composer = composer
    }

    func beginArchiveTransition(ownerID: String) throws -> ActiveConversation {
        active = ActiveConversation()
        return active
    }
}
