import XCTest
import RewindCore
@testable import RewindButFast

final class AutomaticJevTests: XCTestCase {
    @MainActor
    func testNaturalQuestionUsesJevAutomaticallyAndRefreshDoesNotResend() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let suite = "SeenTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { try? FileManager.default.removeItem(at: directory); defaults.removePersistentDomain(forName: suite) }
        defaults.set(false, forKey: "recordOnLaunch")
        var queries: [String] = []
        let app = AppModel(defaults: defaults, directory: directory) { query, candidates, _ in
            queries.append(query)
            return candidates.sorted { $0.id < $1.id }
        }
        let store = try MemoryStore(directory: directory)
        try await store.insert(Memory(id: "a", app: "Safari", title: "Data infrastructure", text: "TypeSafe is mostly a data shop", imagePath: ""))
        try await store.insert(Memory(id: "b", app: "Notes", title: "Data", text: "Data for the trip", imagePath: ""))
        app.query = "hey Jev, what was that tweet I saw TypeSafe being a data shop mostly"
        await app.search()
        XCTAssertTrue(app.results.isEmpty, "Local candidates must not appear before Jev results.")
        try await Task.sleep(for: .milliseconds(800))
        XCTAssertEqual(queries, [app.query])
        XCTAssertEqual(app.results.first?.id, "a")
        XCTAssertEqual(app.jevStatus, "Jev · 2 candidates")
        await app.search()
        try await Task.sleep(for: .milliseconds(750))
        XCTAssertEqual(queries.count, 1)
        app.query = ""
        await app.search()
        XCTAssertNil(app.jevStatus)
    }

    @MainActor
    func testQuickSearchCancelsOldQueryAndFallsBackOnProviderFailure() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let suite = "SeenTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { try? FileManager.default.removeItem(at: directory); defaults.removePersistentDomain(forName: suite) }
        var queries: [String] = []
        let app = AppModel(defaults: defaults, directory: directory) { query, _, _ in
            queries.append(query)
            throw JevError.http(429)
        }
        let store = try MemoryStore(directory: directory)
        try await store.insert(Memory(app: "Notes", title: "Launch", text: "Launch on Friday", imagePath: ""))
        let quick = QuickSearchModel(app: app)
        quick.query = "old question"
        await quick.search()
        quick.query = "when is the launch"
        await quick.search()
        try await Task.sleep(for: .milliseconds(800))
        XCTAssertEqual(queries, ["when is the launch"])
        XCTAssertEqual(quick.results.count, 1)
        XCTAssertTrue(quick.jevStatus?.contains("Local results") == true)
        XCTAssertFalse(quick.isJevSearching)
    }

    @MainActor
    func testNoKeyKeepsLocalResultsWithoutError() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let app = AppModel(directory: directory) { _, _, _ in nil }
        let store = try MemoryStore(directory: directory)
        try await store.insert(Memory(app: "Notes", title: "Launch", text: "Launch on Friday", imagePath: ""))
        app.query = "launch"
        await app.search()
        try await Task.sleep(for: .milliseconds(800))
        XCTAssertEqual(app.results.count, 1)
        XCTAssertNil(app.jevStatus)
        XCTAssertFalse(app.isJevSearching)
        app.query = ""
    }
}
