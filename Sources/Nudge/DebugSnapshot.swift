#if DEBUG
import AppKit
import SwiftUI

/// Development aid: `-SnapshotDir /some/dir` makes the app write PNGs of its windows in
/// light and dark appearance, then quit. Needs no Screen Recording permission.
/// Behind-window blur isn't captured, so translucent surfaces render flat.
@MainActor
enum DebugSnapshot {
    /// Snapshots `windows` plus any `extras` (views that normally live in popovers),
    /// each hosted in its own offscreen window.
    static func run(windows: [String: NSWindow], extras: [String: AnyView] = [:]) {
        guard let dir = UserDefaults.standard.string(forKey: "SnapshotDir") else { return }
        var windows = windows
        for (name, view) in extras {
            let hosting = NSHostingView(rootView: view)
            let extra = NSWindow(contentRect: NSRect(origin: .zero, size: hosting.fittingSize), styleMask: [.borderless], backing: .buffered, defer: false)
            extra.contentView = hosting
            extra.setFrameOrigin(NSPoint(x: -10_000, y: -10_000))
            extra.orderFront(nil)
            windows[name] = extra
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            for (name, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
                for (windowName, window) in windows {
                    window.appearance = NSAppearance(named: appearance)
                    window.contentView?.layoutSubtreeIfNeeded()
                    window.displayIfNeeded()
                    write(window, to: URL(fileURLWithPath: dir).appending(path: "\(windowName)-\(name).png"))
                }
            }
            NSApp.terminate(nil)
        }
    }

    private static func write(_ window: NSWindow, to url: URL) {
        // Render the frame view so the title bar and window background are included.
        guard let view = window.contentView?.superview,
              let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
    }
}
#endif
