import SwiftUI
import AppKit
import RewindCore

@MainActor @Observable
final class AppRuntime {
    let model: AppModel
    private let demo = CommandLine.arguments.contains("--demo")
    private var initialized = false
    let quickSearch: QuickSearchController
    init() {
        if demo {
            let defaults = UserDefaults(suiteName: "Seen.Demo")!
            defaults.set(false, forKey: "recordOnLaunch")
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent("SeenDemo-" + UUID().uuidString)
            model = AppModel(defaults: defaults, directory: directory, jevOperation: { _, _, _ in nil })
            model.jevAvailable = false
        } else { model = AppModel() }
        quickSearch = QuickSearchController(app: model)
    }
    func initialize() async {
        guard !initialized else { return }
        initialized = true
        if demo {
            do { try await DemoContent.seed(directory: model.directory) }
            catch { model.error = error.localizedDescription }
        }
        await model.initialize()
    }
}

@main
struct RewindButFastApp: App {
    @State private var runtime = AppRuntime()
    var body: some Scene {
        Window("Seen", id: "history") {
            HistoryRoot(runtime: runtime)
        }
        .defaultSize(width: 1120, height: 780)
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .appTermination) {
                Button("Keep Seen in Menu Bar") {
                    for window in NSApp.windows where window.isVisible { window.orderOut(nil) }
                    NSApp.setActivationPolicy(.accessory)
                    NSApp.hide(nil)
                }.keyboardShortcut("q")
                Button("Quit Seen Completely") { NSApp.terminate(nil) }.keyboardShortcut("q", modifiers: [.command, .option])
            }
            CommandGroup(after: .newItem) {
                Button("Quick search") { runtime.quickSearch.toggle() }
                Button(runtime.model.isRecording ? "Pause recording" : "Start recording") {
                    runtime.model.isRecording ? runtime.model.pause() : runtime.model.start()
                }.keyboardShortcut("r", modifiers: [.command, .shift])
            }
        }
        Settings { SettingsView(model: runtime.model, shortcutAvailable: runtime.quickSearch.shortcutAvailable).tint(Style.accent) }
        MenuBarExtra("Seen", systemImage: runtime.model.isRecording ? "backward.circle.fill" : "backward.circle") {
            MenuContent(runtime: runtime)
        }
    }
}

private struct HistoryRoot: View {
    let runtime: AppRuntime
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        HistoryView(model: runtime.model, quickSearch: { runtime.quickSearch.toggle() })
            .task {
                runtime.quickSearch.openHistory = {
                    openWindow(id: "history")
                    NSApp.activate(ignoringOtherApps: true)
                }
                await runtime.initialize()
            }
    }
}

private struct MenuContent: View {
    let runtime: AppRuntime
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        Button("Quick search    ⇧⌘Space") { runtime.quickSearch.show() }
        Button("Open history") {
            openWindow(id: "history")
            NSApp.activate(ignoringOtherApps: true)
        }
        Divider()
        Text(runtime.model.status)
        Button(runtime.model.isRecording ? "Pause recording" : "Start recording") {
            runtime.model.isRecording ? runtime.model.pause() : runtime.model.start()
        }
        Divider()
        SettingsLink()
        Button("Quit Seen Completely") { NSApp.terminate(nil) }
    }
}
