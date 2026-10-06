import Foundation
import Testing
@testable import DailyCore

@Suite struct NotificationPlannerTests {
    let today = DayKey(year: 2026, month: 9, day: 28)
    let planner = NotificationPlanner(repeatInterval: 15 * 60, persistent: true, perTaskLimit: 3)

    func task(dueAt minutes: Int?, reminder: Reminder? = nil) -> DailyTask {
        DailyTask(title: "T", dueDay: minutes == nil ? nil : today, dueMinutes: minutes, reminder: reminder)
    }

    func fires(_ task: DailyTask, now: Date, planner: NotificationPlanner? = nil) -> [(Date, PlannedNotification.Kind)] {
        (planner ?? self.planner).plan(for: [task], now: now, calendar: testCalendar).map { ($0.fireDate, $0.kind) }
    }

    @Test func futureDueTaskFiresAtDueTimeThenRepeats() {
        let result = fires(task(dueAt: 15 * 60), now: date(2026, 9, 28, 11))
        #expect(result.map(\.0) == [date(2026, 9, 28, 15), date(2026, 9, 28, 15, 15), date(2026, 9, 28, 15, 30)])
        #expect(result.map(\.1) == [.due, .repeated, .repeated])
    }

    @Test func overdueTaskContinuesOnGrid() {
        // Due 3:00 PM, now 3:20 PM: next repeats are 3:30, 3:45, 4:00.
        let result = fires(task(dueAt: 15 * 60), now: date(2026, 9, 28, 15, 20))
        #expect(result.map(\.0) == [date(2026, 9, 28, 15, 30), date(2026, 9, 28, 15, 45), date(2026, 9, 28, 16)])
    }

    @Test func exactlyOnGridSchedulesNextSlot() {
        let result = fires(task(dueAt: 15 * 60), now: date(2026, 9, 28, 15, 15))
        #expect(result.first?.0 == date(2026, 9, 28, 15, 30))
    }

    @Test func earlierReminderIsHeadsUp() {
        let t = task(dueAt: 16 * 60, reminder: .minutesBefore(30))
        let result = fires(t, now: date(2026, 9, 28, 11))
        #expect(result.map(\.0) == [date(2026, 9, 28, 15, 30), date(2026, 9, 28, 16), date(2026, 9, 28, 16, 15)])
        #expect(result.map(\.1) == [.reminder, .due, .repeated])
    }

    @Test func atDueTimeReminderDoesNotDuplicate() {
        let result = fires(task(dueAt: 16 * 60, reminder: .atDueTime), now: date(2026, 9, 28, 11))
        #expect(result.filter { $0.1 == .reminder }.isEmpty)
        #expect(result.first?.0 == date(2026, 9, 28, 16))
    }

    @Test func reminderOnlyTaskStartsLoopAtReminder() {
        let t = task(dueAt: nil, reminder: .at(date(2026, 9, 28, 14)))
        let result = fires(t, now: date(2026, 9, 28, 11))
        #expect(result.map(\.0) == [date(2026, 9, 28, 14), date(2026, 9, 28, 14, 15), date(2026, 9, 28, 14, 30)])
        #expect(result.first?.1 == .due)
    }

    @Test func dateOnlyTaskHasNoNotifications() {
        let t = DailyTask(title: "T", dueDay: today)
        #expect(fires(t, now: date(2026, 9, 28, 11)).isEmpty)
    }

    @Test func mutedAndCompletedTasksAreSilent() {
        var muted = task(dueAt: 15 * 60)
        muted.notificationsMuted = true
        var done = task(dueAt: 15 * 60)
        done.completedAt = date(2026, 9, 28, 10)
        #expect(planner.plan(for: [muted, done], now: date(2026, 9, 28, 11), calendar: testCalendar).isEmpty)
    }

    @Test func snoozeSuppressesUntilThenResumes() {
        var t = task(dueAt: 15 * 60)
        t.snoozedUntil = date(2026, 9, 28, 15, 40)
        let result = fires(t, now: date(2026, 9, 28, 15, 10))
        #expect(result.map(\.0) == [date(2026, 9, 28, 15, 40), date(2026, 9, 28, 15, 55), date(2026, 9, 28, 16, 10)])
    }

    @Test func expiredSnoozeIsIgnored() {
        var t = task(dueAt: 15 * 60)
        t.snoozedUntil = date(2026, 9, 28, 15, 5)
        #expect(fires(t, now: date(2026, 9, 28, 15, 20)).first?.0 == date(2026, 9, 28, 15, 30))
    }

    @Test func rescheduledTaskPlansFromNewTime() {
        var t = task(dueAt: 15 * 60)
        t.dueMinutes = 17 * 60
        #expect(fires(t, now: date(2026, 9, 28, 15, 10)).first?.0 == date(2026, 9, 28, 17))
        #expect(NotificationPlanner.isNotifiable(t, calendar: testCalendar))
    }

    @Test func nonPersistentFiresOnce() {
        let once = NotificationPlanner(repeatInterval: 15 * 60, persistent: false)
        #expect(fires(task(dueAt: 15 * 60), now: date(2026, 9, 28, 11), planner: once).map(\.0) == [date(2026, 9, 28, 15)])
        #expect(fires(task(dueAt: 15 * 60), now: date(2026, 9, 28, 16), planner: once).isEmpty)
    }

    @Test func customInterval() {
        let fiveMinutes = NotificationPlanner(repeatInterval: 5 * 60)
        let result = fires(task(dueAt: 15 * 60), now: date(2026, 9, 28, 15, 1), planner: fiveMinutes)
        #expect(result.map(\.0) == [date(2026, 9, 28, 15, 5), date(2026, 9, 28, 15, 10), date(2026, 9, 28, 15, 15)])
    }

    @Test func totalLimitKeepsSoonest() {
        let tasks = (0..<40).map { i in DailyTask(title: "T\(i)", dueDay: today, dueMinutes: 12 * 60 + i) }
        let plan = NotificationPlanner(totalLimit: 60).plan(for: tasks, now: date(2026, 9, 28, 11), calendar: testCalendar)
        #expect(plan.count == 60)
        #expect(plan.first?.fireDate == date(2026, 9, 28, 12))
        #expect(zip(plan, plan.dropFirst()).allSatisfy { $0.fireDate <= $1.fireDate })
    }

    @Test func rescheduleDetection() {
        let t = task(dueAt: 15 * 60)
        var moved = t
        moved.dueMinutes = 16 * 60
        var renamed = t
        renamed.title = "New"
        #expect(moved.scheduleDiffers(from: t))
        #expect(!renamed.scheduleDiffers(from: t))
    }
}
