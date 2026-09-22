import AppKit
import ScreenCaptureKit
import Vision
import CryptoKit
import ImageIO
import UniformTypeIdentifiers
import CoreImage
import RewindCore

struct CaptureContext: Sendable {
    let app: String
    let bundleID: String
    let title: String
    let url: String?
}

actor ImageIndexer {
    private let store: MemoryStore
    private let directory: URL
    private var lastSignatures: [String: String] = [:]

    init(store: MemoryStore, directory: URL) {
        self.store = store
        self.directory = directory
    }

    func reset() { lastSignatures.removeAll() }

    func index(_ image: CGImage, context: CaptureContext, display: String, deduplicate: Bool = true) async throws -> Bool {
        try Task.checkCancellation()
        let metadata = context.bundleID + context.title + (context.url ?? "")
        let signature = fingerprint(image, metadata: metadata)
        if deduplicate && lastSignatures[display] == signature { return false }
        let text = try recognize(image)
        try Task.checkCancellation()
        let id = UUID().uuidString
        let url = directory.appendingPathComponent("images/\(id).jpg")
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.jpeg.identifier as CFString, 1, nil) else {
            throw CocoaError(.fileWriteUnknown)
        }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.65] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw CocoaError(.fileWriteUnknown) }
        do {
            try Task.checkCancellation()
            try await store.insert(Memory(id: id, app: context.app, title: context.title,
                text: text, imagePath: url.path, sourceURL: context.url))
            lastSignatures[display] = signature
            return true
        } catch {
            try? FileManager.default.removeItem(at: url)
            throw error
        }
    }

    private func recognize(_ image: CGImage) throws -> String {
        let tileSize = 1280
        let strideSize = 1152
        var lines: [String] = []
        var seen = Set<String>()
        for y in stride(from: 0, to: image.height, by: strideSize) {
            for x in stride(from: 0, to: image.width, by: strideSize) {
                try Task.checkCancellation()
                let rect = CGRect(x: x, y: y, width: min(tileSize, image.width - x), height: min(tileSize, image.height - y))
                guard let tile = image.cropping(to: rect) else { continue }
                let request = VNRecognizeTextRequest()
                request.recognitionLevel = .accurate
                request.minimumTextHeight = 0.002
                request.usesLanguageCorrection = true
                request.automaticallyDetectsLanguage = true
                try VNImageRequestHandler(cgImage: tile).perform([request])
                for line in (request.results ?? []).compactMap({ $0.topCandidates(1).first?.string }) {
                    if seen.insert(line).inserted { lines.append(line) }
                }
            }
        }
        return lines.joined(separator: "\n")
    }

    private func fingerprint(_ image: CGImage, metadata: String) -> String {
        var hasher = SHA256()
        hasher.update(data: Data(metadata.utf8))
        if let data = image.dataProvider?.data { hasher.update(data: data as Data) }
        return hasher.finalize().description
    }

    func importImage(at url: URL) async throws {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { throw CocoaError(.fileReadCorruptFile) }
        _ = try await index(image, context: CaptureContext(app: "Imported image", bundleID: "import",
            title: url.deletingPathExtension().lastPathComponent, url: nil), display: "import", deduplicate: false)
    }
}

@MainActor
enum CaptureEngine {
    static let defaultExclusions = "com.1password.1password\ncom.agilebits.onepassword7\ncom.apple.Passwords\ncom.bitwarden.desktop\norg.keepassxc.keepassxc"

    static func context(readBrowserURL: Bool) -> CaptureContext {
        let app = NSWorkspace.shared.frontmostApplication
        var title = app?.localizedName ?? "Screen"
        var sourceURL: String?
        if AXIsProcessTrusted(), let pid = app?.processIdentifier {
            let application = AXUIElementCreateApplication(pid)
            AXUIElementSetMessagingTimeout(application, 0.15)
            if let window = attribute(application, kAXFocusedWindowAttribute) {
                let element = unsafeBitCast(window, to: AXUIElement.self)
                title = attribute(element, kAXTitleAttribute) as? String ?? title
                if readBrowserURL {
                    sourceURL = documentURL(element)
                }
            }
        }
        return CaptureContext(app: app?.localizedName ?? "Screen", bundleID: app?.bundleIdentifier ?? "",
            title: title, url: sourceURL)
    }

    private static func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value
    }

    private static func documentURL(_ window: AXUIElement) -> String? {
        var queue = [window]
        var count = 0
        let deadline = Date().addingTimeInterval(0.2)
        while !queue.isEmpty && count < 100 && Date() < deadline {
            let element = queue.removeFirst()
            count += 1
            if let value = attribute(element, kAXDocumentAttribute) as? String,
               SearchQuery.safeURL(value) != nil { return value }
            if let children = attribute(element, kAXChildrenAttribute) as? [AXUIElement] {
                queue.append(contentsOf: children.prefix(30))
            }
        }
        return nil
    }

    struct Coverage: Codable {
        var displays = 0
        var windows = 0
        var offscreenWindows = 0
        var unavailable = 0
        var failures: [String] = []
        var skippedWindows: [String] = []
    }

    static func capture(exclusions: Set<String>, readBrowserURL: Bool,
                        consume: (String, CGImage, CaptureContext) async throws -> Void) async throws -> Coverage {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
        try Task.checkCancellation()
        let excluded = content.applications.filter {
            exclusions.contains($0.bundleIdentifier) || $0.processID == ProcessInfo.processInfo.processIdentifier
        }
        var coverage = Coverage()
        for (number, display) in content.displays.enumerated() {
            try Task.checkCancellation()
            let filter = SCContentFilter(display: display, excludingApplications: excluded, exceptingWindows: [])
            let config = SCStreamConfiguration()
            let scale = min(2.0, 2560.0 / Double(display.width))
            config.width = Int(Double(display.width) * scale)
            config.height = Int(Double(display.height) * scale)
            config.showsCursor = false
            config.capturesAudio = false
            let image: CGImage
            do { image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config) }
            catch {
                coverage.unavailable += 1
                coverage.failures.append("Display \(display.displayID): \(error.localizedDescription)")
                continue
            }
            try await consume("display-\(display.displayID)", image,
                CaptureContext(app: "Display \(number + 1)", bundleID: "display.\(display.displayID)",
                    title: "Full display · active desktop", url: nil))
            coverage.displays += 1
        }
        let active = context(readBrowserURL: readBrowserURL)
        for window in content.windows {
            try Task.checkCancellation()
            guard let app = window.owningApplication,
                  !exclusions.contains(app.bundleIdentifier),
                  app.processID != ProcessInfo.processInfo.processIdentifier else { continue }
            guard window.windowLayer == 0, window.frame.width > 80, window.frame.height > 80 else {
                coverage.skippedWindows.append("\(app.applicationName): layer \(window.windowLayer), size \(window.frame.width) × \(window.frame.height)")
                continue
            }
            let filter = SCContentFilter(desktopIndependentWindow: window)
            let config = SCStreamConfiguration()
            let scale = min(2.0, 2560.0 / window.frame.width)
            config.width = max(1, Int(window.frame.width * scale))
            config.height = max(1, Int(window.frame.height * scale))
            config.showsCursor = false
            config.capturesAudio = false
            let image: CGImage
            do {
                do { image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config) }
                catch { image = try await WindowFrameGrabber.capture(filter: filter, configuration: config) }
            } catch {
                try Task.checkCancellation()
                coverage.unavailable += 1
                coverage.failures.append("\(app.applicationName), window \(window.windowID), onscreen \(window.isOnScreen): \(error.localizedDescription)")
                continue
            }
            let title = window.title.flatMap { $0.isEmpty ? nil : $0 } ?? app.applicationName
            let sourceURL = app.bundleIdentifier == active.bundleID && title == active.title ? active.url : nil
            try await consume("window-\(window.windowID)", image,
                CaptureContext(app: app.applicationName, bundleID: app.bundleIdentifier, title: title, url: sourceURL))
            coverage.windows += 1
            if !window.isOnScreen { coverage.offscreenWindows += 1 }
        }
        return coverage
    }
}

private final class WindowFrameGrabber: NSObject, SCStreamOutput, SCStreamDelegate {
    private let continuation: AsyncThrowingStream<CGImage, Error>.Continuation
    private let imageContext = CIContext()

    init(continuation: AsyncThrowingStream<CGImage, Error>.Continuation) {
        self.continuation = continuation
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer buffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, buffer.isValid,
              let attachments = CMSampleBufferGetSampleAttachmentsArray(buffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
              let status = attachments.first?[.status] as? Int,
              status == SCFrameStatus.complete.rawValue,
              let pixelBuffer = buffer.imageBuffer else { return }
        let source = CIImage(cvPixelBuffer: pixelBuffer)
        if let image = imageContext.createCGImage(source, from: source.extent) {
            continuation.yield(image)
            continuation.finish()
        }
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        continuation.finish(throwing: error)
    }

    @MainActor
    static func capture(filter: SCContentFilter, configuration: SCStreamConfiguration) async throws -> CGImage {
        let (frames, continuation) = AsyncThrowingStream<CGImage, Error>.makeStream(bufferingPolicy: .bufferingNewest(1))
        let receiver = WindowFrameGrabber(continuation: continuation)
        let stream = SCStream(filter: filter, configuration: configuration, delegate: receiver)
        try stream.addStreamOutput(receiver, type: .screen, sampleHandlerQueue: DispatchQueue(label: "rewind.window-frame"))
        let timeout = Task {
            do {
                try await Task.sleep(for: .seconds(3))
                continuation.finish(throwing: NSError(domain: "RewindCapture", code: 1,
                    userInfo: [NSLocalizedDescriptionKey: "macOS did not provide a window image within three seconds."]))
            } catch { }
        }
        defer { timeout.cancel() }
        return try await withTaskCancellationHandler {
            do {
                try await stream.startCapture()
                var iterator = frames.makeAsyncIterator()
                guard let image = try await iterator.next() else { throw CancellationError() }
                try? await stream.stopCapture()
                return image
            } catch {
                try? await stream.stopCapture()
                throw error
            }
        } onCancel: {
            continuation.finish(throwing: CancellationError())
        }
    }
}
