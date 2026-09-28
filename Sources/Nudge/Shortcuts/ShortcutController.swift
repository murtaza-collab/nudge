import AppKit
import Observation
import os
import SwiftUI

/// Registers the app's global shortcuts from settings, validates changes, and shows the
/// shortcut window (also used when the default is unavailable at launch).
@MainActor
@Observable
final class ShortcutController {
    private static let log = Logger(subsystem: "com.murtazacollab.nudge", category: "Shortcuts")
    private let settings: AppSettings
    @ObservationIgnored private let handlers: [HotKeyAction: () -> Void]
    @ObservationIgnored private var window: NSWindow?
    /// Windows in which pressing a shortcut tests it instead of running it.
    @ObservationIgnored private var testWindows: [ObjectIdentifier] = []

    /// Actions whose saved shortcut couldn't be registered.
    private(set) var failures: [HotKeyAction: HotKeyError] = [:]
    /// Shortcuts pressed while the window was open. macOS can't report whether another app
    /// has claimed the same keys, so pressing it here is the real test that it reaches us.
    private(set) var verified: Set<HotKeyAction> = []

    init(settings: AppSettings, handlers: [HotKeyAction: () -> Void]) {
        self.settings = settings
        self.handlers = handlers
    }

    /// Registers every saved shortcut. Returns true if all succeeded.
    @discardableResult
    func registerAll() -> Bool {
        for action in HotKeyAction.allCases {
            let shortcut = settings.shortcut(for: action)
            failures[action] = HotKeyCenter.shared.register(shortcut, for: action, handler: handler(for: action))
            Self.log.notice("Shortcut \(action.title, privacy: .public) \(shortcut?.displayString ?? "none", privacy: .public): \(self.failures[action].map { "\($0)" } ?? "ok", privacy: .public)")
        }
        return failures.isEmpty
    }

    /// Tries `shortcut` for `action`; saves it only if it registers. On failure the
    /// previous shortcut stays active.
    func apply(_ shortcut: KeyShortcut?, for action: HotKeyAction) -> HotKeyError? {
        if let shortcut, let other = HotKeyAction.allCases.first(where: { $0 != action && settings.shortcut(for: $0) == shortcut }) {
            return .duplicate(other)
        }
        if let error = HotKeyCenter.shared.register(shortcut, for: action, handler: handler(for: action)) {
            let previous = settings.shortcut(for: action)
            failures[action] = HotKeyCenter.shared.register(previous, for: action, handler: handler(for: action))
            return error
        }
        settings.setShortcut(shortcut, for: action)
        failures[action] = nil
        verified.remove(action)
        return nil
    }

    func showWindow() {
        if window == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 420, height: 200),
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            window.title = "Keyboard Shortcuts"
            window.isReleasedWhenClosed = false
            testShortcuts(in: window)
            let hosting = NSHostingController(rootView: ShortcutsView(controller: self, settings: settings) { [weak window] in
                window?.close()
            })
            hosting.sizingOptions = .preferredContentSize // window follows the content's size
            window.contentViewController = hosting
            self.window = window
        }
        window?.center()
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }

    var shortcutsWindow: NSWindow? { window }

    #if DEBUG
    /// Lets snapshot runs show the "shortcut unavailable" state.
    func debugSimulateFailure(_ error: HotKeyError, for action: HotKeyAction) {
        failures[action] = error
    }
    #endif

    /// Pressing a shortcut while `window` is frontmost marks it as working instead of running it.
    func testShortcuts(in window: NSWindow) {
        testWindows.append(ObjectIdentifier(window))
    }

    private func handler(for action: HotKeyAction) -> () -> Void {
        { [weak self] in
            guard let self else { return }
            if let key = NSApp.keyWindow, key.isVisible, self.testWindows.contains(ObjectIdentifier(key)) {
                self.verified.insert(action)
            } else {
                self.handlers[action]?()
            }
        }
    }
}

struct ShortcutsView: View {
    let controller: ShortcutController
    let settings: AppSettings
    /// Shows a Done button when set (standalone window).
    let onDone: (() -> Void)?

    @State private var errors: [HotKeyAction: HotKeyError] = [:]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let failure = controller.failures[.quickAdd] {
                VStack(alignment: .leading, spacing: 4) {
                    Label("\((settings.quickAddShortcut ?? .quickAddDefault).displayString) isn't available", systemImage: "exclamationmark.triangle.fill")
                        .font(.headline)
                        .foregroundStyle(Theme.orange)
                    Text("\(failure.message) Choose another shortcut for Quick Add.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            VStack(alignment: .leading, spacing: 12) {
                ForEach(HotKeyAction.allCases, id: \.self) { action in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 10) {
                            Text(action.title)
                                .frame(width: 90, alignment: .trailing)
                            ShortcutRecorder(shortcut: settings.shortcut(for: action)) { shortcut in
                                errors[action] = controller.apply(shortcut, for: action)
                            }
                            .frame(width: 150, height: 24)
                            if settings.shortcut(for: action) != nil {
                                if controller.verified.contains(action) {
                                    Label("Works", systemImage: "checkmark.circle.fill")
                                        .foregroundStyle(Theme.green)
                                        .font(.caption)
                                } else {
                                    Text("Press it to test")
                                        .foregroundStyle(.secondary)
                                        .font(.caption)
                                }
                            }
                            if action == .quickAdd && settings.quickAddShortcut != .quickAddDefault {
                                Button("Use \(KeyShortcut.quickAddDefault.displayString)") {
                                    errors[action] = controller.apply(.quickAddDefault, for: action)
                                }
                                .controlSize(.small)
                            }
                        }
                        if let error = errors[action] {
                            Text(error.message)
                                .font(.caption)
                                .foregroundStyle(Theme.red)
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(.leading, 100)
                        }
                    }
                }
            }

            Text("Click a shortcut and press new keys; Delete removes it. macOS can't tell if another app uses the same keys, so press each shortcut once to check it reaches this app.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if let onDone {
                HStack {
                    Spacer()
                    Button("Done", action: onDone)
                        .keyboardShortcut(.defaultAction)
                }
            }
        }
        .padding(20)
        .frame(width: 420)
        .fixedSize(horizontal: false, vertical: true)
    }
}
