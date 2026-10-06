import Foundation

public enum Priority: Int, Codable, CaseIterable, Comparable, Sendable {
    case none = 0
    case low = 1
    case medium = 2
    case high = 3
    case critical = 4

    public var title: String {
        switch self {
        case .none: "None"
        case .low: "Low"
        case .medium: "Medium"
        case .high: "High"
        case .critical: "Critical"
        }
    }

    public static func < (lhs: Priority, rhs: Priority) -> Bool { lhs.rawValue < rhs.rawValue }
}

/// When to notify, independent of the due date.
public enum Reminder: Hashable, Sendable {
    case atDueTime
    case minutesBefore(Int)
    /// An absolute moment, e.g. "Thursday 10:00" for a task due Friday.
    case at(Date)
}

extension Reminder: Codable {
    // Explicit, stable JSON shape because it ends up in export files.
    private enum CodingKeys: String, CodingKey { case kind, minutes, date }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        switch try c.decode(String.self, forKey: .kind) {
        case "atDueTime": self = .atDueTime
        case "before": self = .minutesBefore(try c.decode(Int.self, forKey: .minutes))
        case "at": self = .at(try c.decode(Date.self, forKey: .date))
        case let kind:
            throw DecodingError.dataCorruptedError(forKey: .kind, in: c, debugDescription: "Unknown reminder kind \(kind)")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .atDueTime:
            try c.encode("atDueTime", forKey: .kind)
        case .minutesBefore(let minutes):
            try c.encode("before", forKey: .kind)
            try c.encode(minutes, forKey: .minutes)
        case .at(let date):
            try c.encode("at", forKey: .kind)
            try c.encode(date, forKey: .date)
        }
    }
}

public struct TaskLink: Hashable, Codable, Sendable {
    public var title: String
    public var url: URL

    public init(title: String, url: URL) {
        self.title = title
        self.url = url
    }
}

public struct DailyTask: Identifiable, Hashable, Codable, Sendable {
    public var id: UUID
    public var title: String
    public var notes: String
    /// The day the task is due. Nil means undated.
    public var dueDay: DayKey?
    /// Minutes after midnight on `dueDay`. Nil means "sometime that day".
    public var dueMinutes: Int?
    public var reminder: Reminder?
    public var priority: Priority
    public var links: [TaskLink]
    public var recurrence: Recurrence?
    public var categoryID: UUID?
    /// "Don't notify again": silences this task without completing it.
    public var notificationsMuted: Bool
    /// "Remind me later": no notifications before this moment.
    public var snoozedUntil: Date?
    /// Identifies all occurrences of one recurring task.
    public var seriesID: UUID?
    public var createdAt: Date
    public var updatedAt: Date
    public var completedAt: Date?

    public init(
        id: UUID = UUID(),
        title: String,
        notes: String = "",
        dueDay: DayKey? = nil,
        dueMinutes: Int? = nil,
        reminder: Reminder? = nil,
        priority: Priority = .none,
        links: [TaskLink] = [],
        recurrence: Recurrence? = nil,
        categoryID: UUID? = nil,
        notificationsMuted: Bool = false,
        snoozedUntil: Date? = nil,
        seriesID: UUID? = nil,
        createdAt: Date = Date(),
        updatedAt: Date? = nil,
        completedAt: Date? = nil
    ) {
        self.id = id
        self.title = title
        self.notes = notes
        self.dueDay = dueDay
        self.dueMinutes = dueMinutes
        self.reminder = reminder
        self.priority = priority
        self.links = links
        self.recurrence = recurrence
        self.categoryID = categoryID
        self.notificationsMuted = notificationsMuted
        self.snoozedUntil = snoozedUntil
        self.seriesID = seriesID
        self.createdAt = createdAt
        self.updatedAt = updatedAt ?? createdAt
        self.completedAt = completedAt
    }

    public var isCompleted: Bool { completedAt != nil }
    public var hasDueTime: Bool { dueDay != nil && dueMinutes != nil }

    /// The exact due moment, only when both a day and a time are set.
    public func dueDate(calendar: Calendar = .current) -> Date? {
        guard let dueDay, let dueMinutes else { return nil }
        return calendar.date(byAdding: .minute, value: dueMinutes, to: dueDay.startDate(calendar: calendar))
    }

    /// True when the due time or reminder differs from `other`, i.e. the task was rescheduled.
    public func scheduleDiffers(from other: DailyTask) -> Bool {
        dueDay != other.dueDay || dueMinutes != other.dueMinutes || reminder != other.reminder || recurrence != other.recurrence
    }

    /// When the reminder should fire, or nil if it can't be resolved
    /// (e.g. "30 minutes before" on a task without a due time).
    public func reminderDate(calendar: Calendar = .current) -> Date? {
        switch reminder {
        case nil: return nil
        case .at(let date): return date
        case .atDueTime: return dueDate(calendar: calendar)
        case .minutesBefore(let minutes): return dueDate(calendar: calendar)?.addingTimeInterval(-Double(minutes) * 60)
        }
    }
}
