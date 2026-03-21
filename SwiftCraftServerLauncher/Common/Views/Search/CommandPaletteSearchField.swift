import AppKit
import SwiftUI

struct CommandPaletteSearchField: NSViewRepresentable {
    let onActivate: () -> Void

    func makeNSView(context: Context) -> NSSearchField {
        let field = CommandPaletteSearchFieldView()
        field.placeholderString = ""
        field.isEditable = false
        field.isEnabled = true
        field.onActivate = onActivate
        return field
    }

    func updateNSView(_ nsView: NSSearchField, context: Context) {
        if let field = nsView as? CommandPaletteSearchFieldView {
            field.onActivate = onActivate
        }
    }
}

final class CommandPaletteSearchFieldView: NSSearchField {
    var onActivate: (() -> Void)?

    override var acceptsFirstResponder: Bool {
        false
    }

    override func mouseDown(with event: NSEvent) {
        onActivate?()
    }
}
