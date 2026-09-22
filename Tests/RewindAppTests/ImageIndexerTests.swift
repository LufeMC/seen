import XCTest
import AppKit
import RewindCore
@testable import RewindButFast

final class ImageIndexerTests: XCTestCase {
    @MainActor
    func testOCRSearchDeduplicationAndCancellation() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try MemoryStore(directory: directory)
        let indexer = ImageIndexer(store: store, directory: directory)
        let image = NSImage(size: NSSize(width: 1200, height: 300))
        image.lockFocus()
        NSColor.white.setFill()
        NSRect(x: 0, y: 0, width: 1200, height: 300).fill()
        ("Typesafe is mostly a data shop" as NSString).draw(at: NSPoint(x: 50, y: 130),
            withAttributes: [.font: NSFont.systemFont(ofSize: 42), .foregroundColor: NSColor.black])
        image.unlockFocus()
        let cgImage = try XCTUnwrap(image.cgImage(forProposedRect: nil, context: nil, hints: nil))
        let context = CaptureContext(app: "Safari", bundleID: "test", title: "Post", url: "https://example.com/post")
        let first = try await indexer.index(cgImage, context: context, display: "1")
        let duplicate = try await indexer.index(cgImage, context: context, display: "1")
        XCTAssertTrue(first)
        XCTAssertFalse(duplicate)
        let result = try await store.search("Typesafe data shop")
        XCTAssertEqual(result.count, 1)
        XCTAssertTrue(result[0].text.contains("Typesafe"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: result[0].imagePath))
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await indexer.index(cgImage, context: context, display: "2")
        }
        do { _ = try await task.value; XCTFail("A canceled task must not save an image.") }
        catch is CancellationError { }
        let count = try await store.count()
        XCTAssertEqual(count, 1)
    }

    @MainActor
    func testImagesWithNoTextRemainDistinct() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try MemoryStore(directory: directory)
        let indexer = ImageIndexer(store: store, directory: directory)
        let context = CaptureContext(app: "Drawing", bundleID: "drawing", title: "Canvas", url: nil)
        for color in [NSColor.red, NSColor.blue] {
            let image = NSImage(size: NSSize(width: 300, height: 200))
            image.lockFocus()
            color.setFill()
            NSRect(x: 0, y: 0, width: 300, height: 200).fill()
            image.unlockFocus()
            let cgImage = try XCTUnwrap(image.cgImage(forProposedRect: nil, context: nil, hints: nil))
            let inserted = try await indexer.index(cgImage, context: context, display: "1")
            XCTAssertTrue(inserted)
        }
        let count = try await store.count()
        XCTAssertEqual(count, 2)
    }

    @MainActor
    func testSmallTextInLargeImage() async throws {
        let image = NSImage(size: NSSize(width: 2560, height: 1600))
        image.lockFocus()
        NSColor.white.setFill()
        NSRect(x: 0, y: 0, width: 2560, height: 1600).fill()
        ("SEEN SMALL TEXT CHECK" as NSString).draw(at: NSPoint(x: 1700, y: 200),
            withAttributes: [.font: NSFont.systemFont(ofSize: 14), .foregroundColor: NSColor.black])
        image.unlockFocus()
        let cgImage = try XCTUnwrap(image.cgImage(forProposedRect: nil, context: nil, hints: nil))
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try MemoryStore(directory: directory)
        let indexer = ImageIndexer(store: store, directory: directory)
        _ = try await indexer.index(cgImage, context: CaptureContext(app: "Test", bundleID: "test", title: "Small text", url: nil), display: "1")
        let results = try await store.search("SEEN SMALL TEXT CHECK")
        XCTAssertEqual(results.count, 1)
        XCTAssertTrue(results.first?.text.contains("SMALL TEXT CHECK") == true)
    }
}
