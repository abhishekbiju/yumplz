import XCTest
@testable import MealKit

// Tests use a temp-directory-backed store to stay isolated from any real
// App Group container. We swap the file URL by testing via the public API
// (append → readAll → drain) against whatever containerDirectory resolves to
// in the simulator (temp dir fallback).

final class PendingImportStoreTests: XCTestCase {

    override func setUp() {
        super.setUp()
        // Drain any leftover items from a previous test run.
        PendingImportStore.drain()
    }

    override func tearDown() {
        PendingImportStore.drain()
        super.tearDown()
    }

    // ── Slice 1 ──────────────────────────────────────────────────────────
    // append then readAll returns the item

    func testAppendAndReadAll() {
        let item = PendingImportItem(kind: .url, value: "https://example.com/recipe")
        PendingImportStore.append(item)

        let all = PendingImportStore.readAll()
        XCTAssertEqual(all.count, 1)
        XCTAssertEqual(all.first?.value, "https://example.com/recipe")
        XCTAssertEqual(all.first?.kind, .url)
    }

    // ── Slice 2 ──────────────────────────────────────────────────────────
    // Multiple appends accumulate

    func testMultipleAppendsAccumulate() {
        PendingImportStore.append(PendingImportItem(kind: .url, value: "https://a.com"))
        PendingImportStore.append(PendingImportItem(kind: .url, value: "https://b.com"))
        PendingImportStore.append(PendingImportItem(kind: .videoFile, value: "/tmp/video.mp4"))

        XCTAssertEqual(PendingImportStore.readAll().count, 3)
    }

    // ── Slice 3 ──────────────────────────────────────────────────────────
    // drain returns all items and leaves queue empty

    func testDrainReturnsAndClearsQueue() {
        PendingImportStore.append(PendingImportItem(kind: .url, value: "https://x.com"))
        PendingImportStore.append(PendingImportItem(kind: .url, value: "https://y.com"))

        let drained = PendingImportStore.drain()
        XCTAssertEqual(drained.count, 2)
        XCTAssertTrue(PendingImportStore.readAll().isEmpty)
    }

    // ── Slice 4 ──────────────────────────────────────────────────────────
    // hasPending reflects queue state

    func testHasPendingReflectsState() {
        XCTAssertFalse(PendingImportStore.hasPending)
        PendingImportStore.append(PendingImportItem(kind: .url, value: "https://z.com"))
        XCTAssertTrue(PendingImportStore.hasPending)
        PendingImportStore.drain()
        XCTAssertFalse(PendingImportStore.hasPending)
    }

    // ── Slice 5 ──────────────────────────────────────────────────────────
    // remove by ID removes only that item

    func testRemoveByIDRemovesSingleItem() {
        let a = PendingImportItem(kind: .url, value: "https://a.com")
        let b = PendingImportItem(kind: .url, value: "https://b.com")
        PendingImportStore.append(a)
        PendingImportStore.append(b)

        PendingImportStore.remove(id: a.id)

        let remaining = PendingImportStore.readAll()
        XCTAssertEqual(remaining.count, 1)
        XCTAssertEqual(remaining.first?.value, "https://b.com")
    }

    // ── Slice 6 ──────────────────────────────────────────────────────────
    // readAll on empty queue returns empty array (no crash)

    func testReadAllOnEmptyQueueIsEmpty() {
        XCTAssertTrue(PendingImportStore.readAll().isEmpty)
    }

    // ── Slice 7 ──────────────────────────────────────────────────────────
    // Items preserve kind and value after round-trip

    func testVideoFileItemRoundTrip() {
        let item = PendingImportItem(kind: .videoFile, value: "/group/video/abc.mp4")
        PendingImportStore.append(item)

        let read = PendingImportStore.readAll().first
        XCTAssertEqual(read?.kind, .videoFile)
        XCTAssertEqual(read?.value, "/group/video/abc.mp4")
        XCTAssertEqual(read?.id, item.id)
    }
}
