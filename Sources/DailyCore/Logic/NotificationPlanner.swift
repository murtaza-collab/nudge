import Foundation

public struct PlannedNotification: Hashable, Sendable {
    public enum Kind: Hashable, Sendable {
        /// A heads-up before the due time ("Thursday 10 AM" for a task due Friday).
        case reminder
        /// The first notification when the task is due.
        case due
        /// A follow-up because the task still hasn't been handled.
        case repeated
    }

    public let taskID: UUID
    public let fireDate: Date
    public let kind: Kind

    public init(taskID: UUID, fireDate: Date, kind: Kind) {
        self.taskID = taskID
        self.fireDate = fireDate
        self.kind = kind
    }
}

/// Decides which notifications should be scheduled. Pure logic; the app turns the plan
/// into UserNotifications requests and re-plans whenever tasks change or one fires.
///
/// Rules:
/// - A task's reminder loop starts at its due time, or at its reminder if it has no due time.
/// - A reminder earlier than the due time fires once, as a heads-up.
/// - When persistent, the loop repeats every `repeatInterval` until the task is completed,
///   muted ("Don't notify again"), or rescheduled. Closing a notification doesn't stop it.
/// - "Remind me later" (`snoozedUntil`) suppresses everything until then; the loop resumes from there.
public struct NotificationPlanner: Sendable {
    public var repeatInterval: TimeInterval
    public var persistent: Bool
    /// Upcoming notifications scheduled per task. The app re-plans after each delivery,
    /// so a few is enough to survive the app not running for a while.
    public var perTaskLimit: Int
    /// macOS keeps at most 64 pending requests per app.
    public var totalLimit: Int

    public init(repeatInterval: TimeInterval = 15 * 60, persistent: Bool = true, perTaskLimit: Int = 3, totalLimit: Int = 60) {
        self.repeatInterval = max(repeatInterval, 60)
        self.persistent = persistent
        self.perTaskLimit = perTaskLimit
        self.totalLimit = totalLimit
    }

    /// The moment the reminder loop begins, if the task has one.
    public static func loopStart(for task: DailyTask, calendar: Calendar = .current) -> Date? {
        task.dueDate(calendar: calendar) ?? task.reminderDate(calendar: calendar)
    }

    /// Whether the task can still produce notifications (ignoring timing).
    public static func isNotifiable(_ task: DailyTask, calendar: Calendar = .current) -> Bool {
        !task.isCompleted && !task.notificationsMuted && loopStart(for: task, calendar: calendar) != nil
    }

    public func plan(for tasks: [DailyTask], now: Date = Date(), calendar: Calendar = .current) -> [PlannedNotification] {
        let all = tasks.flatMap { plan(for: $0, now: now, calendar: calendar) }
        return Array(all.sorted { $0.fireDate < $1.fireDate }.prefix(totalLimit))
    }

    func plan(for task: DailyTask, now: Date, calendar: Calendar) -> [PlannedNotification] {
        guard !task.isCompleted, !task.notificationsMuted,
              let start = Self.loopStart(for: task, calendar: calendar) else { return [] }

        let snooze = task.snoozedUntil.flatMap { $0 > now ? $0 : nil }
        let earliest = snooze ?? now
        var result: [PlannedNotification] = []

        // Heads-up reminder before the due time.
        if let reminder = task.reminderDate(calendar: calendar), reminder < start, reminder > earliest {
            result.append(PlannedNotification(taskID: task.id, fireDate: reminder, kind: .reminder))
        }

        if let snooze {
            // Resume from the snooze time, then keep the normal interval from there.
            result.append(PlannedNotification(taskID: task.id, fireDate: snooze, kind: .repeated))
            if persistent {
                result += repeats(after: snooze, from: snooze, task: task)
            }
        } else if start > now {
            result.append(PlannedNotification(taskID: task.id, fireDate: start, kind: .due))
            if persistent {
                result += repeats(after: start, from: start, task: task)
            }
        } else if persistent {
            // Already due: continue on the grid anchored at the due time.
            result += repeats(after: now, from: start, task: task)
        }

        return Array(result.sorted { $0.fireDate < $1.fireDate }.prefix(perTaskLimit))
    }

    /// Next `perTaskLimit` times strictly after `after`, on the grid `anchor + k * interval`.
    private func repeats(after: Date, from anchor: Date, task: DailyTask) -> [PlannedNotification] {
        let elapsed = after.timeIntervalSince(anchor)
        var k = max(Int((elapsed / repeatInterval).rounded(.down)) + 1, 1)
        var result: [PlannedNotification] = []
        while result.count < perTaskLimit {
            result.append(PlannedNotification(taskID: task.id, fireDate: anchor.addingTimeInterval(Double(k) * repeatInterval), kind: .repeated))
            k += 1
        }
        return result
    }
}
