import XCTest
import RewindCore
@testable import RewindButFast

final class QuickSearchTests: XCTestCase {
    @MainActor
    func testQuickSearchIsIndependentAndKeepsSelectionWithinResults() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let suite = "SeenTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer {
            try? FileManager.default.removeItem(at: directory)
            defaults.removePersistentDomain(forName: suite)
        }
        defaults.set(false, forKey: "recordOnLaunch")
        let app = AppModel(defaults: defaults, directory: directory, jevOperation: { _, _, _ in nil })
        app.jevAvailable = false
        let store = try MemoryStore(directory: directory)
        for index in 0..<3 {
            try await store.insert(Memory(id: "\(index)", app: "Notes", title: "Lantern \(index)", text: "Blue lantern", imagePath: ""))
        }
        app.query = "unrelated"
        app.appFilter = "Safari"
        app.onlyToday = true
        await app.initialize()
        XCTAssertFalse(app.isRecording)
        XCTAssertTrue(app.results.isEmpty)
        let quick = QuickSearchModel(app: app)
        quick.query = "lantern"
        await quick.search()
        XCTAssertEqual(quick.results.count, 3)
        XCTAssertEqual(app.query, "unrelated")
        XCTAssertEqual(app.appFilter, "Safari")
        quick.move(-1)
        XCTAssertEqual(quick.selection, quick.results.first?.id)
        quick.move(99)
        XCTAssertEqual(quick.selection, quick.results.last?.id)
        quick.query = "unmatchedword"
        await quick.search()
        XCTAssertNil(quick.selection)
        XCTAssertTrue(quick.results.isEmpty)
    }

    @MainActor
    func testRecordingStartupPreferenceDefaultsOnAndPersistsOptOut() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let suite = "SeenTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer {
            try? FileManager.default.removeItem(at: directory)
            defaults.removePersistentDomain(forName: suite)
        }
        let app = AppModel(defaults: defaults, directory: directory, jevOperation: { _, _, _ in nil })
        XCTAssertTrue(app.recordOnLaunch)
        app.recordOnLaunch = false
        let reopened = AppModel(defaults: defaults, directory: directory, jevOperation: { _, _, _ in nil })
        XCTAssertFalse(reopened.recordOnLaunch)
    }
}
