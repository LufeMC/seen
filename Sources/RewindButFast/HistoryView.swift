import SwiftUI
import UniformTypeIdentifiers
import RewindCore

struct HistoryView: View {
    @Bindable var model: AppModel
    let quickSearch: () -> Void
    @State private var showImporter = false
    @State private var pendingDeletion: Memory?
    @FocusState private var searchFocused: Bool
    private var hasFilters: Bool { model.onlyToday || !model.appFilter.isEmpty }
    private var searchIdentity: String { "\(model.query)\u{0}\(model.onlyToday)\u{0}\(model.appFilter)" }

    var body: some View {
        VStack(spacing: 0) {
            header
            searchBar
            JevSearchStatus(busy: model.isJevSearching, status: model.jevStatus)
                .padding(.horizontal, 28).padding(.bottom, 10)
            if model.count == 0 {
                emptyHistory
            } else if model.results.isEmpty {
                emptyResults
            } else {
                HSplitView {
                    resultList.frame(minWidth: 280, idealWidth: 330, maxWidth: 390)
                    if let memory = model.selected {
                        MemoryDetail(memory: memory, query: model.query, onDelete: { pendingDeletion = memory })
                            .frame(minWidth: 360, maxWidth: .infinity, maxHeight: .infinity)
                    }
                }.padding(.horizontal, 16).padding(.bottom, 12)
            }
            footer
        }
        .font(Style.body).foregroundStyle(Style.primary).tint(Style.accent)
        .background(Style.background)
        .frame(minWidth: 780, minHeight: 580)
        .defaultFocus($searchFocused, true)
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.png, .jpeg, .heic, .tiff]) { result in
            switch result {
            case .success(let url): Task { await model.importImage(url) }
            case .failure(let error): model.error = error.localizedDescription
            }
        }
        .task(id: searchIdentity) {
            do { try await Task.sleep(for: .milliseconds(150)) } catch { return }
            await model.search()
        }
        .alert("Unable to complete the action", isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })) {
            Button("Close") { model.error = nil }
        } message: { Text(model.error ?? "") }
        .confirmationDialog("Delete this capture?", isPresented: Binding(get: { pendingDeletion != nil }, set: { if !$0 { pendingDeletion = nil } })) {
            if let memory = pendingDeletion {
                Button("Delete capture", role: .destructive) {
                    Task { await model.deleteCapture(id: memory.id) }
                    pendingDeletion = nil
                }
            }
            Button("Cancel", role: .cancel) { pendingDeletion = nil }
        } message: { Text("The saved image and text will be deleted.") }
        .background {
            Button("Focus search") { searchFocused = true }.keyboardShortcut("f").hidden()
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            AppMark(size: 42)
            VStack(alignment: .leading, spacing: 3) {
                Text("Seen").font(.system(size: 17, weight: .semibold, design: .rounded))
                Text("Your screen history, searchable.").font(Style.small).foregroundStyle(Style.secondary)
            }
            Spacer()
            Button(action: quickSearch) {
                HStack(spacing: 10) { Text("Quick search"); KeyCap(text: "⇧⌘Space") }
            }.buttonStyle(QuietButtonStyle()).help("Search from any app with Shift-Command-Space")
            Menu {
                Button("Import image…", systemImage: "square.and.arrow.down") { showImporter = true }.disabled(model.isWorking)
                Button("Show history folder", systemImage: "folder") { NSWorkspace.shared.open(model.directory) }
                Divider()
                SettingsLink { Label("Settings…", systemImage: "gearshape") }
            } label: {
                Image(systemName: "ellipsis").font(.system(size: 18, weight: .medium)).frame(width: 36, height: 36)
            }
            .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().accessibilityLabel("More options")
        }.font(Style.small).padding(.horizontal, 26).padding(.top, 16).padding(.bottom, 22)
    }

    private var searchBar: some View {
        VStack(spacing: 16) {
            HStack(spacing: 14) {
                Image(systemName: "magnifyingglass").font(.system(size: 24, weight: .regular))
                    .foregroundStyle(Style.accent).accessibilityHidden(true)
                TextField("Ask about something you saw…", text: $model.query)
                    .font(Style.heading).textFieldStyle(.plain).focused($searchFocused)
                    .accessibilityLabel("Search screen history")
                    .onKeyPress(.downArrow) { model.moveSelection(by: 1); return .handled }
                    .onKeyPress(.upArrow) { model.moveSelection(by: -1); return .handled }
                    .onKeyPress(.escape) { model.query = ""; return .handled }
                if !model.query.isEmpty {
                    Button("Clear search", systemImage: "xmark.circle.fill") { model.query = "" }
                        .labelStyle(.iconOnly).buttonStyle(.plain).foregroundStyle(Style.secondary)
                        .frame(width: 32, height: 32).help("Clear search · Escape")
                } else { KeyCap(text: "⌘F") }
            }
            .padding(.horizontal, 20).frame(height: 66)
            .background(Style.surface, in: .rect(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(searchFocused ? Style.accent.opacity(0.65) : Style.line, lineWidth: searchFocused ? 2 : 1))
            .shadow(color: .black.opacity(0.035), radius: 10, y: 4)
            HStack(spacing: 10) {
                Menu {
                    Button("All apps") { model.appFilter = "" }
                    Divider()
                    ForEach(model.applications, id: \.self) { app in Button(app) { model.appFilter = app } }
                } label: { filterLabel(model.appFilter.isEmpty ? "All apps" : model.appFilter, symbol: "square.grid.2x2") }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Filter by app").accessibilityValue(model.appFilter.isEmpty ? "All apps" : model.appFilter)
                Menu {
                    Button("Any time") { model.onlyToday = false }
                    Button("Today") { model.onlyToday = true }
                } label: { filterLabel(model.onlyToday ? "Today" : "Any time", symbol: "calendar") }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Filter by date").accessibilityValue(model.onlyToday ? "Today" : "Any time")
                if hasFilters {
                    Button("Clear filters") { model.onlyToday = false; model.appFilter = "" }
                        .buttonStyle(.plain).foregroundStyle(Style.accent)
                }
                Spacer()
                if model.isSearching || model.isWorking {
                    ProgressView().controlSize(.small).accessibilityLabel(model.isWorking ? "Reading image" : "Searching")
                } else { Text(resultSummary).foregroundStyle(Style.secondary) }
            }.font(Style.small).menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize(horizontal: false, vertical: true)
        }.padding(.horizontal, 28).padding(.bottom, 20)
    }

    private func filterLabel(_ title: String, symbol: String) -> some View {
        HStack(spacing: 7) {
            Image(systemName: symbol)
            Text(title).lineLimit(1).truncationMode(.middle).frame(maxWidth: 180)
            Image(systemName: "chevron.down").font(.system(size: 9, weight: .semibold))
        }.foregroundStyle(Style.secondary).padding(.horizontal, 12).padding(.vertical, 8)
            .background(Style.surface.opacity(0.7), in: .capsule)
            .overlay(Capsule().strokeBorder(Style.line, lineWidth: 0.5)).fixedSize()
    }

    private var resultSummary: String {
        if model.count == 0 { return "" }
        if model.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return "Recent captures" }
        if model.results.count == 150 { return "Top 150 results" }
        return model.results.count == 1 ? "1 result" : "\(model.results.count) results"
    }

    private var resultList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 6) {
                    ForEach(model.results) { memory in
                        Button { model.selection = memory.id } label: {
                            CaptureRow(memory: memory, query: model.query, selected: memory.id == model.selection)
                        }.buttonStyle(.plain).id(memory.id)
                            .contextMenu {
                                Button("Open image", systemImage: "arrow.up.right.square") { NSWorkspace.shared.open(URL(fileURLWithPath: memory.imagePath)) }
                                Button("Copy text", systemImage: "doc.on.doc") { copyText(memory.text) }.disabled(memory.text.isEmpty)
                                Divider()
                                Button("Delete capture…", systemImage: "trash", role: .destructive) { pendingDeletion = memory }
                            }
                    }
                }.padding(.horizontal, 10).padding(.vertical, 2)
            }
            .onChange(of: model.selection) { if let id = model.selection { proxy.scrollTo(id) } }
            .onKeyPress(.downArrow) { model.moveSelection(by: 1); return .handled }
            .onKeyPress(.upArrow) { model.moveSelection(by: -1); return .handled }
        }
    }

    private var emptyHistory: some View {
        VStack(spacing: 16) {
            AppMark(size: 76)
            Text(model.isRecording ? "Your history is starting" : "Find it again, right here").font(Style.heading)
            Text(model.isRecording ? "Your first captures will appear shortly." : "Start recording to save what appears on your Mac.")
                .foregroundStyle(Style.secondary)
            if !model.isRecording {
                Button("Start recording", systemImage: "record.circle") { model.start() }.buttonStyle(.borderedProminent).controlSize(.large)
            }
            Button("Import an image…") { showImporter = true }.buttonStyle(.plain).foregroundStyle(Style.accent).disabled(model.isWorking)
        }.padding(32).frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyResults: some View {
        VStack(spacing: 14) {
            Image(systemName: "doc.text.magnifyingglass").font(.system(size: 36, weight: .light)).foregroundStyle(Style.accent)
            Text((model.isSearching || model.isJevSearching) ? "Searching…" : "No matching captures").font(Style.heading)
            Text(hasFilters ? "Try different words or clear the filters." : "Try fewer words, an app name, or part of a title.").foregroundStyle(Style.secondary)
            Button(hasFilters ? "Clear filters" : "Show recent captures") {
                if hasFilters { model.appFilter = ""; model.onlyToday = false } else { model.query = "" }
            }.buttonStyle(QuietButtonStyle())
        }.padding(32).frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var footer: some View {
        HStack(spacing: 12) {
            Button { model.isRecording ? model.pause() : model.start() } label: {
                HStack(spacing: 8) {
                    Circle().fill(model.isRecording ? Color.green : Style.secondary).frame(width: 6, height: 6)
                    Text(model.isRecording ? "Recording" : "Paused")
                    Image(systemName: model.isRecording ? "pause.fill" : "play.fill").font(.system(size: 9, weight: .semibold))
                }
            }.buttonStyle(QuietButtonStyle()).help(model.status)
                .accessibilityLabel(model.isRecording ? "Pause recording" : "Start recording")
            Label("Stored on this Mac", systemImage: "internaldrive").foregroundStyle(Style.secondary)
            Spacer()
            KeyCap(text: "↑ ↓")
            Text("Select").foregroundStyle(Style.secondary)
        }.font(Style.small).padding(.horizontal, 28).padding(.bottom, 14).padding(.top, 4)
    }
}

struct MemoryDetail: View {
    let memory: Memory
    let query: String
    var onDelete: (() -> Void)? = nil
    var compact = false
    @State private var showText = false
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: compact ? 6 : 10) {
                HStack {
                    Label(memory.app, systemImage: "macwindow").foregroundStyle(Style.accent).lineLimit(1)
                    Spacer()
                    Text(memory.date, format: .dateTime.month(.abbreviated).day().hour().minute()).foregroundStyle(Style.secondary)
                }.font(Style.small)
                Text(memory.title).font(.system(size: 19, weight: .semibold, design: .rounded))
                    .lineLimit(compact ? 1 : 2).textSelection(.enabled).help(memory.title)
                HStack(spacing: 12) {
                    Picker("Preview", selection: $showText) {
                        Text("Image").tag(false)
                        Text("Text").tag(true)
                    }.pickerStyle(.segmented).labelsHidden().frame(width: 144).accessibilityLabel("Preview mode")
                    Spacer()
                    if let url = SearchQuery.safeURL(memory.sourceURL) {
                        Link(destination: url) { Label("Open page", systemImage: "arrow.up.right") }.help(url.absoluteString)
                    }
                    Menu {
                        Button("Open image", systemImage: "arrow.up.right.square") { NSWorkspace.shared.open(URL(fileURLWithPath: memory.imagePath)) }
                        Button("Copy text", systemImage: "doc.on.doc") { copyText(memory.text) }.disabled(memory.text.isEmpty)
                        if let onDelete {
                            Divider()
                            Button("Delete capture…", systemImage: "trash", role: .destructive, action: onDelete)
                        }
                    } label: { Image(systemName: "ellipsis").frame(width: 32, height: 32) }
                    .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().accessibilityLabel("Capture actions")
                }.font(Style.small).padding(.top, 4)
            }.padding(compact ? 14 : 18)
            if showText {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        if memory.text.isEmpty { Text("No text was detected in this image.").foregroundStyle(Style.secondary) }
                        else {
                            Text(highlighted(memory.text, query: query)).textSelection(.enabled).lineSpacing(6).frame(maxWidth: .infinity, alignment: .leading)
                            Button(copied ? "Copied" : "Copy text", systemImage: copied ? "checkmark" : "doc.on.doc") {
                                copyText(memory.text); copied = true
                            }.buttonStyle(QuietButtonStyle())
                        }
                    }.padding(22)
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ImageViewer(path: memory.imagePath)
                    .padding(.horizontal, 10).padding(.bottom, 10)
            }
        }
        .background(Style.surface, in: .rect(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Style.line.opacity(0.65), lineWidth: 0.5))
        .padding(.leading, 12).padding(.trailing, 10)
        .onChange(of: memory.id) { copied = false }
    }
}
