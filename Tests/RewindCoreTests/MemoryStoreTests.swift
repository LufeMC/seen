import XCTest
@testable import RewindCore

final class MemoryStoreTests: XCTestCase {
    func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    }

    func testNaturalQuestionAndPersistence() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try MemoryStore(directory: directory)
        let expected = Memory(app: "Safari", title: "A useful post", text: "Typesafe is mostly a data shop",
            imagePath: "", sourceURL: "https://example.com/post/123")
        try await store.insert(expected)
        try await store.insert(Memory(app: "Notes", title: "Groceries", text: "Milk and bread", imagePath: ""))
        let results = try await store.search("What was that tweet I saw about Typesafe being a data shop?")
        XCTAssertEqual(results.first?.id, expected.id)
        XCTAssertEqual(results.first?.sourceURL, expected.sourceURL)
        let reopened = try MemoryStore(directory: directory)
        let persisted = try await reopened.search("Typesaf")
        XCTAssertEqual(persisted.map(\.id), [expected.id])
    }

    func testQueriesCannotInjectFTSSyntax() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try MemoryStore(directory: directory)
        try await store.insert(Memory(app: "Notes", title: "Café", text: "Résumé 日本語", imagePath: ""))
        for query in ["\" OR * NOT (", "' ; DROP TABLE memories; --", "日本語", "cafe", "", "🪐"] {
            _ = try await store.search(query)
        }
        let count = try await store.count()
        XCTAssertEqual(count, 1)
        let unicodeResults = try await store.search("cafe")
        XCTAssertEqual(unicodeResults.count, 1)
    }

    func testDateFilterRetentionAndImageDeletion() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try MemoryStore(directory: directory)
        let oldImage = directory.appendingPathComponent("images/old.jpg")
        try Data([1, 2, 3]).write(to: oldImage)
        try await store.insert(Memory(date: Date(timeIntervalSinceNow: -864000), app: "Old", title: "Old",
            text: "old needle", imagePath: oldImage.path))
        for index in 0..<3 {
            try await store.insert(Memory(date: Date(timeIntervalSinceNow: Double(-index)), app: "New", title: "New",
                text: "needle \(index)", imagePath: ""))
        }
        let recent = try await store.search("needle", since: Date(timeIntervalSinceNow: -60))
        XCTAssertEqual(recent.count, 3)
        try await store.prune(before: Date(timeIntervalSinceNow: -86400), maximumCount: 2)
        let count = try await store.count()
        XCTAssertEqual(count, 2)
        XCTAssertFalse(FileManager.default.fileExists(atPath: oldImage.path))
        try await store.deleteAll()
        let results = try await store.search("needle")
        XCTAssertTrue(results.isEmpty)
    }

    func testDeletionDoesNotRemoveAnExternalFile() async throws {
        let directory = temporaryDirectory()
        let outside = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: directory)
            try? FileManager.default.removeItem(at: outside)
        }
        try Data([42]).write(to: outside)
        let store = try MemoryStore(directory: directory)
        let item = Memory(app: "Test", title: "Test", text: "secret", imagePath: outside.path)
        try await store.insert(item)
        try await store.delete(id: item.id)
        XCTAssertTrue(FileManager.default.fileExists(atPath: outside.path))
        let result = try await store.search("secret")
        XCTAssertTrue(result.isEmpty)
    }

    func testSourceURLValidation() {
        XCTAssertNil(SearchQuery.safeURL("javascript:alert(1)"))
        XCTAssertNil(SearchQuery.safeURL("file:///etc/passwd"))
        XCTAssertNil(SearchQuery.safeURL("https:no-host"))
        XCTAssertNotNil(SearchQuery.safeURL("https://example.com/post"))
    }

    func testSearchAcross5000Captures() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try MemoryStore(directory: directory)
        for index in 0..<5000 {
            try await store.insert(Memory(app: "Browser", title: "Page \(index)",
                text: index == 2500 ? "Typesafe data shop" : "A routine page about project number \(index)", imagePath: ""))
        }
        let start = Date()
        let results = try await store.search("what was that Typesafe data shop")
        let duration = Date().timeIntervalSince(start)
        XCTAssertEqual(results.first?.title, "Page 2500")
        XCTAssertLessThan(duration, 2)
        print("Search benchmark: 5,000 captures in \(duration) seconds")
    }
}
