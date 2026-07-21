import XCTest
import UIKit
@testable import TaiAssistant

@MainActor
final class ConversationRuntimeStabilityTests: XCTestCase {
    override func setUp() {
        super.setUp()
        ConversationRuntimeProbe.reset()
        ConversationImageCache.resetForTests()
        MealCardPayloadCache.resetForTests()
        ConversationAttachmentStore.shared = .makeEphemeralForTests()
    }

    func testAttachmentImageCacheHitDoesNotReloadDisk() throws {
        let id = UUID()
        let jpeg = syntheticJPEG(byteTarget: 40_000)
        try ConversationAttachmentStore.shared.save(id: id, data: jpeg)
        let attachment = ConversationAttachment(id: id, kind: .photoJPEGFile)

        let first = ConversationImageCache.image(id: id, loadData: {
            ConversationAttachmentStore.shared.resolvedJPEGData(for: attachment)
        })
        XCTAssertNotNil(first)
        let loadsAfterFirst = ConversationRuntimeProbe.attachmentDiskLoadCount
        XCTAssertEqual(loadsAfterFirst, 1)

        for _ in 0..<20 {
            let again = ConversationImageCache.image(id: id, loadData: {
                ConversationAttachmentStore.shared.resolvedJPEGData(for: attachment)
            })
            XCTAssertNotNil(again)
        }

        XCTAssertEqual(
            ConversationRuntimeProbe.attachmentDiskLoadCount,
            loadsAfterFirst,
            "Cached UIImage must not re-read attachment bytes from disk"
        )
        XCTAssertGreaterThan(ConversationRuntimeProbe.imageCacheHitCount, 0)
    }

    func testMealCardPayloadCacheAvoidsRepeatedJSONDecode() {
        let payload = MealEstimateCardPayload(
            draft: MealEstimateSnapshot(
                draft: CheckInMealDraft(
                    id: UUID(),
                    label: "Oats",
                    timing: .breakfast,
                    eatenAt: .now,
                    calories: 400,
                    proteinGrams: 20,
                    carbsGrams: 50,
                    fatGrams: 10,
                    confidence: 0.8,
                    alternatives: [],
                    items: []
                )
            ),
            refinementAccepted: false,
            isLogged: false
        )
        let card = MealCardCodec.makeCard(payload: payload, interactive: true)

        XCTAssertNotNil(MealCardPayloadCache.payload(for: card))
        XCTAssertEqual(ConversationRuntimeProbe.cardDecodeCount, 1)

        for _ in 0..<30 {
            XCTAssertNotNil(MealCardPayloadCache.payload(for: card))
        }
        XCTAssertEqual(ConversationRuntimeProbe.cardDecodeCount, 1)
        XCTAssertEqual(ConversationRuntimeProbe.cardDecodeCacheHitCount, 30)
    }

    func testComposerKeystrokesDoNotCopyActiveMessages() {
        let store = ConversationSessionStore(
            seed: ActiveConversation(
                messages: (0..<40).map { ConversationMessage(actor: .assistant, text: "m\($0)") },
                activity: .awaitingUser
            )
        )
        let messageIDs = store.active.messages.map(\.id)
        ConversationRuntimeProbe.reset()

        for i in 0..<25 {
            store.updateComposer { $0.text = "draft-\(i)" }
        }

        XCTAssertEqual(store.active.messages.map(\.id), messageIDs)
        XCTAssertEqual(ConversationRuntimeProbe.composerStoreUpdateCount, 25)
        XCTAssertEqual(store.composerDraft.text, "draft-24")
        XCTAssertEqual(store.active.composer.text, "")
    }

    func testComposerDebounceCreatesTasksButCancelsPriorWork() async throws {
        let store = ConversationSessionStore()
        var composerSaves = 0
        store.onPersistComposer = { _ in composerSaves += 1 }
        ConversationRuntimeProbe.reset()

        for i in 0..<15 {
            store.updateComposer { $0.text = "x\(i)" }
        }
        XCTAssertEqual(ConversationRuntimeProbe.debounceTaskCreatedCount, 15)

        try await Task.sleep(nanoseconds: 500_000_000)
        XCTAssertEqual(composerSaves, 1, "Only the latest debounced composer persist should run")
    }

    func testScrollProbeDoesNotFireOnComposerUpdates() {
        ConversationRuntimeProbe.reset()
        let store = ConversationSessionStore(
            seed: ActiveConversation(
                messages: [ConversationMessage(actor: .assistant, text: "Hi")],
                activity: .awaitingUser
            )
        )
        store.updateComposer { $0.text = "typing" }
        store.updateComposer { $0.text = "typing more" }
        XCTAssertEqual(ConversationRuntimeProbe.scrollToBottomCount, 0)
    }

    // MARK: - Helpers

    private func syntheticJPEG(byteTarget: Int) -> Data {
        let side = 320
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: side, height: side))
        let image = renderer.image { ctx in
            UIColor.gray.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: side, height: side))
            UIColor.orange.setFill()
            ctx.fill(CGRect(x: 40, y: 40, width: 120, height: 120))
        }
        var data = image.jpegData(compressionQuality: 0.9) ?? Data(count: byteTarget)
        if data.count < byteTarget {
            data.append(Data(repeating: 0xAB, count: byteTarget - data.count))
        }
        return data.prefix(byteTarget)
    }
}
