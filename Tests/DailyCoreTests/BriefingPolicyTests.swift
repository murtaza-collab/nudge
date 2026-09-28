import Foundation
import Testing
@testable import DailyCore

@Suite struct BriefingPolicyTests {
    let today = DayKey(year: 2026, month: 9, day: 28)
    let yesterday = DayKey(year: 2026, month: 9, day: 27)

    func show(
        _ trigger: BriefingTrigger,
        _ preferences: BriefingPreferences = BriefingPreferences(),
        lastShown: DayKey? = nil,
        hasTasks: Bool = true,
        weekend: Bool = false
    ) -> Bool {
        BriefingPolicy.shouldShow(trigger, preferences: preferences, today: today, lastShown: lastShown, hasTasks: hasTasks, isWeekend: weekend)
    }

    @Test func defaultsShowOnFirstLaunchOrWakeOfTheDay() {
        #expect(show(.launch, lastShown: yesterday))
        #expect(show(.wake, lastShown: yesterday))
        #expect(show(.scheduled, lastShown: nil))
    }

    @Test func oncePerDay() {
        #expect(!show(.wake, lastShown: today))
        #expect(!show(.launch, lastShown: today))
        var every = BriefingPreferences()
        every.oncePerDay = false
        #expect(show(.wake, every, lastShown: today))
    }

    @Test func onlyIfTasks() {
        #expect(!show(.launch, hasTasks: false))
        var always = BriefingPreferences()
        always.onlyIfTasks = false
        #expect(show(.launch, always, hasTasks: false))
    }

    @Test func triggerToggles() {
        var prefs = BriefingPreferences()
        prefs.onWake = false
        #expect(!show(.wake, prefs))
        #expect(show(.launch, prefs))
        prefs.onLaunch = false
        #expect(!show(.launch, prefs))
        #expect(show(.scheduled, prefs))
    }

    @Test func weekends() {
        #expect(show(.launch, weekend: true))
        var weekdaysOnly = BriefingPreferences()
        weekdaysOnly.skipWeekends = true
        #expect(!show(.launch, weekdaysOnly, weekend: true))
        #expect(show(.launch, weekdaysOnly, weekend: false))
    }

    @Test func disabledStillAllowsManual() {
        let off = BriefingPreferences(enabled: false)
        #expect(!show(.launch, off))
        #expect(!show(.scheduled, off))
        #expect(show(.manual, off, lastShown: today, hasTasks: false, weekend: true))
    }

    @Test func greetings() {
        #expect(BriefingPolicy.greeting(hour: 7) == "Good morning")
        #expect(BriefingPolicy.greeting(hour: 13) == "Good afternoon")
        #expect(BriefingPolicy.greeting(hour: 20) == "Good evening")
        #expect(BriefingPolicy.greeting(hour: 2) == "Good evening")
    }
}
