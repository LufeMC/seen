import AppKit
import SwiftUI

// A native field gives the search panel an explicit keyboard responder.
struct PanelSearchField: NSViewRepresentable {
    @Binding var text: String
    let move: (Int) -> Void
    let submit: () -> Void
    let escape: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> FocusedSearchField {
        let field = FocusedSearchField()
        field.delegate = context.coordinator
        field.stringValue = text
        field.placeholderString = "Ask about something you saw…"
        field.setAccessibilityLabel("Quick search screen history")
        let base = NSFont.systemFont(ofSize: 24, weight: .semibold)
        field.font = base.fontDescriptor.withDesign(.rounded).flatMap { NSFont(descriptor: $0, size: 24) } ?? base
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.textColor = .labelColor
        field.maximumNumberOfLines = 1
        field.cell?.usesSingleLineMode = true
        field.cell?.isScrollable = true
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return field
    }

    func updateNSView(_ field: FocusedSearchField, context: Context) {
        context.coordinator.parent = self
        if field.stringValue != text { field.stringValue = text }
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: PanelSearchField
        init(_ parent: PanelSearchField) { self.parent = parent }
        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            parent.text = field.stringValue
        }
        func control(_ control: NSControl, textView: NSTextView, doCommandBy command: Selector) -> Bool {
            switch command {
            case #selector(NSResponder.moveDown(_:)): parent.move(1)
            case #selector(NSResponder.moveUp(_:)): parent.move(-1)
            case #selector(NSResponder.insertNewline(_:)): parent.submit()
            case #selector(NSResponder.cancelOperation(_:)): parent.escape()
            default: return false
            }
            return true
        }
    }
}

final class FocusedSearchField: NSTextField {
    override var acceptsFirstResponder: Bool { true }
    override var needsPanelToBecomeKey: Bool { true }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard let window else { return }
        window.initialFirstResponder = self
        DispatchQueue.main.async { [weak self, weak window] in
            guard let self, let window, window.isVisible else { return }
            window.makeFirstResponder(self)
            self.currentEditor()?.selectAll(nil)
        }
    }
}
