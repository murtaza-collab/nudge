import AppKit
import DailyCore
import SwiftUI

/// Owns the app's surfaces. There's no main window: the menu-bar item, floating
/// button and task panel are the app.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let settings = AppSettings()
    private var model: TaskListModel?
    private var panel: TaskPanelController?
    private var floatingButton: FloatingButtonController?
    private var menuBar: MenuBarController?
    private var notifications: NotificationController?
    private var quickAdd: QuickAddController?
    private var shortcuts: ShortcutController?
    private var briefing: BriefingController?
    private var settingsWindow: SettingsController?
    private var onboarding: OnboardingController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        NSApp.mainMenu = Self.makeMainMenu()

        // `-StorePath /path/to.sqlite` on the command line points at a scratch database for testing.
        let customStore = UserDefaults.standard.string(forKey: "StorePath")
        if customStore == nil {
            // The app used to be called "Mac Daily Utility"; bring its data along.
            do { try TaskStore.migrateLegacyFolder() } catch {
                NSLog("Couldn't move data from the old MacDailyUtility folder: \(error)")
            }
        }
        let storeURL = customStore.map(URL.init(fileURLWithPath:)) ?? TaskStore.defaultURL
        let model: TaskListModel
        do {
            model = TaskListModel(store: try TaskStore.open(at: storeURL))
        } catch {
            NSApp.activate()
            let alert = NSAlert()
            alert.messageText = "Nudge couldn't open its task database."
            alert.informativeText = "\(error)\n\n\(storeURL.path)"
            alert.runModal()
            NSApp.terminate(nil)
            return
        }
        self.model = model

        let notifications = NotificationController(model: model, settings: settings)
        let panel = TaskPanelController(model: model, settings: settings, notifications: notifications)
        let quickAdd = QuickAddController(model: model)
        let briefing = BriefingController(model: model, settings: settings)
        let shortcuts = ShortcutController(settings: settings, handlers: [
            .quickAdd: { [weak quickAdd] in quickAdd?.toggle() },
            .openTasks: { [weak panel] in panel?.toggle(from: .activeScreen) },
            .search: { [weak panel] in panel?.show(from: .activeScreen, mode: .search) },
        ])
        let settingsWindow = SettingsController(settings: settings, model: model, notifications: notifications, shortcuts: shortcuts)
        settingsWindow.onShowBriefing = { [weak briefing] in briefing?.showNow() }
        panel.onShowShortcuts = { [weak settingsWindow] in settingsWindow?.show(tab: .shortcuts) }
        panel.onShowBriefing = { [weak briefing] in briefing?.showNow() }
        panel.onShowSettings = { [weak settingsWindow] in settingsWindow?.show() }
        let floatingButton = FloatingButtonController(model: model, settings: settings)
        settingsWindow.onPreviewNudge = { [weak floatingButton] in floatingButton?.nudge() }
        let menuBar = MenuBarController(model: model, settings: settings, actions: .init(
            togglePanel: { [weak panel] in panel?.toggle(from: .statusItem) },
            addTask: { [weak quickAdd] in quickAdd?.show() },
            showBriefing: { [weak briefing] in briefing?.showNow() },
            search: { [weak panel] in panel?.show(from: .statusItem, mode: .search) },
            showSettings: { [weak settingsWindow] in settingsWindow?.show() },
            quit: { AppDelegate.confirmQuit() }
        ))
        floatingButton.onClick = { [weak panel] in panel?.toggle(from: .floatingButton) }
        panel.floatingButtonAnchor = { [weak floatingButton] in floatingButton?.anchor }
        panel.statusItemFrame = { [weak menuBar] in menuBar?.buttonFrame }
        let openTasks: () -> Void = { [weak panel, weak floatingButton] in
            panel?.show(from: floatingButton?.anchor != nil ? .floatingButton : .activeScreen)
        }
        notifications.onOpen = openTasks
        briefing.onOpenTasks = openTasks
        // Test runs against a scratch database must not schedule notifications: they share
        // this app's identity, so macOS would deliver them after the test copy quits.
        // Settings that the model and the whole app follow.
        observeChanges { [settings, weak model] in
            model?.historyDays = settings.historyDays
            model?.defaultReminderMinutes = settings.defaultReminderMinutes
            switch settings.appearance {
            case .system: NSApp.appearance = nil
            case .light: NSApp.appearance = NSAppearance(named: .aqua)
            case .dark: NSApp.appearance = NSAppearance(named: .darkAqua)
            }
        }

        let firstLaunch = !settings.onboardingCompleted && !isDevelopmentRun
        if !isDevelopmentRun {
            // On first launch, permission is asked after setup rather than on top of it.
            notifications.start(requestPermission: !firstLaunch)
            if !firstLaunch { briefing.start() }
            observeChanges { [settings] in LaunchAtLogin.apply(settings.launchAtLogin) }
        }

        self.panel = panel
        self.floatingButton = floatingButton
        self.menuBar = menuBar
        self.notifications = notifications
        self.quickAdd = quickAdd
        self.shortcuts = shortcuts
        self.briefing = briefing
        self.settingsWindow = settingsWindow

        let allRegistered = shortcuts.registerAll()
        if firstLaunch {
            // Setup includes choosing the Quick Add shortcut.
            let onboarding = OnboardingController(settings: settings, shortcuts: shortcuts)
            onboarding.onFinish = { [weak notifications, weak briefing, weak self] in
                notifications?.requestPermissionIfNeeded()
                briefing?.start()
                self?.onboarding = nil
            }
            self.onboarding = onboarding
            onboarding.show()
        } else if !allRegistered, shortcuts.failures[.quickAdd] != nil, !isSnapshotRun {
            // The Quick Add shortcut may be taken by macOS; if so, let the user pick another.
            shortcuts.showWindow()
        }

        #if DEBUG
        runSnapshotIfRequested()
        #endif
    }

    /// Launched with `-StorePath` or `-SnapshotDir` for development.
    private var isDevelopmentRun: Bool {
        UserDefaults.standard.string(forKey: "StorePath") != nil || isSnapshotRun
    }

    private var isSnapshotRun: Bool {
        #if DEBUG
        UserDefaults.standard.string(forKey: "SnapshotDir") != nil
        #else
        false
        #endif
    }

    /// Starts a fresh copy of the app and quits this one (after importing settings or a reset).
    static func relaunch() {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: configuration) { _, _ in
            DispatchQueue.main.async { NSApp.terminate(nil) }
        }
    }

    /// Quitting stops reminders, so ask first. Used by the app's own Quit commands; logout
    /// and shutdown quit without asking.
    static func confirmQuit() {
        NSApp.activate()
        let alert = NSAlert()
        alert.messageText = "Quit Nudge?"
        alert.informativeText = UserDefaults.standard.bool(forKey: "launchAtLogin")
            ? "Reminders and the daily briefing stop until you open it again. It will start automatically next time you log in."
            : "Reminders and the daily briefing stop until you open it again."
        alert.addButton(withTitle: "Quit")
        alert.addButton(withTitle: "Cancel")
        if alert.runModal() == .alertFirstButtonReturn {
            NSApp.terminate(nil)
        }
    }

    @objc private func quitFromMenu(_ sender: Any?) {
        Self.confirmQuit()
    }

    /// Reopening the app (e.g. from Finder or Spotlight) shows the task panel.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        panel?.show(from: .activeScreen)
        return false
    }

    /// Menu-bar apps have no visible main menu, but it still supplies standard key equivalents.
    private static func makeMainMenu() -> NSMenu {
        let main = NSMenu()
        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Quit Nudge", action: #selector(AppDelegate.quitFromMenu(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        main.addItem(appItem)

        let editItem = NSMenuItem()
        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        edit.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        edit.addItem(.separator())
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = edit
        main.addItem(editItem)
        return main
    }

    #if DEBUG
    private func runSnapshotIfRequested() {
        guard UserDefaults.standard.string(forKey: "SnapshotDir") != nil, let model, let panel else { return }
        panel.show(from: settings.floatingButtonEnabled ? .floatingButton : .activeScreen)
        if let title = UserDefaults.standard.string(forKey: "SnapshotCompleteTask"),
           let task = model.activeTasks.first(where: { $0.title == title }) {
            // Exercises completion (and a recurring task's next occurrence) end to end.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { model.complete(task) }
        }
        if let title = UserDefaults.standard.string(forKey: "SnapshotAddTask") {
            // Exercises resizing while open.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { model.add(parsing: title) }
        }
        let sample = model.activeTasks.first { $0.recurrence != nil && $0.recurrence?.frequency == .monthly }
            ?? model.groups.overdue.first ?? model.groups.today.first ?? DailyTask(title: "Sample task")
        var windows: [String: NSWindow] = [:]
        windows["panel"] = panel.window
        windows["button"] = floatingButton?.window
        quickAdd?.show()
        if let text = UserDefaults.standard.string(forKey: "SnapshotQuickAddText") { quickAdd?.debugSetText(text) }
        windows["quickadd"] = quickAdd?.window
        shortcuts?.debugSimulateFailure(.reservedBySystem, for: .quickAdd)
        shortcuts?.showWindow()
        windows["shortcuts"] = shortcuts?.shortcutsWindow
        briefing?.debugPresent()
        windows["briefing"] = briefing?.window
        settingsWindow?.show(tab: UserDefaults.standard.string(forKey: "SnapshotSettingsTab").flatMap(SettingsTab.init(debugName:)) ?? .general)
        windows["settings"] = settingsWindow?.settingsWindow
        if UserDefaults.standard.bool(forKey: "SnapshotOnboarding") {
            let onboarding = OnboardingController(settings: settings, shortcuts: shortcuts!)
            onboarding.show()
            self.onboarding = onboarding
            windows["onboarding"] = onboarding.onboardingWindow
        }
        if let mode = UserDefaults.standard.string(forKey: "SnapshotPanelMode") {
            panel.debugSetMode(mode == "history" ? .history : .search, query: UserDefaults.standard.string(forKey: "SnapshotSearch") ?? "")
        }
        DebugSnapshot.run(windows: windows, extras: [
            "editor": AnyView(TaskEditorView(task: sample, model: model, onSave: { _ in }, onCancel: {})
                .background(Color(nsColor: .windowBackgroundColor))),
        ])
    }
    #endif
}
