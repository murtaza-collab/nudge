import AppKit
import os
import ServiceManagement

/// Keeps the macOS login item in sync with the "Launch at login" setting.
///
/// Only the copy in /Applications registers itself, so development builds elsewhere
/// never become the login item.
@MainActor
enum LaunchAtLogin {
    private static let log = Logger(subsystem: "com.murtazacollab.nudge", category: "LaunchAtLogin")

    static var isInstalledCopy: Bool {
        Bundle.main.bundleURL.deletingLastPathComponent().path == "/Applications"
    }

    /// Whether macOS is waiting for the user to allow the login item in System Settings.
    static var needsApproval: Bool {
        SMAppService.mainApp.status == .requiresApproval
    }

    static func apply(_ enabled: Bool) {
        guard isInstalledCopy else {
            log.notice("Not in /Applications; leaving login item unchanged")
            return
        }
        let service = SMAppService.mainApp
        do {
            if enabled, service.status != .enabled {
                try service.register()
            } else if !enabled, service.status == .enabled {
                try service.unregister()
            }
            log.notice("Launch at login \(enabled ? "on" : "off", privacy: .public); status \(service.status.rawValue, privacy: .public)")
        } catch {
            log.error("Login item change failed: \(error, privacy: .public)")
        }
    }

    static func openSystemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
