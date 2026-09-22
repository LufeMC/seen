import XCTest
@testable import RewindCore

final class SearchFilterTests: XCTestCase {
    func testAppAndDateFiltersApplyBeforeResultLimit() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try MemoryStore(directory: directory)
        let expected = Memory(app: "TextEdit", title: "Target", text: "Blue lantern", imagePath: "")
        try await store.insert(expected)
        try await store.insert(Memory(date: Date(timeIntervalSinceNow: -172800), app: "TextEdit",
            title: "Old", text: "Blue lantern", imagePath: ""))
        for _ in 0..<155 {
            try await store.insert(Memory(app: "Safari", title: "Other", text: "Blue lantern", imagePath: ""))
        }
        let matching = try await store.search("lantern", since: Date(timeIntervalSinceNow: -60), app: "TextEdit", limit: 1)
        XCTAssertEqual(matching.map(\.id), [expected.id])
        let recent = try await store.search(app: "TextEdit")
        XCTAssertEqual(recent.count, 2)
        let apps = try await store.applications()
        XCTAssertEqual(apps, ["Safari", "TextEdit"])
        let missing = try await store.search("lantern", app: "' OR 1=1 --")
        XCTAssertTrue(missing.isEmpty)
    }
}
