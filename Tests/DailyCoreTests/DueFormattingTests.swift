import Foundation
import Testing
@testable import DailyCore

@Suite struct DueFormattingTests {
    let today = DayKey(year: 2026, month: 9, day: 28) // Monday
    let locale = Locale(identifier: "en_US")

    func label(_ offset: Int) -> String {
        DueFormatting.dayLabel(today.adding(days: offset, calendar: testCalendar), today: today, calendar: testCalendar, locale: locale)
    }

    @Test func relativeDayLabels() {
        #expect(label(0) == "Today")
        #expect(label(1) == "Tomorrow")
        #expect(label(-1) == "Yesterday")
        #expect(label(4) == "Friday")
        #expect(label(3) == "Thursday")
        #expect(label(7) == "Oct 5")
        #expect(label(-3) == "Sep 25")
    }

    @Test func includesYearWhenDifferent() {
        let nextYear = DayKey(year: 2027, month: 1, day: 15)
        #expect(DueFormatting.dayLabel(nextYear, today: today, calendar: testCalendar, locale: locale) == "Jan 15, 2027")
    }

    @Test func timeFollowsLocale() {
        #expect(DueFormatting.time(minutes: 15 * 60, calendar: testCalendar, locale: locale) == "3:00\u{202F}PM")
        #expect(DueFormatting.time(minutes: 9 * 60 + 5, calendar: testCalendar, locale: Locale(identifier: "en_GB")) == "09:05")
    }

    @Test func dueLabelCombinesDayAndTime() {
        let task = DailyTask(title: "Fix API", dueDay: today.adding(days: -1, calendar: testCalendar), dueMinutes: 15 * 60)
        #expect(DueFormatting.dueLabel(for: task, today: today, calendar: testCalendar, locale: locale) == "Yesterday · 3:00\u{202F}PM")
        #expect(DueFormatting.dueLabel(for: DailyTask(title: "Undated"), today: today, calendar: testCalendar, locale: locale) == nil)
    }

    @Test func dueLabelOmitsImpliedDay() {
        let timed = DailyTask(title: "Meeting", dueDay: today, dueMinutes: 12 * 60)
        let untimed = DailyTask(title: "Anytime", dueDay: today)
        #expect(DueFormatting.dueLabel(for: timed, today: today, impliedDay: today, calendar: testCalendar, locale: locale) == "12:00\u{202F}PM")
        #expect(DueFormatting.dueLabel(for: untimed, today: today, impliedDay: today, calendar: testCalendar, locale: locale) == nil)
        let tomorrow = today.adding(days: 1, calendar: testCalendar)
        #expect(DueFormatting.dueLabel(for: timed, today: today, impliedDay: tomorrow, calendar: testCalendar, locale: locale) == "Today · 12:00\u{202F}PM")
    }
}

@Suite struct RefreshScheduleTests {
    let now = date(2026, 9, 28, 11)
    let today = DayKey(year: 2026, month: 9, day: 28)

    @Test func defaultsToNextMidnight() {
        #expect(TaskGrouping.nextRefreshDate(for: [], now: now, calendar: testCalendar) == date(2026, 9, 29))
    }

    @Test func picksNextUpcomingDueTime() {
        let tasks = [
            DailyTask(title: "Missed", dueDay: today, dueMinutes: 10 * 60),
            DailyTask(title: "Later", dueDay: today, dueMinutes: 16 * 60),
            DailyTask(title: "Soon", dueDay: today, dueMinutes: 12 * 60),
            DailyTask(title: "Untimed", dueDay: today),
        ]
        #expect(TaskGrouping.nextRefreshDate(for: tasks, now: now, calendar: testCalendar) == date(2026, 9, 28, 12))
    }

    @Test func ignoresCompletedAndFarFutureTasks() {
        var done = DailyTask(title: "Done", dueDay: today, dueMinutes: 12 * 60)
        done.completedAt = now
        let nextWeek = DailyTask(title: "Next week", dueDay: today.adding(days: 7, calendar: testCalendar), dueMinutes: 9 * 60)
        #expect(TaskGrouping.nextRefreshDate(for: [done, nextWeek], now: now, calendar: testCalendar) == date(2026, 9, 29))
    }
}
