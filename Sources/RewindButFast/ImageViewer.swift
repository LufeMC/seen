import SwiftUI
import ImageIO

struct ImageViewer: View {
    let path: String
    @State private var image: NSImage?
    @State private var loading = true
    @State private var sizing: ImageSizing = .width
    @GestureState private var pinch: CGFloat = 1

    var body: some View {
        GeometryReader { geometry in
            let viewport = CGSize(width: geometry.size.width, height: max(1, geometry.size.height - 44))
            VStack(spacing: 0) {
                if let image {
                    let scale = sizing.scale(image: image.size, viewport: viewport)
                    ScrollView([.horizontal, .vertical]) {
                        Image(nsImage: image).resizable().interpolation(.high)
                            .frame(width: image.size.width * scale * pinch, height: image.size.height * scale * pinch)
                            .frame(minWidth: viewport.width, minHeight: viewport.height, alignment: .top)
                            .accessibilityLabel("Saved screen. Use the zoom controls to enlarge the image.")
                            .onTapGesture(count: 2) { sizing = scale < 0.95 ? .custom(1) : .width }
                    }
                    .defaultScrollAnchor(.topLeading)
                    .background(Style.inset)
                    .gesture(MagnifyGesture()
                        .updating($pinch) { value, state, _ in state = value.magnification }
                        .onEnded { value in sizing = .custom(min(4, max(0.05, scale * value.magnification))) })
                    .id(path)
                    controls(scale: scale)
                } else {
                    Group {
                        if loading { ProgressView() }
                        else { ContentUnavailableView("Image unavailable", systemImage: "photo") }
                    }.frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .clipShape(.rect(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Style.line, lineWidth: 0.5))
        }
        .task(id: path) {
            image = nil
            loading = true
            sizing = .width
            let result = await Task.detached(priority: .userInitiated) {
                guard let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil) else { return nil as CGImage? }
                return CGImageSourceCreateImageAtIndex(source, 0, nil)
            }.value
            guard !Task.isCancelled else { return }
            image = result.map { NSImage(cgImage: $0, size: NSSize(width: $0.width, height: $0.height)) }
            loading = false
        }
    }

    private func controls(scale: CGFloat) -> some View {
        HStack(spacing: 8) {
            Menu {
                Button("Fit width") { sizing = .width }
                Button("Fit entire image") { sizing = .fit }
                Button("Actual size · 100%") { sizing = .custom(1) }
            } label: { Text(sizing.label) }
                .menuStyle(.borderlessButton).fixedSize().accessibilityLabel("Image size")
            Spacer(minLength: 4)
            Button("Zoom out", systemImage: "minus.magnifyingglass") { sizing = .custom(max(0.05, scale / 1.5)) }
                .labelStyle(.iconOnly).disabled(scale <= 0.05).help("Zoom out")
            Text("\(Int((scale * 100).rounded()))%")
                .monospacedDigit().frame(minWidth: 38).accessibilityLabel("Zoom: \(Int((scale * 100).rounded())) percent")
            Button("Zoom in", systemImage: "plus.magnifyingglass") { sizing = .custom(min(4, scale * 1.5)) }
                .labelStyle(.iconOnly).disabled(scale >= 4).help("Zoom in")
            Button("Open full image", systemImage: "arrow.up.right.square") {
                NSWorkspace.shared.open(URL(fileURLWithPath: path))
            }.labelStyle(.iconOnly).help("Open full image in Preview")
        }
        .buttonStyle(.borderless).font(Style.small).foregroundStyle(Style.secondary)
        .padding(.horizontal, 12).frame(height: 44).background(Style.surface)
    }
}

enum ImageSizing: Equatable {
    case width, fit, custom(CGFloat)

    var label: String {
        switch self {
        case .width: return "Fit width"
        case .fit: return "Fit image"
        case .custom: return "Image size"
        }
    }

    func scale(image: CGSize, viewport: CGSize) -> CGFloat {
        guard image.width > 0, image.height > 0 else { return 1 }
        switch self {
        case .width: return max(0.01, viewport.width / image.width)
        case .fit: return max(0.01, min(viewport.width / image.width, viewport.height / image.height))
        case .custom(let value): return min(4, max(0.05, value))
        }
    }
}
