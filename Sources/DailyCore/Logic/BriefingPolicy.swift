import Foundation

public enum BriefingTrigger: Sendable {
    /// The app started (normally at login).
    case launch
    /// The Mac or its display woke, or the screen was unlocked.
    case wake
    /// The user's preferred briefing time arrived while the Mac was on.
    case scheduled
    /// Asked for from the menu. Always shown.
    case manual
}

public struct BriefingPreferences: Sendable {
    public var enabled = true
    public var onLaunch = true
    public var onWake = true
    public var oncePerDay = true
    public var onlyIfTasks = true
    public var skipWeekends = false

    public init(enabled: Bool = true, onLaunch: Bool = true, onWake: Bool = true, oncePerDay: Bool = true, onlyIfTasks: Bool = true, skipWeekends: Bool = false) {
        self.enabled = enabled
        self.onLaunch = onLaunch
        self.onWake = onWake
        self.oncePerDay = oncePerDay
        self.onlyIfTasks = onlyIfTasks
        self.skipWeekends = skipWeekends
    }
}

/// Decides whether the daily briefing should appear. Automatic triggers respect every
/// preference; a manual request always shows it.
public enum BriefingPolicy {
    public static func shouldShow(
        _ trigger: BriefingTrigger,
        preferences: BriefingPreferences,
        today: DayKey,
        lastShown: DayKey?,
        hasTasks: Bool,
        isWeekend: Bool
    ) -> Bool {
        if case .manual = trigger { return true }
        guard preferences.enabled else { return false }
        switch trigger {
        case .launch: guard preferences.onLaunch else { return false }
        case .wake: guard preferences.onWake else { return false }
        case .scheduled, .manual: break
        }
        if preferences.skipWeekends && isWeekend { return false }
        if preferences.oncePerDay && lastShown == today { return false }
        if preferences.onlyIfTasks && !hasTasks { return false }
        return true
    }

    /// "Good morning" / "Good afternoon" / "Good evening".
    public static func greeting(hour: Int) -> String {
        switch hour {
        case 5..<12: "Good morning"
        case 12..<17: "Good afternoon"
        default: "Good evening"
        }
    }
}
