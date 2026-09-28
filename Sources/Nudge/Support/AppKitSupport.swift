import AppKit
import Observation
import SwiftUI

/// Runs `apply` now and again whenever any observable property it read changes.
/// Bridges @Observable state to AppKit controllers.
@MainActor
func observeChanges(_ apply: @escaping @MainActor () -> Void) {
    withObservationTracking(apply) {
        // onChange fires before the new value is stored; re-run on the next turn.
        Task { @MainActor in observeChanges(apply) }
    }
}

extension NSScreen {
    var displayID: UInt32? {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
    }

    static func withDisplayID(_ id: UInt32?) -> NSScreen? {
        guard let id else { return nil }
        return screens.first { $0.displayID == id }
    }

    /// The screen containing `point`, or the nearest one.
    static func containing(_ point: NSPoint) -> NSScreen? {
        screens.first { $0.frame.contains(point) }
            ?? screens.min { $0.frame.distance(to: point) < $1.frame.distance(to: point) }
    }

    /// The screen with the mouse pointer: where keyboard-triggered UI should appear.
    static var active: NSScreen? {
        containing(NSEvent.mouseLocation) ?? main
    }
}

extension NSRect {
    func distance(to point: NSPoint) -> CGFloat {
        let dx = max(minX - point.x, 0, point.x - maxX)
        let dy = max(minY - point.y, 0, point.y - maxY)
        return hypot(dx, dy)
    }
}

/// Behind-window blur for borderless panels.
struct VisualEffectBackground: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .popover

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.material = material
    }
}
