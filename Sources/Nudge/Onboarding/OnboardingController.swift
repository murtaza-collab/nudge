import AppKit
import SwiftUI

/// First-launch setup: three short steps, everything else uses defaults.
@MainActor
final class OnboardingController {
    private let settings: AppSettings
    private let shortcuts: ShortcutController
    private var window: NSWindow?

    /// Called once setup is finished (the app then asks for notification permission).
    var onFinish: () -> Void = {}

    init(settings: AppSettings, shortcuts: ShortcutController) {
        self.settings = settings
        self.shortcuts = shortcuts
    }

    var onboardingWindow: NSWindow? { window }

    func show() {
        let view = OnboardingView(settings: settings, shortcuts: shortcuts) { [weak self] in self?.finish() }
        let hosting = NSHostingController(rootView: view)
        hosting.sizingOptions = .preferredContentSize
        let window = NSWindow(contentViewController: hosting)
        window.styleMask = [.titled, .fullSizeContentView]
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        shortcuts.testShortcuts(in: window)
        self.window = window
        window.center()
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    private func finish() {
        settings.onboardingCompleted = true
        window?.close()
        window = nil
        onFinish()
    }
}

private struct OnboardingView: View {
    @Bindable var settings: AppSettings
    let shortcuts: ShortcutController
    let onFinish: () -> Void

    @State private var step = 0
    @State private var choosingShortcut = false
    @State private var shortcutError: HotKeyError?

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            switch step {
            case 0: welcome
            case 1: shortcutStep
            default: briefingStep
            }
        }
        .padding(28)
        .frame(width: 420, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var welcome: some View {
        VStack(alignment: .leading, spacing: 18) {
            Image(systemName: "checklist")
                .font(.system(size: 36))
                .foregroundStyle(Theme.accent)
            VStack(alignment: .leading, spacing: 6) {
                Text("Nudge")
                    .font(.system(size: 22, weight: .semibold))
                Text("Your personal daily task assistant.")
                    .foregroundStyle(.secondary)
                Label("Everything stays on this Mac.", systemImage: "lock")
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)
            }
            footer("Continue") { step = 1 }
        }
    }

    private var shortcutStep: some View {
        let current = settings.quickAddShortcut
        let failure = shortcuts.failures[.quickAdd]
        return VStack(alignment: .leading, spacing: 14) {
            Text("Quick Add Shortcut")
                .font(.system(size: 18, weight: .semibold))
            Text("Add a task from any app, in a couple of seconds.")
                .foregroundStyle(.secondary)

            HStack(spacing: 12) {
                if choosingShortcut {
                    ShortcutRecorder(shortcut: current) { shortcut in
                        shortcutError = shortcuts.apply(shortcut, for: .quickAdd)
                    }
                    .frame(width: 160, height: 26)
                } else {
                    Text(current?.displayString ?? "None")
                        .font(.system(size: 20, weight: .medium, design: .rounded))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.06)))
                }
                if shortcuts.verified.contains(.quickAdd) {
                    Label("Works", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(Theme.green)
                } else if current != nil && failure == nil {
                    Text("Press it now to test")
                        .foregroundStyle(.secondary)
                        .font(.callout)
                }
            }
            if let message = (shortcutError ?? failure)?.message {
                Text(message)
                    .font(.callout)
                    .foregroundStyle(Theme.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text("If pressing it doesn't show ✓, another app is using it — choose another.")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack {
                if !choosingShortcut {
                    Button("Choose Another") { choosingShortcut = true }
                }
                Spacer()
                Button(choosingShortcut ? "Continue" : "Use This Shortcut") { step = 2 }
                    .keyboardShortcut(.defaultAction)
                    .disabled(failure != nil && !choosingShortcut)
            }
        }
    }

    private var briefingStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Daily Briefing")
                .font(.system(size: 18, weight: .semibold))
            Toggle("Show my tasks when I start my Mac", isOn: $settings.briefingEnabled)
            Text("Once a day, only when something is due. You can change this in Settings.")
                .font(.caption)
                .foregroundStyle(.secondary)
            footer("Continue", action: onFinish)
        }
    }

    private func footer(_ title: String, action: @escaping () -> Void) -> some View {
        HStack {
            Spacer()
            Button(title, action: action)
                .keyboardShortcut(.defaultAction)
                .controlSize(.large)
        }
    }
}
