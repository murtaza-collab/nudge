import Foundation
import Testing
@testable import DailyCore

@Suite struct NaturalLanguageParserTests {
    // Monday, Sep 28 2026, 11:00 AM
    let now = date(2026, 9, 28, 11)
    let parser = NaturalLanguageParser(calendar: testCalendar, locale: Locale(identifier: "en_US"))

    func day(_ offset: Int) -> DayKey {
        DayKey(year: 2026, month: 9, day: 28).adding(days: offset, calendar: testCalendar)
    }

    func parse(_ text: String) -> ParsedInput { parser.parse(text, now: now) }

    // MARK: Spec examples

    @Test func callAlexTomorrow11am() {
        #expect(parse("Call Alex tomorrow 11am") == ParsedInput(title: "Call Alex", dueDay: day(1), dueMinutes: 11 * 60))
    }

    @Test func fixPayFlowTomorrow3pm() {
        #expect(parse("Fix PayFlow API tomorrow 3pm") == ParsedInput(title: "Fix PayFlow API", dueDay: day(1), dueMinutes: 15 * 60))
    }

    @Test func reviewMetricsEveryMonday10am() {
        let result = parse("Review metrics every Monday 10am")
        #expect(result.title == "Review metrics")
        #expect(result.recurrence == Recurrence(frequency: .weekly, weekdays: [2]))
        // Today is Monday but 10am has passed, so the first one is next Monday.
        #expect(result.dueDay == day(7))
        #expect(result.dueMinutes == 10 * 60)
    }

    @Test func recurringTodayWhenTimeStillAhead() {
        let result = parse("Standup every Monday 2pm")
        #expect(result.dueDay == day(0))
    }

    // MARK: Plain titles stay plain

    @Test(arguments: [
        "Buy milk",
        "Read chapter 3",
        "Prepare Monday report",
        "Walk in the sun",
        "Rate the talk 4/5",
        "Deploy v2.30",
        "Buy 2 apples",
        "Call mom at 5:30",
        "Plan A",
        "Chapter 2 a",
        "Meeting notes for sat",
    ])
    func leavesPlainTitlesAlone(_ text: String) {
        #expect(parse(text) == ParsedInput(title: text))
    }

    @Test func onlyDateWordsStayAsTitle() {
        #expect(parse("tomorrow") == ParsedInput(title: "tomorrow"))
        #expect(parse("  tomorrow 3pm ") == ParsedInput(title: "tomorrow 3pm"))
    }

    // MARK: Times

    @Test(arguments: [
        ("Call at 3pm", 15 * 60), ("Call 3 pm", 15 * 60), ("Call 3:30pm", 15 * 60 + 30), ("Call 3.30 PM", 15 * 60 + 30),
        ("Call 11 a.m.", 11 * 60 + 0), ("Call 3p", 15 * 60), ("Call 12am", 0), ("Call 12pm", 12 * 60),
        ("Call @4pm", 16 * 60), ("Call 17:30", 17 * 60 + 30), ("Call at 09:15", 9 * 60 + 15), ("Call 12:45", 12 * 60 + 45),
        ("Lunch at noon", 12 * 60),
    ])
    func times(_ text: String, _ minutes: Int) {
        let result = parse(text)
        #expect(result.dueMinutes == minutes, "\(text)")
        #expect(result.title == (text.hasPrefix("Lunch") ? "Lunch" : "Call"), "\(text)")
    }

    @Test func timeOnlyIsTodayIfAheadElseTomorrow() {
        #expect(parse("Call 3pm").dueDay == day(0))
        #expect(parse("Call 9am").dueDay == day(1))
    }

    @Test func invalidTimesAreNotParsed() {
        #expect(parse("Call 13pm") == ParsedInput(title: "Call 13pm"))
        #expect(parse("Call 25:00") == ParsedInput(title: "Call 25:00"))
    }

    // MARK: Dates

    @Test(arguments: [
        ("Pay rent today", 0), ("Pay rent tonight", 0), ("Pay rent tomorrow", 1), ("Pay rent tmrw", 1),
        ("Pay rent tommorow", 1), ("Pay rent tomorow", 1), ("Pay rent tommorrow", 1),
        ("Pay rent day after tomorrow", 2), ("Pay rent next week", 7), ("Pay rent in 3 days", 3),
        ("Pay rent in a week", 7), ("Pay rent in 2 weeks", 14),
        ("Pay rent Friday", 4), ("Pay rent on Friday", 4), ("Pay rent by Fri", 4), ("Pay rent next fri", 4),
        ("Pay rent Monday", 7), ("Pay rent this Monday", 0), ("Pay rent on sat", 5),
    ])
    func relativeDates(_ text: String, _ offset: Int) {
        let result = parse(text)
        #expect(result.dueDay == day(offset), "\(text)")
        #expect(result.title == "Pay rent", "\(text)")
        #expect(result.dueMinutes == nil)
    }

    @Test func monthNames() {
        #expect(parse("Report Oct 1").dueDay == DayKey(year: 2026, month: 10, day: 1))
        #expect(parse("Report on October 1st").dueDay == DayKey(year: 2026, month: 10, day: 1))
        #expect(parse("Report 1 Oct").dueDay == DayKey(year: 2026, month: 10, day: 1))
        #expect(parse("Report the 3rd of December").dueDay == DayKey(year: 2026, month: 12, day: 3))
        #expect(parse("Report Mar 5, 2027").dueDay == DayKey(year: 2027, month: 3, day: 5))
        #expect(parse("Report Sept 30").dueDay == DayKey(year: 2026, month: 9, day: 30))
    }

    @Test func pastDateWithoutYearRollsToNextYear() {
        #expect(parse("Taxes Jan 15").dueDay == DayKey(year: 2027, month: 1, day: 15))
        #expect(parse("Taxes Sep 27").dueDay == DayKey(year: 2027, month: 9, day: 27))
        #expect(parse("Taxes Sep 28").dueDay == day(0))
    }

    @Test func impossibleDatesAreNotParsed() {
        #expect(parse("Report Feb 30") == ParsedInput(title: "Report Feb 30"))
    }

    @Test func isoAndNumericDates() {
        #expect(parse("Report 2026-10-05").dueDay == DayKey(year: 2026, month: 10, day: 5))
        #expect(parse("Report on 10/5").dueDay == DayKey(year: 2026, month: 10, day: 5))
        let british = NaturalLanguageParser(calendar: testCalendar, locale: Locale(identifier: "en_GB"))
        #expect(british.parse("Report on 10/5", now: now).dueDay == DayKey(year: 2027, month: 5, day: 10))
        #expect(british.parse("Report 5/10/2026", now: now).dueDay == DayKey(year: 2026, month: 10, day: 5))
    }

    @Test func relativeTime() {
        let inTwoHours = parse("Check deploy in 2 hours")
        #expect(inTwoHours == ParsedInput(title: "Check deploy", dueDay: day(0), dueMinutes: 13 * 60))
        #expect(parse("Tea in 30 minutes").dueMinutes == 11 * 60 + 30)
        #expect(parse("Tea in an hour").dueMinutes == 12 * 60)
        let late = parser.parse("Sleep in 2 hours", now: date(2026, 9, 28, 23, 30))
        #expect(late.dueDay == day(1))
        #expect(late.dueMinutes == 90)
    }

    // MARK: Combinations and positions

    @Test func dateAndTimeInEitherOrder() {
        let expected = ParsedInput(title: "Standup", dueDay: day(4), dueMinutes: 15 * 60 + 30)
        #expect(parse("Standup at 3:30pm on Friday") == expected)
        #expect(parse("Standup Friday 3:30pm") == expected)
        #expect(parse("Standup friday at 3:30 pm") == expected)
    }

    @Test func phrasesAtStart() {
        #expect(parse("Tomorrow call Alex") == ParsedInput(title: "call Alex", dueDay: day(1)))
        #expect(parse("tomorrow 3pm call Alex") == ParsedInput(title: "call Alex", dueDay: day(1), dueMinutes: 15 * 60))
        #expect(parse("Every day stretch").recurrence == .daily)
    }

    @Test func midSentencePhrasesAreIgnored() {
        #expect(parse("Move tomorrow meeting to Oct 3").title == "Move tomorrow meeting to")
        #expect(parse("Move tomorrow meeting to Oct 3").dueDay == DayKey(year: 2026, month: 10, day: 3))
    }

    @Test func trailingPunctuationIsCleaned() {
        #expect(parse("Call Alex, tomorrow.").title == "Call Alex")
        #expect(parse("Call Alex - tomorrow").title == "Call Alex")
    }

    // MARK: Recurrence

    @Test(arguments: [
        ("Stretch every day", Recurrence.daily, 0),
        ("Stretch daily", Recurrence.daily, 0),
        ("Stretch every other day", Recurrence(frequency: .daily, interval: 2), 0),
        ("Stretch every 3 days", Recurrence(frequency: .daily, interval: 3), 0),
        ("Stretch every weekday", Recurrence.weekdaysOnly, 0),
        ("Stretch weekdays", Recurrence.weekdaysOnly, 0),
        ("Stretch every Tuesday", Recurrence(frequency: .weekly, weekdays: [3]), 1),
        ("Stretch every tue and thu", Recurrence(frequency: .weekly, weekdays: [3, 5]), 1),
        ("Stretch every other Friday", Recurrence(frequency: .weekly, interval: 2, weekdays: [6]), 4),
        ("Stretch every week", Recurrence(frequency: .weekly, weekdays: [2]), 0),
        ("Stretch weekly", Recurrence(frequency: .weekly, weekdays: [2]), 0),
        ("Stretch every 2 weeks on wed", Recurrence(frequency: .weekly, interval: 2, weekdays: [4]), 2),
        ("Rent every month on the 1st", Recurrence(frequency: .monthly, monthDay: 1), 3),
        ("Rent monthly on the 1st", Recurrence(frequency: .monthly, monthDay: 1), 3),
        ("Rent every 1st", Recurrence(frequency: .monthly, monthDay: 1), 3),
        ("Rent monthly", Recurrence(frequency: .monthly, monthDay: 28), 0),
        ("Sync every 2nd Tuesday", Recurrence(frequency: .monthly, ordinal: 2, ordinalWeekday: 3), 15),
        ("Sync every last friday of the month", Recurrence(frequency: .monthly, ordinal: -1, ordinalWeekday: 6), 32), // Sep's last Friday (25th) has passed
    ])
    func recurrence(_ text: String, _ expected: Recurrence, _ firstOffset: Int) {
        let result = parse(text)
        #expect(result.recurrence == expected, "\(text)")
        #expect(result.dueDay == day(firstOffset), "\(text)")
        #expect(!result.title.lowercased().contains("every"), "\(text)")
    }

    @Test func specRecurrenceExamples() {
        let weekdays = parse("Check email every weekday at 9 AM")
        #expect(weekdays.recurrence == .weekdaysOnly)
        #expect(weekdays.dueMinutes == 9 * 60)
        #expect(weekdays.dueDay == day(1)) // 9 AM today has passed

        let second = parse("Planning every 2nd Tuesday at 12 PM")
        #expect(second.title == "Planning")
        #expect(second.recurrence == Recurrence(frequency: .monthly, ordinal: 2, ordinalWeekday: 3))
        #expect(second.dueMinutes == 12 * 60)
        #expect(second.dueDay == DayKey(year: 2026, month: 10, day: 13))
    }

    @Test func recurrenceWithExplicitStartDate() {
        // An explicit date sets the first occurrence; "weekly" takes its weekday (Wednesday).
        let result = parse("Report weekly Oct 7")
        #expect(result.dueDay == DayKey(year: 2026, month: 10, day: 7))
        #expect(result.recurrence == Recurrence(frequency: .weekly, weekdays: [4]))
    }
}

@Suite struct RecurrenceTests {
    let monday = DayKey(year: 2026, month: 9, day: 28)

    func d(_ y: Int, _ m: Int, _ day: Int) -> DayKey { DayKey(year: y, month: m, day: day) }

    @Test func dailyInterval() {
        let rule = Recurrence(frequency: .daily, interval: 3)
        #expect(rule.occurrence(after: monday, calendar: testCalendar) == d(2026, 10, 1))
    }

    @Test func weeklyMultipleDays() {
        let rule = Recurrence(frequency: .weekly, weekdays: [3, 5]) // Tue, Thu
        #expect(rule.firstOccurrence(onOrAfter: monday, calendar: testCalendar) == d(2026, 9, 29))
        #expect(rule.occurrence(after: d(2026, 9, 29), calendar: testCalendar) == d(2026, 10, 1))
        #expect(rule.occurrence(after: d(2026, 10, 1), calendar: testCalendar) == d(2026, 10, 6))
    }

    @Test func biweeklySkipsAWeek() {
        let rule = Recurrence(frequency: .weekly, interval: 2, weekdays: [3, 5])
        #expect(rule.occurrence(after: d(2026, 9, 29), calendar: testCalendar) == d(2026, 10, 1))
        #expect(rule.occurrence(after: d(2026, 10, 1), calendar: testCalendar) == d(2026, 10, 13))
    }

    @Test func weekdaysRollOverWeekend() {
        #expect(Recurrence.weekdaysOnly.occurrence(after: d(2026, 10, 2), calendar: testCalendar) == d(2026, 10, 5))
    }

    @Test func sundayIsEndOfWeek() {
        let rule = Recurrence(frequency: .weekly, interval: 2, weekdays: [1, 2]) // Sun, Mon
        #expect(rule.occurrence(after: monday, calendar: testCalendar) == d(2026, 10, 4)) // same week's Sunday
        #expect(rule.occurrence(after: d(2026, 10, 4), calendar: testCalendar) == d(2026, 10, 12))
    }

    @Test func monthlyClampsShortMonths() {
        let rule = Recurrence(frequency: .monthly, monthDay: 31)
        #expect(rule.occurrence(after: d(2026, 1, 31), calendar: testCalendar) == d(2026, 2, 28))
        #expect(rule.occurrence(after: d(2026, 2, 28), calendar: testCalendar) == d(2026, 3, 31))
        #expect(rule.occurrence(after: d(2027, 12, 31), calendar: testCalendar) == d(2028, 1, 31))
    }

    @Test func monthlyNthWeekday() {
        let secondTuesday = Recurrence(frequency: .monthly, ordinal: 2, ordinalWeekday: 3)
        #expect(secondTuesday.firstOccurrence(onOrAfter: monday, calendar: testCalendar) == d(2026, 10, 13))
        #expect(secondTuesday.occurrence(after: d(2026, 10, 13), calendar: testCalendar) == d(2026, 11, 10))
        let lastFriday = Recurrence(frequency: .monthly, ordinal: -1, ordinalWeekday: 6)
        #expect(lastFriday.occurrence(after: d(2026, 10, 30), calendar: testCalendar) == d(2026, 11, 27))
    }

    @Test func nextOccurrenceSkipsPastOnes() {
        // A daily task last due 5 days ago, completed today: next is today, not 4 days ago.
        let next = Recurrence.daily.nextOccurrence(after: d(2026, 9, 23), notBefore: monday, calendar: testCalendar)
        #expect(next == monday)
    }

    @Test func summaries() {
        let en = Locale(identifier: "en_US")
        #expect(Recurrence.daily.summary(calendar: testCalendar, locale: en) == "Every day")
        #expect(Recurrence.weekdaysOnly.summary(calendar: testCalendar, locale: en) == "Every weekday")
        #expect(Recurrence(frequency: .weekly, weekdays: [2]).summary(calendar: testCalendar, locale: en) == "Every Monday")
        #expect(Recurrence(frequency: .weekly, weekdays: [3, 5]).summary(calendar: testCalendar, locale: en) == "Every Tue, Thu")
        #expect(Recurrence(frequency: .weekly, interval: 2, weekdays: [6]).summary(calendar: testCalendar, locale: en) == "Every other Friday")
        #expect(Recurrence(frequency: .monthly, monthDay: 1).summary(calendar: testCalendar, locale: en) == "Monthly on the 1st")
        #expect(Recurrence(frequency: .monthly, ordinal: 2, ordinalWeekday: 3).summary(calendar: testCalendar, locale: en) == "2nd Tuesday of every month")
        #expect(Recurrence(frequency: .monthly, ordinal: -1, ordinalWeekday: 6).summary(calendar: testCalendar, locale: en) == "Last Friday of every month")
    }
}

@Suite struct RecurringTaskTests {
    let today = DayKey(year: 2026, month: 9, day: 28) // Monday

    func weekly(dueOffset: Int) -> DailyTask {
        DailyTask(
            title: "Review metrics",
            notes: "Dashboard",
            dueDay: today.adding(days: dueOffset, calendar: testCalendar),
            dueMinutes: 10 * 60,
            reminder: .minutesBefore(15),
            priority: .high,
            recurrence: Recurrence(frequency: .weekly, weekdays: [2])
        )
    }

    @Test func completingOnTimeCreatesNextWeek() throws {
        let task = weekly(dueOffset: 0)
        let next = try #require(RecurringTasks.nextOccurrence(of: task, today: today, calendar: testCalendar))
        #expect(next.dueDay == today.adding(days: 7, calendar: testCalendar))
        #expect(next.id != task.id)
        #expect(next.seriesID == task.id)
        #expect(next.title == task.title && next.notes == task.notes && next.priority == .high)
        #expect(next.dueMinutes == 10 * 60 && next.reminder == .minutesBefore(15))
        #expect(next.completedAt == nil)
    }

    @Test func completingEarlyStillAdvancesFromDueDay() throws {
        // Due next Monday, done on Saturday: next is the Monday after.
        let task = weekly(dueOffset: 7)
        let next = try #require(RecurringTasks.nextOccurrence(of: task, today: today.adding(days: 5, calendar: testCalendar), calendar: testCalendar))
        #expect(next.dueDay == today.adding(days: 14, calendar: testCalendar))
    }

    @Test func overdueSkipsMissedOccurrences() throws {
        let daily = DailyTask(title: "Meds", dueDay: today.adding(days: -3, calendar: testCalendar), recurrence: .daily)
        let next = try #require(RecurringTasks.nextOccurrence(of: daily, today: today, calendar: testCalendar))
        #expect(next.dueDay == today)

        let weeklyTask = weekly(dueOffset: -14)
        #expect(RecurringTasks.nextOccurrence(of: weeklyTask, today: today, calendar: testCalendar)?.dueDay == today)
    }

    @Test func seriesIDIsKeptAcrossOccurrences() throws {
        let first = weekly(dueOffset: 0)
        let second = try #require(RecurringTasks.nextOccurrence(of: first, today: today, calendar: testCalendar))
        let third = try #require(RecurringTasks.nextOccurrence(of: second, today: today, calendar: testCalendar))
        #expect(third.seriesID == first.id)
    }

    @Test func notificationStateResets() throws {
        var task = weekly(dueOffset: 0)
        task.notificationsMuted = true
        task.snoozedUntil = date(2026, 9, 28, 10, 30)
        task.notificationsAcknowledgedAt = date(2026, 9, 28, 10, 5)
        let next = try #require(RecurringTasks.nextOccurrence(of: task, today: today, calendar: testCalendar))
        #expect(!next.notificationsMuted && next.snoozedUntil == nil && next.notificationsAcknowledgedAt == nil)
    }

    @Test func absoluteReminderMovesWithDueDate() throws {
        var task = weekly(dueOffset: 0)
        task.reminder = .at(date(2026, 9, 27, 18)) // Sunday evening before
        let next = try #require(RecurringTasks.nextOccurrence(of: task, today: today, calendar: testCalendar))
        #expect(next.reminder == .at(date(2026, 10, 4, 18)))
    }

    @Test func nonRecurringOrUndatedReturnsNil() {
        #expect(RecurringTasks.nextOccurrence(of: DailyTask(title: "Once", dueDay: today), today: today, calendar: testCalendar) == nil)
        #expect(RecurringTasks.nextOccurrence(of: DailyTask(title: "No day", recurrence: .daily), today: today, calendar: testCalendar) == nil)
    }

    @Test func storeCompletesAndCreatesAtomically() throws {
        let store = try TaskStore.inMemory()
        let task = weekly(dueOffset: 0)
        try store.save(task)
        let next = try #require(RecurringTasks.nextOccurrence(of: task, today: today, calendar: testCalendar))
        try store.complete(task, at: date(2026, 9, 28, 10, 5), creating: next)

        #expect(try store.activeTasks().map(\.id) == [next.id])
        let history = try store.completedTasks()
        #expect(history.map(\.id) == [task.id])
        #expect(history.first?.seriesID == task.id)
    }

    @Test func storeRollsBackWhenCreateFails() throws {
        let store = try TaskStore.inMemory()
        let task = weekly(dueOffset: 0)
        try store.save(task)
        let next = try #require(RecurringTasks.nextOccurrence(of: task, today: today, calendar: testCalendar))
        // Fail only the second write (the new occurrence), after the completion was written.
        try store.database.execute("""
            CREATE TRIGGER block_next BEFORE INSERT ON tasks WHEN NEW.id = '\(next.id.uuidString)'
            BEGIN SELECT RAISE(ABORT, 'blocked'); END;
            """)
        #expect(throws: (any Error).self) { try store.complete(task, creating: next) }
        #expect(try store.activeTasks().map(\.id) == [task.id])
        #expect(try store.completedTasks().isEmpty)
    }
}
