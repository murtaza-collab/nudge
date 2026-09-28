import Foundation
import Testing
@testable import DailyCore

@Suite struct TaskGroupingTests {
    // Monday, Sep 28 2026, 11:00 AM
    let now = date(2026, 9, 28, 11)
    let today = DayKey(year: 2026, month: 9, day: 28)

    func task(_ title: String, day offset: Int?, at minutes: Int? = nil, priority: Priority = .none) -> DailyTask {
        DailyTask(
            title: title,
            dueDay: offset.map { today.adding(days: $0, calendar: testCalendar) },
            dueMinutes: minutes,
            priority: priority
        )
    }

    func group(_ tasks: [DailyTask]) -> TaskGroups {
        TaskGrouping.group(tasks, now: now, calendar: testCalendar)
    }

    @Test func emptyInputProducesEmptyGroups() {
        #expect(group([]).totalCount == 0)
    }

    @Test func bucketsByDay() {
        let groups = group([
            task("Yesterday", day: -1, at: 15 * 60),
            task("Today", day: 0),
            task("Tomorrow", day: 1),
            task("Next week", day: 7),
            task("Undated", day: nil),
        ])
        #expect(groups.overdue.map(\.title) == ["Yesterday"])
        #expect(groups.today.map(\.title) == ["Today", "Undated"])
        #expect(groups.tomorrow.map(\.title) == ["Tomorrow"])
        #expect(groups.upcoming.map(\.title) == ["Next week"])
    }

    @Test func ignoresCompletedTasks() {
        var done = task("Done", day: 0)
        done.completedAt = now
        #expect(group([done]).totalCount == 0)
    }

    @Test func midnightBoundaries() {
        // 23:59 today is still today; 00:00 tomorrow is tomorrow.
        let lateNight = TaskGrouping.group([task("Late", day: 0, at: 23 * 60 + 59)], now: date(2026, 9, 28, 23, 58), calendar: testCalendar)
        #expect(lateNight.today.count == 1)
        let afterMidnight = TaskGrouping.group([task("Late", day: 0, at: 23 * 60 + 59)], now: date(2026, 9, 29, 0, 1), calendar: testCalendar)
        #expect(afterMidnight.overdue.count == 1)
    }

    @Test func pastDueDetection() {
        #expect(TaskGrouping.isPastDue(task("Earlier today", day: 0, at: 10 * 60), now: now, calendar: testCalendar))
        #expect(!TaskGrouping.isPastDue(task("Later today", day: 0, at: 12 * 60), now: now, calendar: testCalendar))
        #expect(!TaskGrouping.isPastDue(task("Today, no time", day: 0), now: now, calendar: testCalendar))
        #expect(TaskGrouping.isPastDue(task("Yesterday, no time", day: -1), now: now, calendar: testCalendar))
        #expect(!TaskGrouping.isPastDue(task("Undated", day: nil), now: now, calendar: testCalendar))
    }

    @Test func todaySortsPastDueThenPriorityThenTime() {
        let groups = group([
            task("Untimed low", day: 0, priority: .low),
            task("4pm", day: 0, at: 16 * 60),
            task("Undated", day: nil),
            task("12pm", day: 0, at: 12 * 60),
            task("10am missed", day: 0, at: 10 * 60),
            task("5pm critical", day: 0, at: 17 * 60, priority: .critical),
        ])
        #expect(groups.today.map(\.title) == [
            "10am missed",
            "5pm critical",
            "Untimed low",
            "12pm",
            "4pm",
            "Undated",
        ])
    }

    @Test func upcomingSortsByDayFirst() {
        let groups = group([
            task("In 5 days", day: 5, priority: .critical),
            task("In 3 days", day: 3),
        ])
        #expect(groups.upcoming.map(\.title) == ["In 3 days", "In 5 days"])
    }

    @Test func manyTasks() {
        let tasks = (0..<500).map { task("T\($0)", day: $0 % 10 - 3, at: ($0 * 7) % 1440, priority: Priority(rawValue: $0 % 5)!) }
        let groups = group(tasks)
        #expect(groups.totalCount == 500)
        #expect(groups.overdue.count == 150)
        #expect(groups.today.count == 50)
    }
}
