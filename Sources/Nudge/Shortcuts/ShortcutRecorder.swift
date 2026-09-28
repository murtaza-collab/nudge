import AppKit
import SwiftUI

/// Click, then press a key combination. Esc cancels, Delete clears.
struct ShortcutRecorder: NSViewRepresentable {
    let shortcut: KeyShortcut?
    /// Called with the new shortcut, or nil when cleared.
    let onChange: (KeyShortcut?) -> Void

    func makeNSView(context: Context) -> RecorderView {
        let view = RecorderView()
        view.onChange = onChange
        view.shortcut = shortcut
        return view
    }

    func updateNSView(_ view: RecorderView, context: Context) {
        view.onChange = onChange
        view.shortcut = shortcut
    }

    final class RecorderView: NSView {
        var onChange: (KeyShortcut?) -> Void = { _ in }
        var shortcut: KeyShortcut? { didSet { needsDisplay = true } }
        private var isRecording = false { didSet { needsDisplay = true } }

        override var acceptsFirstResponder: Bool { true }
        override var intrinsicContentSize: NSSize { NSSize(width: 150, height: 24) }
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

        override func mouseDown(with event: NSEvent) {
            window?.makeFirstResponder(self)
            isRecording = true
        }

        override func resignFirstResponder() -> Bool {
            isRecording = false
            return true
        }

        override func keyDown(with event: NSEvent) {
            guard isRecording else { return super.keyDown(with: event) }
            record(event)
        }

        /// ⌘-combinations arrive here rather than keyDown.
        override func performKeyEquivalent(with event: NSEvent) -> Bool {
            guard isRecording, window?.firstResponder === self else { return false }
            record(event)
            return true
        }

        private func record(_ event: NSEvent) {
            let plain = event.modifierFlags.intersection([.command, .option, .control, .shift]).isEmpty
            switch Int(event.keyCode) {
            case 53 where plain: // Esc
                window?.makeFirstResponder(nil)
            case 51 where plain, 117 where plain: // Delete / Forward Delete
                window?.makeFirstResponder(nil)
                onChange(nil)
            default:
                if let recorded = KeyShortcut(event: event) {
                    window?.makeFirstResponder(nil)
                    onChange(recorded)
                } else {
                    NSSound.beep() // Needs ⌘, ⌃ or ⌥.
                }
            }
        }

        override func draw(_ dirtyRect: NSRect) {
            let rect = bounds.insetBy(dx: 0.5, dy: 0.5)
            let path = NSBezierPath(roundedRect: rect, xRadius: 6, yRadius: 6)
            (isRecording ? NSColor.controlAccentColor.withAlphaComponent(0.12) : NSColor.controlBackgroundColor).setFill()
            path.fill()
            (isRecording ? NSColor.controlAccentColor : NSColor.separatorColor).setStroke()
            path.lineWidth = 1
            path.stroke()

            let text: String
            let color: NSColor
            if isRecording {
                text = "Type shortcut…"
                color = .secondaryLabelColor
            } else if let shortcut {
                text = shortcut.displayString
                color = .labelColor
            } else {
                text = "Click to record"
                color = .tertiaryLabelColor
            }
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 12, weight: shortcut != nil && !isRecording ? .medium : .regular),
                .foregroundColor: color,
            ]
            let size = text.size(withAttributes: attributes)
            text.draw(at: NSPoint(x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2), withAttributes: attributes)
        }

        override func isAccessibilityElement() -> Bool { true }
        override func accessibilityRole() -> NSAccessibility.Role? { .button }
        override func accessibilityLabel() -> String? {
            shortcut.map { "Shortcut \($0.displayString). Click to change." } ?? "No shortcut. Click to record."
        }
    }
}
