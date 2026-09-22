import AppKit
import Observation
import RewindCore

@MainActor @Observable
final class AppModel {
    var query = "" { didSet { if query != oldValue { clearJev() } } }
    var jevProvider: JevProvider { didSet { defaults.set(jevProvider.rawValue, forKey: "jevProvider"); refreshJevConfiguration() } }
    var jevConfigurationVersion = 0
    var jevAvailable = false
    var isJevSearching = false
    var jevStatus: String?
    @ObservationIgnored private var jevTask: Task<Void, Never>?
    @ObservationIgnored private var jevVersion = 0
    @ObservationIgnored private var jevResultsActive = false
    @ObservationIgnored private var jevScheduled = false
    @ObservationIgnored private var jevFailed = false
    @ObservationIgnored private let injectedJev: Bool
    var onlyToday = false { didSet { if onlyToday != oldValue { clearJev() } } }
    var appFilter = "" { didSet { if appFilter != oldValue { clearJev() } } }
    var applications: [String] = []
    var results: [Memory] = []
    var selection: String?
    var count = 0
    var isRecording = false
    var isWorking = false
    var isSearching = false
    var status = "Recording is paused"
    var error: String?
    var recordOnLaunch: Bool { didSet { defaults.set(recordOnLaunch, forKey: "recordOnLaunch") } }
    var retentionDays: Int { didSet { defaults.set(retentionDays, forKey: "retentionDays") } }
    var exclusions: String { didSet { defaults.set(exclusions, forKey: "exclusions") } }
    var readBrowserURL: Bool { didSet { defaults.set(readBrowserURL, forKey: "readBrowserURL") } }
    let directory: URL
    typealias JevOperation = (String, [Memory], JevProvider) async throws -> [Memory]?
    @ObservationIgnored private let jevOperation: JevOperation
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let store: MemoryStore?
    @ObservationIgnored private let indexer: ImageIndexer?
    @ObservationIgnored private var recordingTask: Task<Void, Never>?
    @ObservationIgnored private var searchVersion = 0
    @ObservationIgnored private var suspended = false
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    @ObservationIgnored private var initialized = false

    init(defaults: UserDefaults = .standard, directory dataDirectory: URL? = nil, jevOperation: JevOperation? = nil) {
        self.defaults = defaults
        self.injectedJev = jevOperation != nil
        self.jevOperation = jevOperation ?? { input, candidates, provider in
            guard let key = try APIKeyStore().read(provider) else { return nil }
            return try await JevClient().rank(query: input, memories: candidates, provider: provider, key: key)
        }
        let provider = JevProvider(rawValue: defaults.string(forKey: "jevProvider") ?? "") ?? .typesafe
        jevProvider = provider
        jevAvailable = jevOperation != nil || ((try? APIKeyStore().read(provider)) != nil)
        recordOnLaunch = defaults.object(forKey: "recordOnLaunch") as? Bool ?? true
        retentionDays = defaults.object(forKey: "retentionDays") as? Int ?? 7
        exclusions = defaults.string(forKey: "exclusions") ?? CaptureEngine.defaultExclusions
        readBrowserURL = defaults.bool(forKey: "readBrowserURL")
        let override = ProcessInfo.processInfo.environment["REWIND_DATA_DIR"]
        directory = dataDirectory ?? override.map { URL(fileURLWithPath: $0) } ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("RewindButFast")
        do {
            let opened = try MemoryStore(directory: directory)
            store = opened
            indexer = ImageIndexer(store: opened, directory: directory)
        } catch {
            store = nil
            indexer = nil
            self.error = error.localizedDescription
        }
        for name in [NSWorkspace.screensDidSleepNotification, NSWorkspace.sessionDidResignActiveNotification] {
            observers.append(NSWorkspace.shared.notificationCenter.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.suspended = true }
            })
        }
        for name in [NSWorkspace.screensDidWakeNotification, NSWorkspace.sessionDidBecomeActiveNotification] {
            observers.append(NSWorkspace.shared.notificationCenter.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.suspended = false }
            })
        }
    }

    var selected: Memory? { results.first { $0.id == selection } }
    var excludedIDs: Set<String> { Set(exclusions.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }) }

    func initialize() async {
        guard !initialized else { return }
        initialized = true
        await applyRetention()
        await search()
        if recordOnLaunch { start() }
    }

    func quickResults(for query: String) async throws -> [Memory] {
        try await store?.search(query, limit: 30) ?? []
    }

    func search() async {
        guard let store else { return }
        searchVersion += 1
        let version = searchVersion
        let currentQuery = query
        let since = onlyToday ? Calendar.current.startOfDay(for: Date()) : nil
        let selectedApp = appFilter.isEmpty ? nil : appFilter
        isSearching = true
        defer { if version == searchVersion { isSearching = false } }
        do {
            let found = try await store.search(currentQuery, since: since, app: selectedApp)
            let total = try await store.count()
            let apps = try await store.applications()
            guard version == searchVersion, !Task.isCancelled,
                  query == currentQuery, appFilter == (selectedApp ?? ""),
                  onlyToday == (since != nil) else { return }
            if !jevResultsActive && (!jevAvailable || currentQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || jevFailed) { results = found }
            count = total
            applications = apps
            if !results.contains(where: { $0.id == selection }) { selection = results.first?.id }
            scheduleJev()
        } catch { self.error = error.localizedDescription }
    }

    func jevResults(for input: String, since: Date? = nil, app: String? = nil) async throws -> [Memory]? {
        let provider = jevProvider
        guard let store else { return [] }
        let matches = try await store.search(input, since: since, app: app, limit: 24)
        let recent = try await store.search("", since: since, app: app, limit: 32)
        var ids = Set<String>()
        let candidates = (matches + recent).filter { ids.insert($0.id).inserted }
        try Task.checkCancellation()
        return try await jevOperation(input, Array(candidates.prefix(JevClient.candidateLimit)), provider)
    }

    func refreshJevConfiguration() {
        jevAvailable = injectedJev || ((try? APIKeyStore().read(jevProvider)) != nil)
        clearJev()
        jevConfigurationVersion += 1
        Task { await search() }
    }

    private func scheduleJev() {
        guard jevAvailable, !jevScheduled, !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        jevScheduled = true
        let version = jevVersion
        let input = query
        let since = onlyToday ? Calendar.current.startOfDay(for: Date()) : nil
        let app = appFilter.isEmpty ? nil : appFilter
        isJevSearching = true
        jevTask = Task {
            defer { if version == jevVersion { isJevSearching = false } }
            do {
                try await Task.sleep(for: .milliseconds(650))
                guard let ranked = try await jevResults(for: input, since: since, app: app) else {
                    guard version == jevVersion, !Task.isCancelled else { return }
                    jevFailed = true
                    await search()
                    return
                }
                guard version == jevVersion, !Task.isCancelled else { return }
                jevResultsActive = true
                results = ranked
                selection = ranked.first?.id
                jevStatus = "Jev · \(ranked.count) candidates"
            } catch is CancellationError { }
            catch {
                if version == jevVersion {
                    jevFailed = true
                    jevStatus = "Local results · " + error.localizedDescription
                    await search()
                }
            }
        }
    }

    private func clearJev() {
        jevVersion += 1
        jevTask?.cancel()
        isJevSearching = false
        jevResultsActive = false
        jevScheduled = false
        jevFailed = false
        jevStatus = nil
        if jevAvailable && !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            results = []
            selection = nil
        }
    }

    func moveSelection(by offset: Int) {
        guard !results.isEmpty else { return }
        let current = results.firstIndex { $0.id == selection } ?? (offset > 0 ? -1 : results.count)
        selection = results[max(0, min(results.count - 1, current + offset))].id
    }

    func start() {
        guard recordingTask == nil, store != nil else { return }
        isRecording = true
        status = "Recording all displays and available windows"
        recordingTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                let start = Date()
                await self.captureOnce()
                if Task.isCancelled { break }
                let delay = max(0.2, 5 - Date().timeIntervalSince(start))
                do { try await Task.sleep(for: .seconds(delay)) } catch { break }
            }
        }
    }

    func pause() {
        recordingTask?.cancel()
        recordingTask = nil
        isRecording = false
        status = "Recording is paused"
    }

    private func captureOnce() async {
        guard !suspended, let indexer else {
            status = "Waiting for an active screen"
            return
        }
        do {
            var changed = false
            let coverage = try await CaptureEngine.capture(exclusions: excludedIDs, readBrowserURL: readBrowserURL) { key, image, context in
                try Task.checkCancellation()
                guard !self.suspended else { throw CancellationError() }
                if try await indexer.index(image, context: context, display: key) { changed = true }
            }
            try Task.checkCancellation()
            if let diagnostic = try? JSONEncoder().encode(coverage) {
                try? diagnostic.write(to: directory.appendingPathComponent("capture-status.json"), options: .atomic)
            }
            if changed {
                await applyRetention()
                await search()
            }
            if isRecording {
                status = "Recording · \(coverage.displays) displays · \(coverage.windows) windows (\(coverage.offscreenWindows) offscreen)"
                if coverage.unavailable > 0 { status += " · \(coverage.unavailable) unavailable" }
            }
        } catch is CancellationError { }
        catch {
            pause()
            self.error = "Recording stopped. \(error.localizedDescription)"
        }
    }

    func importImage(_ url: URL) async {
        guard let indexer else { return }
        isWorking = true
        defer { isWorking = false }
        do {
            try await indexer.importImage(at: url)
            await applyRetention()
            await search()
        } catch { self.error = error.localizedDescription }
    }

    func applyRetention() async {
        do { try await store?.prune(before: Date().addingTimeInterval(-Double(retentionDays) * 86400)) }
        catch { self.error = error.localizedDescription }
    }

    func deleteSelected() async {
        guard let selection else { return }
        await deleteCapture(id: selection)
    }

    func deleteCapture(id: String) async {
        clearJev()
        do {
            try await store?.delete(id: id)
            await indexer?.reset()
            await search()
        } catch { self.error = error.localizedDescription }
    }

    func deleteAll() async {
        clearJev()
        let pending = recordingTask
        pause()
        await pending?.value
        do {
            try await store?.deleteAll()
            await indexer?.reset()
            await search()
        } catch { self.error = error.localizedDescription }
    }

    func requestAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }
}
