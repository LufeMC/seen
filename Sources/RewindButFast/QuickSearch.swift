import AppKit
import SwiftUI
import Carbon
import RewindCore

@MainActor @Observable
final class QuickSearchModel {
    var query = "" { didSet { if query != oldValue { clearJev() } } }
    var isJevSearching = false
    var jevStatus: String?
    private var jevTask: Task<Void, Never>?
    private var jevVersion = 0
    private var jevResultsActive = false
    private var jevScheduled = false
    private var jevFailed = false
    var results: [Memory] = []
    var selection: String?
    var showingPreview = false
    var isSearching = false
    var error: String?
    private var version = 0
    private let app: AppModel
    init(app: AppModel) { self.app = app }
    var selected: Memory? { results.first { $0.id == selection } }

    func search() async {
        version += 1
        let current = version
        let input = query
        isSearching = true
        defer { if current == version { isSearching = false } }
        do {
            let matches = try await app.quickResults(for: input)
            guard current == version, input == query, !Task.isCancelled else { return }
            if !jevResultsActive && (!app.jevAvailable || input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || jevFailed) { results = matches }
            error = nil
            if !results.contains(where: { $0.id == selection }) { selection = results.first?.id }
            scheduleJev()
        } catch { self.error = "Search is unavailable. Open history to try again." }
    }

    func refreshJevConfiguration() {
        clearJev()
        Task { await search() }
    }

    private func scheduleJev() {
        guard app.jevAvailable, !jevScheduled, !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        jevScheduled = true
        let current = jevVersion
        let input = query
        isJevSearching = true
        jevTask = Task {
            defer { if current == jevVersion { isJevSearching = false } }
            do {
                try await Task.sleep(for: .milliseconds(650))
                guard let ranked = try await app.jevResults(for: input) else {
                    guard current == jevVersion, !Task.isCancelled else { return }
                    jevFailed = true
                    await search()
                    return
                }
                guard current == jevVersion, !Task.isCancelled else { return }
                jevResultsActive = true
                results = ranked
                selection = ranked.first?.id
                jevStatus = "Jev · \(ranked.count) candidates"
            } catch is CancellationError { }
            catch {
                if current == jevVersion {
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
        if app.jevAvailable && !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            results = []
            selection = nil
        }
    }

    func move(_ offset: Int) {
        guard !results.isEmpty else { return }
        let index = results.firstIndex { $0.id == selection } ?? 0
        selection = results[max(0, min(results.count - 1, index + offset))].id
    }
}

@MainActor
final class QuickSearchController: NSObject, NSWindowDelegate {
    private let model: QuickSearchModel
    private let app: AppModel
    private var panel: SearchPanel?
    private var hotKey: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    private var activationObserver: NSObjectProtocol?
    var openHistory: (() -> Void)?
    private(set) var shortcutAvailable = false

    init(app: AppModel) {
        self.app = app
        model = QuickSearchModel(app: app)
        super.init()
        activationObserver = NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification,
            object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.focusPanel() }
            }
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let pointer = Unmanaged.passUnretained(self).toOpaque()
        let handlerStatus = InstallEventHandler(GetApplicationEventTarget(), { _, _, context in
            guard let context else { return OSStatus(eventNotHandledErr) }
            let controller = Unmanaged<QuickSearchController>.fromOpaque(context).takeUnretainedValue()
            Task { @MainActor in controller.toggle() }
            return noErr
        }, 1, &eventType, pointer, &eventHandler)
        guard handlerStatus == noErr else { return }
        let identifier = EventHotKeyID(signature: 0x52574653, id: 1)
        let status = RegisterEventHotKey(UInt32(kVK_Space), UInt32(cmdKey | shiftKey), identifier,
                                        GetApplicationEventTarget(), 0, &hotKey)
        shortcutAvailable = status == noErr
    }

    deinit {
        if let activationObserver { NotificationCenter.default.removeObserver(activationObserver) }
        if let hotKey { UnregisterEventHotKey(hotKey) }
        if let eventHandler { RemoveEventHandler(eventHandler) }
    }

    func toggle() {
        if panel?.isVisible == true { dismiss(); return }
        show()
    }

    func show() {
        NSApp.unhideWithoutActivation()
        if panel == nil {
            let created = SearchPanel(contentRect: NSRect(x: 0, y: 0, width: 740, height: 590),
                                      styleMask: [.borderless], backing: .buffered, defer: false)
            created.title = "Quick search"
            created.identifier = NSUserInterfaceItemIdentifier("quick-search")
            created.isFloatingPanel = true
            created.level = .floating
            created.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
            created.isOpaque = false
            created.backgroundColor = .clear
            created.hasShadow = true
            created.hidesOnDeactivate = false
            created.isMovableByWindowBackground = true
            created.becomesKeyOnlyIfNeeded = false
            created.delegate = self
            panel = created
        }
        guard let panel else { return }
        model.showingPreview = false
        panel.contentView = NSHostingView(rootView: QuickSearchView(model: model, app: app,
            close: { [weak self] in self?.dismiss() },
            resize: { [weak self] preview in self?.resize(preview: preview) },
            openHistory: { [weak self] in
                guard let self else { return }
                self.app.query = self.model.query
                self.app.appFilter = ""
                self.app.onlyToday = false
                self.dismiss()
                self.openHistory?()
            }))
        resize(preview: false)
        panel.orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        focusPanel()
        Task { await model.search() }
    }

    private func focusPanel() {
        guard let panel, panel.isVisible else { return }
        panel.contentView?.layoutSubtreeIfNeeded()
        panel.makeKeyAndOrderFront(nil)
        if let field = panel.initialFirstResponder { panel.makeFirstResponder(field) }
    }

    private func resize(preview: Bool) {
        guard let panel else { return }
        let pointer = NSEvent.mouseLocation
        let screen = panel.isVisible ? panel.screen : NSScreen.screens.first { NSMouseInRect(pointer, $0.frame, false) }
        guard let bounds = (screen ?? NSScreen.main)?.visibleFrame else { return }
        let width = min(preview ? 1120.0 : 740.0, bounds.width - 40)
        let height = min(preview ? 820.0 : 590.0, bounds.height - 40)
        let frame = NSRect(x: bounds.midX - width / 2, y: bounds.midY - height / 2, width: width, height: height)
        panel.setFrame(frame, display: true)
    }

    func dismiss() { panel?.orderOut(nil) }
    func windowDidResignKey(_ notification: Notification) { dismiss() }
}

private final class SearchPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

private struct QuickSearchView: View {
    @Bindable var model: QuickSearchModel
    let app: AppModel
    let close: () -> Void
    let resize: (Bool) -> Void
    let openHistory: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                AppMark(size: 44)
                PanelSearchField(text: $model.query, move: { model.move($0) },
                    submit: { if model.selected != nil { model.showingPreview = true } },
                    escape: { if model.showingPreview { model.showingPreview = false } else { close() } })
                    .frame(height: 34)
                Button(action: close) { KeyCap(text: "esc") }.buttonStyle(.plain).accessibilityLabel("Close quick search")
            }.padding(model.showingPreview ? 14 : 22)
            if !model.showingPreview {
                JevSearchStatus(busy: model.isJevSearching, status: model.jevStatus)
                    .padding(.horizontal, 22).padding(.bottom, 12)
            }
            Rectangle().fill(Style.line).frame(height: 1)
            if model.showingPreview, let memory = model.selected {
                HStack {
                    Button { model.showingPreview = false } label: { Label("Back to results", systemImage: "arrow.left") }
                        .buttonStyle(.plain).foregroundStyle(Style.accent)
                    Spacer()
                }.font(Style.small).padding(.horizontal, 24).padding(.top, 10)
                MemoryDetail(memory: memory, query: model.query, compact: true).padding(.vertical, 8).padding(.horizontal, 4)
            } else if let error = model.error {
                emptyState(title: "Search unavailable", detail: error)
            } else if model.results.isEmpty {
                emptyState(title: (model.isSearching || model.isJevSearching) ? "Searching…" : "No matching captures",
                           detail: "Try an app name, a title, or words you remember.")
            } else {
                HStack {
                    Text(model.query.isEmpty ? "RECENT CAPTURES" : "MATCHING CAPTURES").tracking(1.2)
                    Spacer()
                    if model.isSearching { ProgressView().controlSize(.mini) }
                    else { Text("\(model.results.count)\(model.results.count == 30 ? "+" : "")") }
                }.font(.system(size: 10, weight: .semibold, design: .rounded)).foregroundStyle(Style.secondary)
                    .padding(.horizontal, 28).padding(.top, 18).padding(.bottom, 8)
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 4) {
                            ForEach(model.results) { memory in
                                Button {
                                    model.selection = memory.id
                                    model.showingPreview = true
                                } label: {
                                    CaptureRow(memory: memory, query: model.query, selected: memory.id == model.selection, compact: true)
                                }.buttonStyle(.plain).id(memory.id)
                            }
                        }.padding(.horizontal, 16).padding(.bottom, 12)
                    }.onChange(of: model.selection) { if let id = model.selection { proxy.scrollTo(id) } }
                }
            }
            Rectangle().fill(Style.line).frame(height: 1)
            HStack(spacing: 8) {
                Circle().fill(app.isRecording ? Color.green : Style.secondary).frame(width: 6, height: 6)
                Text(app.isRecording ? "Recording" : "Paused").foregroundStyle(Style.secondary)
                Spacer()
                if !model.showingPreview { KeyCap(text: "↵"); Text("Preview").foregroundStyle(Style.secondary) }
                Button(action: openHistory) { Label("Open history", systemImage: "arrow.up.right.square") }
                    .buttonStyle(QuietButtonStyle()).padding(.leading, 10)
            }.font(Style.small).padding(.horizontal, 24).padding(.vertical, 12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity).font(Style.body).foregroundStyle(Style.primary).tint(Style.accent)
        .background(Style.background, in: .rect(cornerRadius: 22))
        .overlay(RoundedRectangle(cornerRadius: 22).strokeBorder(Style.line, lineWidth: 1))
        .clipShape(.rect(cornerRadius: 22))
        .onExitCommand { if model.showingPreview { model.showingPreview = false } else { close() } }
        .onChange(of: app.jevConfigurationVersion) { model.refreshJevConfiguration() }
        .onChange(of: model.showingPreview) { resize(model.showingPreview) }
        .task(id: model.query) {
            model.showingPreview = false
            do { try await Task.sleep(for: .milliseconds(120)) } catch { return }
            await model.search()
        }
    }

    private func emptyState(title: String, detail: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "doc.text.magnifyingglass").font(.system(size: 32, weight: .light)).foregroundStyle(Style.accent)
            Text(title).font(Style.heading)
            Text(detail).foregroundStyle(Style.secondary)
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
