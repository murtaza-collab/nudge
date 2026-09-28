import Foundation

/// How a task repeats. Only the next occurrence is ever materialized: completing one
/// occurrence creates the next.
///
/// Weekdays use Calendar numbering: 1 = Sunday … 7 = Saturday.
public struct Recurrence: Hashable, Codable, Sendable {
    public enum Frequency: String, Codable, Sendable {
        case daily, weekly, monthly
    }

    public var frequency: Frequency
    /// Every `interval` days / weeks / months.
    public var interval: Int
    /// Weekly: which days. Empty means "the weekday of the first occurrence".
    public var weekdays: [Int]
    /// Monthly by date: day of month (1–31, clamped to short months).
    public var monthDay: Int?
    /// Monthly by position: 1–4 for "1st"…"4th", -1 for "last" (with `ordinalWeekday`).
    public var ordinal: Int?
    public var ordinalWeekday: Int?

    public init(frequency: Frequency, interval: Int = 1, weekdays: [Int] = [], monthDay: Int? = nil, ordinal: Int? = nil, ordinalWeekday: Int? = nil) {
        self.frequency = frequency
        self.interval = max(interval, 1)
        self.weekdays = Array(Set(weekdays)).sorted()
        self.monthDay = monthDay
        self.ordinal = ordinal
        self.ordinalWeekday = ordinalWeekday
    }

    public static let daily = Recurrence(frequency: .daily)
    public static let weekdaysOnly = Recurrence(frequency: .weekly, weekdays: [2, 3, 4, 5, 6])

    /// Fills in details left implicit ("every week", "monthly") from the first occurrence's day.
    public func anchored(to day: DayKey, calendar: Calendar = .current) -> Recurrence {
        var copy = self
        switch frequency {
        case .daily:
            break
        case .weekly:
            if copy.weekdays.isEmpty { copy.weekdays = [day.weekday(calendar: calendar)] }
        case .monthly:
            if copy.monthDay == nil && copy.ordinal == nil { copy.monthDay = day.day }
        }
        return copy
    }

    // MARK: - Occurrences

    /// The first day on or after `day` that matches the rule.
    public func firstOccurrence(onOrAfter day: DayKey, calendar: Calendar = .current) -> DayKey {
        switch frequency {
        case .daily:
            return day
        case .weekly:
            guard !weekdays.isEmpty else { return day }
            var candidate = day
            for _ in 0..<7 {
                if weekdays.contains(candidate.weekday(calendar: calendar)) { return candidate }
                candidate = candidate.adding(days: 1, calendar: calendar)
            }
            return day
        case .monthly:
            if monthDay == nil && ordinal == nil { return day } // "monthly": starts on the given day
            var month = (year: day.year, month: day.month)
            for _ in 0..<24 {
                if let candidate = monthlyDay(year: month.year, month: month.month, calendar: calendar), candidate >= day {
                    return candidate
                }
                month = Self.addMonths(1, to: month)
            }
            return day
        }
    }

    /// The occurrence immediately after `previous`.
    public func occurrence(after previous: DayKey, calendar: Calendar = .current) -> DayKey {
        switch frequency {
        case .daily:
            return previous.adding(days: interval, calendar: calendar)
        case .weekly:
            guard !weekdays.isEmpty else { return previous.adding(days: 7 * interval, calendar: calendar) }
            // Weeks run Monday–Sunday. Later days this week first, otherwise the first
            // listed day `interval` weeks on.
            let order = weekdays.sorted { Self.mondayIndex($0) < Self.mondayIndex($1) }
            let previousIndex = Self.mondayIndex(previous.weekday(calendar: calendar))
            if let next = order.first(where: { Self.mondayIndex($0) > previousIndex }) {
                return previous.adding(days: Self.mondayIndex(next) - previousIndex, calendar: calendar)
            }
            let weekStart = previous.adding(days: -previousIndex, calendar: calendar)
            return weekStart.adding(days: 7 * interval + Self.mondayIndex(order[0]), calendar: calendar)
        case .monthly:
            var month = (year: previous.year, month: previous.month)
            for _ in 0..<48 {
                month = Self.addMonths(interval, to: month)
                // A month without this date (e.g. no 5th Tuesday) is skipped.
                if let candidate = monthlyDay(year: month.year, month: month.month, calendar: calendar) {
                    return candidate
                }
            }
            return previous.adding(days: 30 * interval, calendar: calendar)
        }
    }

    /// The first occurrence after `previous` that isn't before `floor`, so completing a
    /// long-overdue recurring task doesn't create another occurrence that's already overdue.
    public func nextOccurrence(after previous: DayKey, notBefore floor: DayKey, calendar: Calendar = .current) -> DayKey {
        var day = occurrence(after: previous, calendar: calendar)
        var guardCount = 0
        while day < floor && guardCount < 10_000 {
            day = occurrence(after: day, calendar: calendar)
            guardCount += 1
        }
        return day
    }

    private func monthlyDay(year: Int, month: Int, calendar: Calendar) -> DayKey? {
        let first = DayKey(year: year, month: month, day: 1)
        let length = calendar.range(of: .day, in: .month, for: first.startDate(calendar: calendar))?.count ?? 28
        if let ordinal, let weekday = ordinalWeekday {
            let firstWeekday = first.weekday(calendar: calendar)
            if ordinal > 0 {
                let day = 1 + (weekday - firstWeekday + 7) % 7 + (ordinal - 1) * 7
                return day <= length ? DayKey(year: year, month: month, day: day) : nil
            }
            let lastWeekday = DayKey(year: year, month: month, day: length).weekday(calendar: calendar)
            return DayKey(year: year, month: month, day: length - (lastWeekday - weekday + 7) % 7)
        }
        let day = min(monthDay ?? 1, length)
        return DayKey(year: year, month: month, day: day)
    }

    private static func addMonths(_ count: Int, to month: (year: Int, month: Int)) -> (year: Int, month: Int) {
        let zeroBased = month.year * 12 + (month.month - 1) + count
        return (zeroBased / 12, zeroBased % 12 + 1)
    }

    /// Monday = 0 … Sunday = 6.
    private static func mondayIndex(_ weekday: Int) -> Int { (weekday + 5) % 7 }

    // MARK: - Description

    /// "Every Monday", "Every weekday", "Every 2 weeks on Tue, Thu", "2nd Tuesday of every month".
    public func summary(calendar: Calendar = .current, locale: Locale = .current) -> String {
        var symbols = calendar
        symbols.locale = locale
        let names = symbols.weekdaySymbols
        let shortNames = symbols.shortWeekdaySymbols
        switch frequency {
        case .daily:
            return interval == 1 ? "Every day" : interval == 2 ? "Every other day" : "Every \(interval) days"
        case .weekly:
            let sortedDays = weekdays.sorted { Self.mondayIndex($0) < Self.mondayIndex($1) }
            if interval == 1 && sortedDays == [2, 3, 4, 5, 6] { return "Every weekday" }
            if interval == 1 && sortedDays.count == 7 { return "Every day" }
            let prefix = interval == 1 ? "Every" : interval == 2 ? "Every other" : "Every \(interval) weeks on"
            switch sortedDays.count {
            case 0: return interval == 1 ? "Every week" : interval == 2 ? "Every other week" : "Every \(interval) weeks"
            case 1: return "\(prefix) \(names[sortedDays[0] - 1])"
            default: return "\(prefix) \(sortedDays.map { shortNames[$0 - 1] }.joined(separator: ", "))"
            }
        case .monthly:
            let every = interval == 1 ? "every month" : interval == 2 ? "every other month" : "every \(interval) months"
            if let ordinal, let weekday = ordinalWeekday {
                let position = ordinal == -1 ? "Last" : Self.ordinalString(ordinal)
                return "\(position) \(names[weekday - 1]) of \(every)"
            }
            let day = monthDay.map(Self.ordinalString) ?? "same day"
            return interval == 1 ? "Monthly on the \(day)" : "\(every.prefix(1).uppercased() + every.dropFirst()) on the \(day)"
        }
    }

    static func ordinalString(_ n: Int) -> String {
        let suffix: String
        switch (n % 10, n % 100) {
        case (_, 11...13): suffix = "th"
        case (1, _): suffix = "st"
        case (2, _): suffix = "nd"
        case (3, _): suffix = "rd"
        default: suffix = "th"
        }
        return "\(n)\(suffix)"
    }
}

extension DayKey {
    /// 1 = Sunday … 7 = Saturday.
    public func weekday(calendar: Calendar = .current) -> Int {
        calendar.component(.weekday, from: startDate(calendar: calendar))
    }
}
