import SwiftUI
import ImageIO
import RewindCore

enum Style {
    static func adaptive(_ light: UInt32, _ dark: UInt32) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let value = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
            return NSColor(srgbRed: CGFloat((value >> 16) & 255) / 255,
                           green: CGFloat((value >> 8) & 255) / 255,
                           blue: CGFloat(value & 255) / 255, alpha: 1)
        })
    }
    static let accent = adaptive(0x6550C9, 0xB9ABFF)
    static let background = adaptive(0xF6F5FA, 0x17181F)
    static let surface = adaptive(0xFFFFFF, 0x20212B)
    static let inset = adaptive(0xEEEDF4, 0x121319)
    static let primary = adaptive(0x242331, 0xF1EFF9)
    static let secondary = adaptive(0x696575, 0xB2AEBD)
    static let line = adaptive(0xDFDCE9, 0x373541)
    static let heading = Font.system(size: 24, weight: .semibold, design: .rounded)
    static let body = Font.system(size: 14, weight: .regular, design: .rounded)
    static let small = Font.system(size: 12, weight: .medium, design: .rounded)
}

struct AppMark: View {
    var size: CGFloat = 40
    var body: some View {
        Group {
            if let image = NSImage(named: NSImage.Name("AppIcon")) {
                Image(nsImage: image).resizable().scaledToFit()
            } else {
                Image(systemName: "backward.fill").resizable().scaledToFit()
                    .padding(size * 0.22).foregroundStyle(Style.accent)
                    .background(Style.accent.opacity(0.12), in: .rect(cornerRadius: size * 0.25))
            }
        }.frame(width: size, height: size).accessibilityHidden(true)
    }
}

struct KeyCap: View {
    let text: String
    var body: some View {
        Text(text).font(.system(size: 11, weight: .medium, design: .rounded))
            .foregroundStyle(Style.secondary).padding(.horizontal, 7).padding(.vertical, 4)
            .background(Style.primary.opacity(0.045), in: .rect(cornerRadius: 5))
            .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(Style.line, lineWidth: 0.5))
            .accessibilityHidden(true)
    }
}

struct QuietButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.padding(.horizontal, 12).padding(.vertical, 8)
            .background(Style.primary.opacity(configuration.isPressed ? 0.10 : 0.045), in: .rect(cornerRadius: 9))
            .contentShape(.rect(cornerRadius: 9))
    }
}

struct CaptureImage: View {
    let path: String
    var thumbnail = false
    @State private var image: NSImage?
    @State private var loading = true
    var body: some View {
        Group {
            if let image {
                Image(nsImage: image).resizable().scaledToFit()
            } else if loading {
                ProgressView().controlSize(.small)
            } else {
                Image(systemName: "photo").foregroundStyle(Style.secondary)
                    .accessibilityLabel("Image unavailable")
            }
        }
        .task(id: path) {
            image = nil
            loading = true
            let pixelSize = thumbnail ? 240 : 2560
            let result = await Task.detached(priority: .userInitiated) {
                guard let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil) else { return nil as CGImage? }
                return CGImageSourceCreateThumbnailAtIndex(source, 0, [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceThumbnailMaxPixelSize: pixelSize
                ] as CFDictionary)
            }.value
            guard !Task.isCancelled else { return }
            image = result.map { NSImage(cgImage: $0, size: .zero) }
            loading = false
        }
    }
}

struct CaptureRow: View {
    let memory: Memory
    let query: String
    let selected: Bool
    var compact = false
    @State private var hovered = false
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            if compact {
                CaptureImage(path: memory.imagePath, thumbnail: true)
                    .frame(width: 64, height: 48).background(Style.inset)
                    .clipShape(.rect(cornerRadius: 6)).accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 6) {
                    Image(systemName: memory.app.hasPrefix("Display") ? "display" : "macwindow")
                        .foregroundStyle(selected ? Style.accent : Style.secondary).accessibilityHidden(true)
                    Text(memory.app).lineLimit(1)
                    Spacer(minLength: 0)
                    Text(memory.date, format: .dateTime.hour().minute()).monospacedDigit()
                }.font(Style.small).foregroundStyle(Style.secondary)
                Text(highlighted(memory.title, query: query))
                    .font(.system(size: 14, weight: .semibold, design: .rounded)).lineLimit(compact ? 1 : 2)
                    .foregroundStyle(Style.primary)
                if !memory.snippet.isEmpty {
                    Text(highlighted(memory.snippet.replacingOccurrences(of: "\n", with: " "), query: query))
                        .font(.system(size: 13, weight: .regular, design: .rounded))
                        .foregroundStyle(Style.secondary).lineLimit(compact ? 1 : 2).lineSpacing(3)
                }
                if !compact && !Calendar.current.isDateInToday(memory.date) {
                    Text(memory.date, format: .dateTime.month(.abbreviated).day()).font(Style.small).foregroundStyle(Style.secondary)
                }
            }
        }
        .padding(compact ? 12 : 16).frame(maxWidth: .infinity, alignment: .leading)
        .background(selected ? Style.accent.opacity(0.12) : (hovered ? Style.primary.opacity(0.035) : .clear), in: .rect(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(selected ? Style.accent.opacity(0.36) : .clear, lineWidth: 1))
        .contentShape(.rect(cornerRadius: 12)).onHover { hovered = $0 }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

func highlighted(_ text: String, query: String) -> AttributedString {
    var formatted = AttributedString(text)
    for term in SearchQuery.terms(query) {
        var start = text.startIndex
        while start < text.endIndex,
              let match = text.range(of: term, options: [.caseInsensitive, .diacriticInsensitive], range: start..<text.endIndex) {
            if let lower = AttributedString.Index(match.lowerBound, within: formatted),
               let upper = AttributedString.Index(match.upperBound, within: formatted) {
                formatted[lower..<upper].inlinePresentationIntent = .stronglyEmphasized
                formatted[lower..<upper].backgroundColor = Style.accent.opacity(0.20)
                formatted[lower..<upper].foregroundColor = Style.primary
            }
            start = match.upperBound
        }
    }
    return formatted
}

func copyText(_ text: String) {
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(text, forType: .string)
}
