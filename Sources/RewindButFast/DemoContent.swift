import AppKit
import RewindCore

@MainActor
enum DemoContent {
    static func seed(directory: URL) async throws {
        let store = try MemoryStore(directory: directory)
        let entries = [
            ("Notes", "Launch plan", "The launch is scheduled for Friday.\n\nBefore launch\nFinish the setup guide.\nCheck keyboard search.\nRecord a short product demo.\n\nKeep the first release small and useful."),
            ("Safari", "Designing a useful search", "Start with the words people remember.\n\nShow the source beside each result.\nKeep keyboard navigation predictable.\nMake captured text large enough to read.\n\nLaunch with a clear path from question to source."),
            ("TextEdit", "Release checklist", "Release checklist\n\nBuild the app.\nRun the tests.\nReview the permissions.\nPublish the source code.\n\nThe launch date is Friday.")
        ]
        for (index, entry) in entries.enumerated() {
            let image = NSImage(size: NSSize(width: 1200, height: 860))
            image.lockFocus()
            NSColor(calibratedRed: 0.97, green: 0.96, blue: 0.94, alpha: 1).setFill()
            NSRect(x: 0, y: 0, width: 1200, height: 860).fill()
            let ink = NSColor(calibratedRed: 0.15, green: 0.14, blue: 0.19, alpha: 1)
            ("FIELD NOTES     /     DEMO CONTENT" as NSString).draw(at: NSPoint(x: 88, y: 760),
                withAttributes: [.font: NSFont.monospacedSystemFont(ofSize: 18, weight: .medium), .foregroundColor: ink])
            (entry.1 as NSString).draw(at: NSPoint(x: 88, y: 640),
                withAttributes: [.font: NSFont.systemFont(ofSize: 52, weight: .semibold), .foregroundColor: ink])
            (entry.2 as NSString).draw(in: NSRect(x: 88, y: 110, width: 1000, height: 480),
                withAttributes: [.font: NSFont.systemFont(ofSize: 27), .foregroundColor: ink])
            image.unlockFocus()
            guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil),
                  let data = NSBitmapImageRep(cgImage: cgImage).representation(using: .jpeg, properties: [.compressionFactor: 0.9]) else { continue }
            let path = directory.appendingPathComponent("images/demo-\(index).jpg")
            try data.write(to: path)
            try await store.insert(Memory(date: Date().addingTimeInterval(Double(-index * 300)), app: entry.0,
                title: entry.1, text: entry.2, imagePath: path.path))
        }
    }
}
