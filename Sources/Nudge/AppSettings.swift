import DailyCore
import Foundation
import Observation

enum ScreenEdge: String {
    case left, right
}

enum AppearanceMode: String, CaseIterable {
    case system, light, dark

    var title: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }
}

/// User preferences, persisted in UserDefaults. The Settings window (Phase 12) edits these.
@MainActor
@Observable
final class AppSettings {
    @ObservationIgnored private let defaults: UserDefaults

    // General
    var launchAtLogin: Bool { didSet { defaults.set(launchAtLogin, forKey: Keys.launchAtLogin) } }
    var appearance: AppearanceMode { didSet { defaults.set(appearance.rawValue, forKey: Keys.appearance) } }
    /// Completed tasks shown in History.
    var historyDays: Int { didSet { defaults.set(historyDays, forKey: Keys.historyDays) } }
    var onboardingCompleted: Bool { didSet { defaults.set(onboardingCompleted, forKey: Keys.onboardingCompleted) } }

    // Daily briefing
    var briefingEnabled: Bool { didSet { defaults.set(briefingEnabled, forKey: Keys.briefingEnabled) } }
    var briefingOnLaunch: Bool { didSet { defaults.set(briefingOnLaunch, forKey: Keys.briefingOnLaunch) } }
    var briefingOnWake: Bool { didSet { defaults.set(briefingOnWake, forKey: Keys.briefingOnWake) } }
    var briefingOncePerDay: Bool { didSet { defaults.set(briefingOncePerDay, forKey: Keys.briefingOncePerDay) } }
    var briefingOnlyIfTasks: Bool { didSet { defaults.set(briefingOnlyIfTasks, forKey: Keys.briefingOnlyIfTasks) } }
    var briefingIncludeOverdue: Bool { didSet { defaults.set(briefingIncludeOverdue, forKey: Keys.briefingIncludeOverdue) } }
    var briefingIncludeUpcoming: Bool { didSet { defaults.set(briefingIncludeUpcoming, forKey: Keys.briefingIncludeUpcoming) } }
    var briefingSkipWeekends: Bool { didSet { defaults.set(briefingSkipWeekends, forKey: Keys.briefingSkipWeekends) } }
    /// Also show at this time (minutes after midnight) if the Mac is on. Nil = off.
    var briefingTimeMinutes: Int? { didSet { defaults.set(briefingTimeMinutes, forKey: Keys.briefingTimeMinutes) } }

    var briefingPreferences: BriefingPreferences {
        BriefingPreferences(
            enabled: briefingEnabled, onLaunch: briefingOnLaunch, onWake: briefingOnWake,
            oncePerDay: briefingOncePerDay, onlyIfTasks: briefingOnlyIfTasks, skipWeekends: briefingSkipWeekends
        )
    }

    // Menu bar
    var showMenuBarIcon: Bool { didSet { defaults.set(showMenuBarIcon, forKey: Keys.showMenuBarIcon) } }
    var showMenuBarCount: Bool { didSet { defaults.set(showMenuBarCount, forKey: Keys.showMenuBarCount) } }

    // Floating button
    var floatingButtonEnabled: Bool { didSet { defaults.set(floatingButtonEnabled, forKey: Keys.floatingButtonEnabled) } }
    /// A small bounce when a task becomes due, repeated every `nudgeIntervalMinutes` while overdue.
    var floatingButtonNudges: Bool { didSet { defaults.set(floatingButtonNudges, forKey: Keys.floatingButtonNudges) } }
    var nudgeIntervalMinutes: Int { didSet { defaults.set(nudgeIntervalMinutes, forKey: Keys.nudgeIntervalMinutes) } }
    var floatingButtonStyle: FloatingButtonStyle { didSet { defaults.set(floatingButtonStyle.rawValue, forKey: Keys.floatingButtonStyle) } }
    var floatingButtonAlwaysOnTop: Bool { didSet { defaults.set(floatingButtonAlwaysOnTop, forKey: Keys.floatingButtonAlwaysOnTop) } }
    var floatingButtonShowsCount: Bool { didSet { defaults.set(floatingButtonShowsCount, forKey: Keys.floatingButtonShowsCount) } }
    var floatingButtonShowsAttention: Bool { didSet { defaults.set(floatingButtonShowsAttention, forKey: Keys.floatingButtonShowsAttention) } }
    var floatingButtonEdge: ScreenEdge { didSet { defaults.set(floatingButtonEdge.rawValue, forKey: Keys.floatingButtonEdge) } }
    /// Vertical position as a fraction of the screen's usable height, from the bottom.
    var floatingButtonPosition: Double { didSet { defaults.set(floatingButtonPosition, forKey: Keys.floatingButtonPosition) } }
    /// The display the button belongs to (CGDirectDisplayID), or nil for the main display.
    var floatingButtonDisplay: UInt32? { didSet { defaults.set(floatingButtonDisplay, forKey: Keys.floatingButtonDisplay) } }

    // Notifications
    var notificationsEnabled: Bool { didSet { defaults.set(notificationsEnabled, forKey: Keys.notificationsEnabled) } }
    /// Keep re-notifying until the task is handled.
    var persistentReminders: Bool { didSet { defaults.set(persistentReminders, forKey: Keys.persistentReminders) } }
    var repeatIntervalMinutes: Int { didSet { defaults.set(repeatIntervalMinutes, forKey: Keys.repeatIntervalMinutes) } }
    /// Heads-up reminder given to new tasks that have a due time: minutes before, or nil for none.
    var defaultReminderMinutes: Int? { didSet { defaults.set(defaultReminderMinutes, forKey: Keys.defaultReminderMinutes) } }

    // Shortcuts. Nil means no shortcut; a missing stored value means the default.
    var quickAddShortcut: KeyShortcut? { didSet { storeShortcut(quickAddShortcut, forKey: Keys.quickAddShortcut) } }
    var openTasksShortcut: KeyShortcut? { didSet { storeShortcut(openTasksShortcut, forKey: Keys.openTasksShortcut) } }
    var searchShortcut: KeyShortcut? { didSet { storeShortcut(searchShortcut, forKey: Keys.searchShortcut) } }

    // Panel
    var panelClosesOnOutsideClick: Bool { didSet { defaults.set(panelClosesOnOutsideClick, forKey: Keys.panelClosesOnOutsideClick) } }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: [
            Keys.launchAtLogin: true,
            Keys.appearance: AppearanceMode.system.rawValue,
            Keys.historyDays: 30,
            Keys.onboardingCompleted: false,
            Keys.briefingEnabled: true,
            Keys.briefingOnLaunch: true,
            Keys.briefingOnWake: true,
            Keys.briefingOncePerDay: true,
            Keys.briefingOnlyIfTasks: true,
            Keys.briefingIncludeOverdue: true,
            Keys.briefingIncludeUpcoming: true,
            Keys.briefingSkipWeekends: false,
            Keys.showMenuBarIcon: true,
            Keys.showMenuBarCount: true,
            Keys.floatingButtonEnabled: true,
            Keys.floatingButtonStyle: FloatingButtonStyle.tab.rawValue,
            Keys.floatingButtonNudges: true,
            Keys.nudgeIntervalMinutes: 5,
            Keys.floatingButtonAlwaysOnTop: true,
            Keys.floatingButtonShowsCount: true,
            Keys.floatingButtonShowsAttention: true,
            Keys.floatingButtonEdge: ScreenEdge.right.rawValue,
            Keys.floatingButtonPosition: 0.4,
            Keys.panelClosesOnOutsideClick: true,
            Keys.notificationsEnabled: true,
            Keys.persistentReminders: true,
            Keys.repeatIntervalMinutes: 15,
        ])
        launchAtLogin = defaults.bool(forKey: Keys.launchAtLogin)
        appearance = AppearanceMode(rawValue: defaults.string(forKey: Keys.appearance) ?? "") ?? .system
        historyDays = max(defaults.integer(forKey: Keys.historyDays), 1)
        onboardingCompleted = defaults.bool(forKey: Keys.onboardingCompleted)
        briefingEnabled = defaults.bool(forKey: Keys.briefingEnabled)
        briefingOnLaunch = defaults.bool(forKey: Keys.briefingOnLaunch)
        briefingOnWake = defaults.bool(forKey: Keys.briefingOnWake)
        briefingOncePerDay = defaults.bool(forKey: Keys.briefingOncePerDay)
        briefingOnlyIfTasks = defaults.bool(forKey: Keys.briefingOnlyIfTasks)
        briefingIncludeOverdue = defaults.bool(forKey: Keys.briefingIncludeOverdue)
        briefingIncludeUpcoming = defaults.bool(forKey: Keys.briefingIncludeUpcoming)
        briefingSkipWeekends = defaults.bool(forKey: Keys.briefingSkipWeekends)
        briefingTimeMinutes = (defaults.object(forKey: Keys.briefingTimeMinutes) as? NSNumber)?.intValue
        showMenuBarIcon = defaults.bool(forKey: Keys.showMenuBarIcon)
        showMenuBarCount = defaults.bool(forKey: Keys.showMenuBarCount)
        floatingButtonEnabled = defaults.bool(forKey: Keys.floatingButtonEnabled)
        floatingButtonNudges = defaults.bool(forKey: Keys.floatingButtonNudges)
        nudgeIntervalMinutes = max(defaults.integer(forKey: Keys.nudgeIntervalMinutes), 1)
        floatingButtonStyle = FloatingButtonStyle(rawValue: defaults.string(forKey: Keys.floatingButtonStyle) ?? "") ?? .tab
        floatingButtonAlwaysOnTop = defaults.bool(forKey: Keys.floatingButtonAlwaysOnTop)
        floatingButtonShowsCount = defaults.bool(forKey: Keys.floatingButtonShowsCount)
        floatingButtonShowsAttention = defaults.bool(forKey: Keys.floatingButtonShowsAttention)
        floatingButtonEdge = ScreenEdge(rawValue: defaults.string(forKey: Keys.floatingButtonEdge) ?? "") ?? .right
        floatingButtonPosition = defaults.double(forKey: Keys.floatingButtonPosition)
        floatingButtonDisplay = (defaults.object(forKey: Keys.floatingButtonDisplay) as? NSNumber)?.uint32Value
        panelClosesOnOutsideClick = defaults.bool(forKey: Keys.panelClosesOnOutsideClick)
        notificationsEnabled = defaults.bool(forKey: Keys.notificationsEnabled)
        persistentReminders = defaults.bool(forKey: Keys.persistentReminders)
        repeatIntervalMinutes = max(defaults.integer(forKey: Keys.repeatIntervalMinutes), 1)
        quickAddShortcut = Self.loadShortcut(defaults, Keys.quickAddShortcut, default: .quickAddDefault)
        openTasksShortcut = Self.loadShortcut(defaults, Keys.openTasksShortcut, default: nil)
        searchShortcut = Self.loadShortcut(defaults, Keys.searchShortcut, default: nil)
        defaultReminderMinutes = (defaults.object(forKey: Keys.defaultReminderMinutes) as? NSNumber)?.intValue
    }

    // MARK: - Backup

    /// Current values of every portable setting (not window positions tied to this Mac's displays).
    func exportValues() -> [String: Backup.SettingValue] {
        var result: [String: Backup.SettingValue] = [:]
        for key in Keys.exportable {
            switch defaults.object(forKey: key) {
            case let value as Bool where CFGetTypeID(value as CFTypeRef) == CFBooleanGetTypeID(): result[key] = .bool(value)
            case let value as Int: result[key] = .int(value)
            case let value as Double: result[key] = .double(value)
            case let value as String: result[key] = .string(value)
            case let value as Data: result[key] = .data(value)
            default: break
            }
        }
        return result
    }

    /// Writes imported values for known keys. The app restarts afterwards to apply them.
    func importValues(_ values: [String: Backup.SettingValue]) {
        for (key, value) in values where Keys.exportable.contains(key) {
            switch value {
            case .bool(let v): defaults.set(v, forKey: key)
            case .int(let v): defaults.set(v, forKey: key)
            case .double(let v): defaults.set(v, forKey: key)
            case .string(let v): defaults.set(v, forKey: key)
            case .data(let v): defaults.set(v, forKey: key)
            }
        }
    }

    func shortcut(for action: HotKeyAction) -> KeyShortcut? {
        switch action {
        case .quickAdd: quickAddShortcut
        case .openTasks: openTasksShortcut
        case .search: searchShortcut
        }
    }

    func setShortcut(_ shortcut: KeyShortcut?, for action: HotKeyAction) {
        switch action {
        case .quickAdd: quickAddShortcut = shortcut
        case .openTasks: openTasksShortcut = shortcut
        case .search: searchShortcut = shortcut
        }
    }

    private func storeShortcut(_ shortcut: KeyShortcut?, forKey key: String) {
        // Stored as JSON; "null" records an explicit "no shortcut" so the default isn't restored.
        defaults.set(try? JSONEncoder().encode(shortcut), forKey: key)
    }

    private static func loadShortcut(_ defaults: UserDefaults, _ key: String, default fallback: KeyShortcut?) -> KeyShortcut? {
        guard let data = defaults.data(forKey: key) else { return fallback }
        return (try? JSONDecoder().decode(KeyShortcut?.self, from: data)) ?? fallback
    }

    /// The menu-bar icon is forced on when the floating button is off, so the app is
    /// never left without a visible way in.
    var effectiveShowMenuBarIcon: Bool { showMenuBarIcon || !floatingButtonEnabled }

    private enum Keys {
        static let launchAtLogin = "launchAtLogin"
        static let appearance = "appearance"
        static let historyDays = "history.days"
        static let onboardingCompleted = "onboarding.completed"
        static let defaultReminderMinutes = "notifications.defaultReminderMinutes"
        static let searchShortcut = "shortcut.search"
        static let briefingEnabled = "briefing.enabled"
        static let briefingOnLaunch = "briefing.onLaunch"
        static let briefingOnWake = "briefing.onWake"
        static let briefingOncePerDay = "briefing.oncePerDay"
        static let briefingOnlyIfTasks = "briefing.onlyIfTasks"
        static let briefingIncludeOverdue = "briefing.includeOverdue"
        static let briefingIncludeUpcoming = "briefing.includeUpcoming"
        static let briefingSkipWeekends = "briefing.skipWeekends"
        static let briefingTimeMinutes = "briefing.timeMinutes"
        static let showMenuBarIcon = "showMenuBarIcon"
        static let showMenuBarCount = "showMenuBarCount"
        static let floatingButtonEnabled = "floatingButton.enabled"
        static let floatingButtonStyle = "floatingButton.style"
        static let floatingButtonNudges = "floatingButton.nudges"
        static let nudgeIntervalMinutes = "floatingButton.nudgeIntervalMinutes"
        static let floatingButtonAlwaysOnTop = "floatingButton.alwaysOnTop"
        static let floatingButtonShowsCount = "floatingButton.showsCount"
        static let floatingButtonShowsAttention = "floatingButton.showsAttention"
        static let floatingButtonEdge = "floatingButton.edge"
        static let floatingButtonPosition = "floatingButton.position"
        static let floatingButtonDisplay = "floatingButton.display"
        static let panelClosesOnOutsideClick = "panel.closesOnOutsideClick"
        static let notificationsEnabled = "notifications.enabled"
        static let persistentReminders = "notifications.persistent"
        static let repeatIntervalMinutes = "notifications.repeatIntervalMinutes"
        static let quickAddShortcut = "shortcut.quickAdd"
        static let openTasksShortcut = "shortcut.openTasks"

        /// Everything except this Mac's display arrangement and first-launch state.
        static let exportable = [
            launchAtLogin, appearance, historyDays,
            briefingEnabled, briefingOnLaunch, briefingOnWake, briefingOncePerDay, briefingOnlyIfTasks,
            briefingIncludeOverdue, briefingIncludeUpcoming, briefingSkipWeekends, briefingTimeMinutes,
            showMenuBarIcon, showMenuBarCount,
            floatingButtonEnabled, floatingButtonStyle, floatingButtonNudges, nudgeIntervalMinutes, floatingButtonAlwaysOnTop, floatingButtonShowsCount, floatingButtonShowsAttention,
            floatingButtonEdge, floatingButtonPosition,
            notificationsEnabled, persistentReminders, repeatIntervalMinutes, defaultReminderMinutes,
            quickAddShortcut, openTasksShortcut, searchShortcut,
            panelClosesOnOutsideClick,
        ]
    }
}
