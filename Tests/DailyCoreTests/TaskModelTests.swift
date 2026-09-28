import Foundation
import Testing
@testable import DailyCore

/// Fixed calendar so tests don't depend on the machine's time zone.
let testCalendar: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Asia/Karachi")!
    return calendar
}()

func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 0, _ min: Int = 0) -> Date {
    testCalendar.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
}

@Suite struct DayKeyTests {
    @Test func parsesAndFormats() {
        let key = DayKey(string: "2026-09-28")
        #expect(key == DayKey(year: 2026, month: 9, day: 28))
        #expect(key?.description == "2026-09-28")
        #expect(DayKey(string: "2026-13-01") == nil)
        #expect(DayKey(string: "tomorrow") == nil)
    }

    @Test func addsDaysAcrossMonthAndYear() {
        #expect(DayKey(year: 2026, month: 9, day: 30).adding(days: 1, calendar: testCalendar) == DayKey(year: 2026, month: 10, day: 1))
        #expect(DayKey(year: 2026, month: 12, day: 31).adding(days: 1, calendar: testCalendar) == DayKey(year: 2027, month: 1, day: 1))
    }

    @Test func ordersChronologically() {
        #expect(DayKey(year: 2026, month: 9, day: 30) < DayKey(year: 2026, month: 10, day: 1))
    }
}

@Suite struct ReminderTests {
    let task = DailyTask(title: "Call", dueDay: DayKey(year: 2026, month: 10, day: 2), dueMinutes: 16 * 60)

    @Test func dueDateCombinesDayAndTime() {
        #expect(task.dueDate(calendar: testCalendar) == date(2026, 10, 2, 16))
    }

    @Test func reminderOffsets() {
        var t = task
        t.reminder = .atDueTime
        #expect(t.reminderDate(calendar: testCalendar) == date(2026, 10, 2, 16))
        t.reminder = .minutesBefore(30)
        #expect(t.reminderDate(calendar: testCalendar) == date(2026, 10, 2, 15, 30))
    }

    @Test func absoluteReminderIsIndependentOfDueDate() {
        var t = task
        t.reminder = .at(date(2026, 10, 1, 10))
        #expect(t.reminderDate(calendar: testCalendar) == date(2026, 10, 1, 10))
    }

    @Test func relativeReminderNeedsDueTime() {
        var t = DailyTask(title: "Someday", dueDay: DayKey(year: 2026, month: 10, day: 2))
        t.reminder = .minutesBefore(15)
        #expect(t.reminderDate(calendar: testCalendar) == nil)
    }

    @Test func reminderJSONShapeIsStable() throws {
        let data = try JSONEncoder().encode(Reminder.minutesBefore(10))
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        #expect(object?["kind"] as? String == "before")
        #expect(object?["minutes"] as? Int == 10)
    }
}
