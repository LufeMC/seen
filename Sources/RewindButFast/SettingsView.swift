import SwiftUI

struct SettingsView: View {
    @Bindable var model: AppModel
    var shortcutAvailable = true
    @State private var confirmDeletion = false
    var body: some View {
        Form {
            Section("Startup and search") {
                Toggle("Start recording when the app opens", isOn: $model.recordOnLaunch)
                Text("Press Shift-Command-Space to search from any app. Command-Q hides Seen and keeps recording active.")
                    .foregroundStyle(.secondary)
                if !shortcutAvailable {
                    Text("Another app may use this shortcut. Use Quick search from the menu bar.")
                        .foregroundStyle(.orange)
                }
            }
            JevSettingsSection(model: model)
            Section("Capture scope") {
                Text("All connected displays and available app windows across macOS desktops.")
                Text("macOS can withhold minimized or protected windows. The menu bar control reports capture failures.")
                    .foregroundStyle(.secondary)
            }
            Section("History") {
                Picker("Keep captures for", selection: $model.retentionDays) {
                    Text("1 day").tag(1)
                    Text("7 days").tag(7)
                    Text("30 days").tag(30)
                }
                Text("The app also limits history to 5,000 captures. Older captures are deleted first.")
                    .foregroundStyle(.secondary)
            }
            Section("Page links") {
                Toggle("Read page links through Accessibility", isOn: $model.readBrowserURL)
                Text("Supported browsers can provide the active page link. A feed link can differ from an individual post link.")
                    .foregroundStyle(.secondary)
                Button("Allow Accessibility…") { model.requestAccessibility() }
            }
            Section("Excluded apps") {
                Text("Enter one bundle identifier per line. These apps are excluded from captures.")
                    .foregroundStyle(.secondary)
                TextEditor(text: $model.exclusions)
                    .font(.system(size: 12, design: .monospaced)).frame(height: 100)
                    .accessibilityLabel("Excluded app bundle identifiers")
                Text("Private browser windows are not detected automatically. Pause recording or exclude the browser to omit them.")
                    .foregroundStyle(.secondary)
            }
            Section("Local storage") {
                Button("Show history folder") { NSWorkspace.shared.open(model.directory) }
                Button("Delete all history…", role: .destructive) { confirmDeletion = true }
                    .disabled(model.isWorking)
                Text("Images and text are stored without app-level encryption. Optional Jev searches send selected text to your provider.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .font(Style.body)
        .frame(width: 560, height: 660)
        .task(id: model.retentionDays) { await model.applyRetention(); await model.search() }
        .confirmationDialog("Delete all history?", isPresented: $confirmDeletion) {
            Button("Delete all history", role: .destructive) { Task { await model.deleteAll() } }
        } message: { Text("Recording will stop. All saved images and recognized text will be deleted.") }
    }
}
