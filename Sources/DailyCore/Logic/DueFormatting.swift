import Foundation

/// Short, human labels for due dates: "Today", "Yesterday", "Friday", "Oct 1".
public enum DueFormatting {
    public static func dayLabel(_ day: DayKey, today: DayKey, calendar: Calendar = .current, locale: Locale = .current) -> String {
        let start = today.startDate(calendar: calendar)
        let offset = calendar.dateComponents([.day], from: start, to: day.startDate(calendar: calendar)).day ?? 0
        switch offset {
        case 0: return "Today"
        case 1: return "Tomorrow"
        case -1: return "Yesterday"
        case 2...6:
            return formatted(day, template: "EEEE", calendar: calendar, locale: locale)
        default:
            let template = day.year == today.year ? "MMMd" : "yMMMd"
            return formatted(day, template: template, calendar: calendar, locale: locale)
        }
    }

    /// "3:00 PM" / "15:00" depending on the user's locale.
    public static func time(minutes: Int, calendar: Calendar = .current, locale: Locale = .current) -> String {
        let reference = calendar.date(from: DateComponents(year: 2000, month: 1, day: 1, hour: minutes / 60, minute: minutes % 60))!
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = locale
        formatter.setLocalizedDateFormatFromTemplate("jmm")
        return formatter.string(from: reference)
    }

    /// "Yesterday · 3:00 PM", "Friday", or nil for undated tasks.
    ///
    /// When the task is due on `impliedDay` (e.g. it's listed under a "Today" heading) the day
    /// is left out, giving just "3:00 PM", or nil if there's no time either.
    public static func dueLabel(
        for task: DailyTask,
        today: DayKey,
        impliedDay: DayKey? = nil,
        calendar: Calendar = .current,
        locale: Locale = .current
    ) -> String? {
        guard let day = task.dueDay else { return nil }
        let timeText = task.dueMinutes.map { time(minutes: $0, calendar: calendar, locale: locale) }
        if day == impliedDay { return timeText }
        let dayText = dayLabel(day, today: today, calendar: calendar, locale: locale)
        return timeText.map { "\(dayText) · \($0)" } ?? dayText
    }

    private static func formatted(_ day: DayKey, template: String, calendar: Calendar, locale: Locale) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = locale
        formatter.setLocalizedDateFormatFromTemplate(template)
        return formatter.string(from: day.startDate(calendar: calendar))
    }
}

extension TaskGrouping {
    /// The next moment the grouped list can change on its own: the next midnight, or the
    /// next due time that will make a task past due, whichever comes first. The app sets a
    /// single timer for this instead of polling.
    public static func nextRefreshDate(for tasks: [DailyTask], now: Date = Date(), calendar: Calendar = .current) -> Date {
        let nextMidnight = DayKey(now, calendar: calendar).adding(days: 1, calendar: calendar).startDate(calendar: calendar)
        let nextDue = tasks
            .filter { !$0.isCompleted }
            .compactMap { $0.dueDate(calendar: calendar) }
            .filter { $0 > now }
            .min()
        return min(nextMidnight, nextDue ?? nextMidnight)
    }
}
