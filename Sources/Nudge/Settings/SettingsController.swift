import AppKit
import DailyCore
import SwiftUI
import UniformTypeIdentifiers

/// Owns the Settings window and the data operations it offers.
@MainActor
final class SettingsController {
    private let settings: AppSettings
    private let model: TaskListModel
    private let notifications: NotificationController
    private let shortcuts: ShortcutController
    private var window: NSWindow?
    private let navigation = SettingsNavigation()

    var onShowBriefing: () -> Void = {}
    var onPreviewNudge: () -> Void = {}

    init(settings: AppSettings, model: TaskListModel, notifications: NotificationController, shortcuts: ShortcutController) {
        self.settings = settings
        self.model = model
        self.notifications = notifications
        self.shortcuts = shortcuts
    }

    var settingsWindow: NSWindow? { window }

    func show(tab: SettingsTab? = nil) {
        if let tab { navigation.tab = tab }
        if window == nil {
            let view = SettingsView(
                settings: settings, model: model, notifications: notifications, shortcuts: shortcuts,
                data: DataActions(
                    export: { [weak self] in self?.exportBackup() },
                    importBackup: { [weak self] in self?.importBackup() },
                    clearHistory: { [weak self] in self?.confirmClearHistory() },
                    resetAll: { [weak self] in self?.confirmReset() },
                    showBriefing: { [weak self] in self?.onShowBriefing() },
                    previewNudge: { [weak self] in self?.onPreviewNudge() }
                ),
                navigation: navigation
            )
            let hosting = NSHostingController(rootView: view)
            hosting.sizingOptions = .preferredContentSize
            let window = NSWindow(contentViewController: hosting)
            window.title = "Nudge Settings"
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            shortcuts.testShortcuts(in: window)
            self.window = window
            window.center()
        }
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }

    // MARK: - Export / import

    private func exportBackup() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = Backup.fileName(for: Date())
        panel.allowedContentTypes = [.json]
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try model.makeBackup(settings: settings.exportValues()).encoded().write(to: url, options: .atomic)
        } catch {
            showError("Couldn't export", error)
        }
    }

    private func importBackup() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }

        // Validate fully before changing anything.
        let backup: Backup
        let plan: Backup.ImportPlan
        do {
            backup = try Backup.read(from: try Data(contentsOf: url))
            plan = try model.importPlan(for: backup)
        } catch {
            showError("Couldn't import “\(url.lastPathComponent)”", error)
            return
        }

        let alert = NSAlert()
        alert.messageText = "Import from “\(url.lastPathComponent)”?"
        var lines = [
            "\(plan.newActiveCount) active task\(plan.newActiveCount == 1 ? "" : "s") and \(plan.newCompletedCount) completed will be added."
        ]
        if !plan.newCategories.isEmpty {
            lines.append("New categories: \(plan.newCategories.map(\.name).joined(separator: ", ")).")
        }
        if plan.existingCount > 0 {
            lines.append("\(plan.existingCount) task\(plan.existingCount == 1 ? " is" : "s are") already here and will be left unchanged.")
        }
        alert.informativeText = lines.joined(separator: "\n")
        let settingsBox = NSButton(checkboxWithTitle: "Also replace my settings with the backup's (restarts the app)", target: nil, action: nil)
        settingsBox.state = .off
        if !backup.settings.isEmpty { alert.accessoryView = settingsBox }
        alert.addButton(withTitle: plan.newTasks.isEmpty && backup.settings.isEmpty ? "OK" : "Import")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        do {
            try model.apply(plan)
        } catch {
            showError("Import failed; nothing was changed", error)
            return
        }
        if settingsBox.state == .on {
            settings.importValues(backup.settings)
            AppDelegate.relaunch()
        }
    }

    // MARK: - Destructive actions

    private func confirmClearHistory() {
        let alert = NSAlert()
        alert.messageText = "Clear all completed tasks?"
        alert.informativeText = "Completed tasks are deleted permanently. Active tasks aren't affected."
        alert.addButton(withTitle: "Clear History").hasDestructiveAction = true
        alert.addButton(withTitle: "Cancel")
        if alert.runModal() == .alertFirstButtonReturn { model.clearHistory() }
    }

    private func confirmReset() {
        let alert = NSAlert()
        alert.alertStyle = .critical
        alert.messageText = "Reset all data?"
        alert.informativeText = "Every task, all history, categories and settings are deleted, and the app restarts with first-launch setup. Consider exporting a backup first."
        alert.addButton(withTitle: "Reset Everything").hasDestructiveAction = true
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        model.deleteAllData()
        if let domain = Bundle.main.bundleIdentifier {
            UserDefaults.standard.removePersistentDomain(forName: domain)
        }
        AppDelegate.relaunch()
    }

    private func showError(_ title: String, _ error: Error) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = "\(error)"
        alert.runModal()
    }
}
