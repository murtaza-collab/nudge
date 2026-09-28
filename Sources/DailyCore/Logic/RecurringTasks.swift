import Foundation

/// Creates the next occurrence of a recurring task when the current one is handled.
public enum RecurringTasks {
    /// The task for the occurrence after `task`, or nil if it doesn't repeat.
    ///
    /// The next date is the first occurrence after the current due day that isn't before
    /// `today`, so handling a long-overdue task doesn't produce another overdue one.
    /// Notification state (snooze, dismissal, mute) starts fresh for the new occurrence.
    public static func nextOccurrence(of task: DailyTask, today: DayKey, now: Date = Date(), calendar: Calendar = .current) -> DailyTask? {
        guard let recurrence = task.recurrence, let dueDay = task.dueDay else { return nil }
        let nextDay = recurrence.nextOccurrence(after: dueDay, notBefore: today, calendar: calendar)

        var next = task
        next.id = UUID()
        next.dueDay = nextDay
        next.seriesID = task.seriesID ?? task.id
        next.completedAt = nil
        next.snoozedUntil = nil
        next.notificationsAcknowledgedAt = nil
        next.notificationsMuted = false
        next.createdAt = now
        next.updatedAt = now
        // An absolute reminder ("Thursday 10 AM" for a Friday task) moves with the due date.
        if case .at(let date) = task.reminder {
            let shift = calendar.dateComponents([.day], from: dueDay.startDate(calendar: calendar), to: nextDay.startDate(calendar: calendar)).day ?? 0
            next.reminder = .at(calendar.date(byAdding: .day, value: shift, to: date) ?? date)
        }
        return next
    }
}
