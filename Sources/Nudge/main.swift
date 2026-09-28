import AppKit

// AppKit owns the app lifecycle so each surface (menu bar, floating button,
// panels, briefing) can be managed individually. Views are SwiftUI.
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
