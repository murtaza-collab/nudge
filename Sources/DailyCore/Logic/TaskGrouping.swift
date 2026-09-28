import Foundation

public enum TaskSection: String, CaseIterable, Sendable {
    case overdue, today, tomorrow, upcoming

    public var title: String {
        switch self {
        case .overdue: "Overdue"
        case .today: "Today"
        case .tomorrow: "Tomorrow"
        case .upcoming: "Upcoming"
        }
    }
}

public struct TaskGroups: Equatable, Sendable {
    public var overdue: [DailyTask] = []
    public var today: [DailyTask] = []
    public var tomorrow: [DailyTask] = []
    public var upcoming: [DailyTask] = []

    public init() {}

    public subscript(section: TaskSection) -> [DailyTask] {
        switch section {
        case .overdue: overdue
        case .today: today
        case .tomorrow: tomorrow
        case .upcoming: upcoming
        }
    }

    public var totalCount: Int { overdue.count + today.count + tomorrow.count + upcoming.count }
}

/// Buckets active tasks into Overdue / Today / Tomorrow / Upcoming.
///
/// - Overdue: due on a day before today.
/// - Today: due today (including ones whose time has already passed) and tasks with no due date,
///   so an undated task is never hidden away.
/// - Tomorrow: due tomorrow.
/// - Upcoming: due after tomorrow.
public enum TaskGrouping {
    public static func group(_ tasks: [DailyTask], now: Date = Date(), calendar: Calendar = .current) -> TaskGroups {
        let today = DayKey(now, calendar: calendar)
        let tomorrow = today.adding(days: 1, calendar: calendar)

        var groups = TaskGroups()
        for task in tasks where !task.isCompleted {
            guard let day = task.dueDay else {
                groups.today.append(task)
                continue
            }
            if day < today {
                groups.overdue.append(task)
            } else if day == today {
                groups.today.append(task)
            } else if day == tomorrow {
                groups.tomorrow.append(task)
            } else {
                groups.upcoming.append(task)
            }
        }

        let order = { (a: DailyTask, b: DailyTask) in sortsBefore(a, b, now: now, calendar: calendar) }
        groups.overdue.sort(by: order)
        groups.today.sort(by: order)
        groups.tomorrow.sort(by: order)
        groups.upcoming.sort(by: order)
        return groups
    }

    /// True when the task's due moment has passed. Tasks due on an earlier day are
    /// past due even without a time; tasks due today without a time are not.
    public static func isPastDue(_ task: DailyTask, now: Date = Date(), calendar: Calendar = .current) -> Bool {
        guard !task.isCompleted, let day = task.dueDay else { return false }
        if day < DayKey(now, calendar: calendar) { return true }
        return task.dueDate(calendar: calendar).map { $0 <= now } ?? false
    }

    /// Within a section: past-due first, then earlier day, then higher priority,
    /// then earlier time (timed before untimed), then creation order.
    static func sortsBefore(_ a: DailyTask, _ b: DailyTask, now: Date, calendar: Calendar) -> Bool {
        let aPast = isPastDue(a, now: now, calendar: calendar)
        let bPast = isPastDue(b, now: now, calendar: calendar)
        if aPast != bPast { return aPast }

        switch (a.dueDay, b.dueDay) {
        case let (x?, y?) where x != y: return x < y
        case (_?, nil): return true
        case (nil, _?): return false
        default: break
        }

        if a.priority != b.priority { return a.priority > b.priority }

        switch (a.dueMinutes, b.dueMinutes) {
        case let (x?, y?) where x != y: return x < y
        case (_?, nil): return true
        case (nil, _?): return false
        default: break
        }

        return a.createdAt < b.createdAt
    }
}
