import Foundation
import Testing
@testable import DailyCore

@Suite struct TaskStoreTests {
    @Test func roundTripsEveryField() throws {
        let store = try TaskStore.inMemory()
        let task = DailyTask(
            title: "Fix PayFlow API",
            notes: "Check encrypted URL implementation.\nConfirm ID validation.",
            dueDay: DayKey(year: 2026, month: 9, day: 29),
            dueMinutes: 15 * 60,
            reminder: .minutesBefore(30),
            priority: .high,
            links: [TaskLink(title: "Jira ticket", url: URL(string: "https://example.com/JIRA-1")!)],
            recurrence: Recurrence(frequency: .monthly, ordinal: 2, ordinalWeekday: 3),
            notificationsMuted: true,
            snoozedUntil: Date(timeIntervalSinceReferenceDate: 812_000_000.25),
            seriesID: UUID(),
            createdAt: Date(timeIntervalSinceReferenceDate: 812_345_678.123456)
        )
        try store.save(task)
        #expect(try store.task(id: task.id) == task)
    }

    @Test func absoluteReminderRoundTrips() throws {
        let store = try TaskStore.inMemory()
        let task = DailyTask(title: "Call Alex", reminder: .at(Date(timeIntervalSinceReferenceDate: 800_000_000.5)))
        try store.save(task)
        #expect(try store.task(id: task.id)?.reminder == task.reminder)
    }

    @Test func saveUpdatesExistingTask() throws {
        let store = try TaskStore.inMemory()
        var task = DailyTask(title: "Draft")
        try store.save(task)
        task.title = "Final"
        task.priority = .critical
        try store.save(task)
        #expect(try store.activeTasks() == [task])
    }

    @Test func completeMovesTaskToHistory() throws {
        let store = try TaskStore.inMemory()
        let task = DailyTask(title: "Product meeting")
        let other = DailyTask(title: "Check metrics")
        try store.save(task)
        try store.save(other)

        let completedAt = Date(timeIntervalSinceReferenceDate: 810_000_000)
        try store.complete(id: task.id, at: completedAt)

        #expect(try store.activeTasks().map(\.id) == [other.id])
        let history = try store.completedTasks()
        #expect(history.count == 1)
        #expect(history[0].completedAt == completedAt)
        #expect(history[0].title == "Product meeting")
    }

    @Test func completedTasksSinceFiltersAndSortsNewestFirst() throws {
        let store = try TaskStore.inMemory()
        let tasks = (0..<3).map { DailyTask(title: "T\($0)") }
        for (i, task) in tasks.enumerated() {
            try store.save(task)
            try store.complete(id: task.id, at: Date(timeIntervalSinceReferenceDate: Double(i) * 1000))
        }
        let recent = try store.completedTasks(since: Date(timeIntervalSinceReferenceDate: 1000))
        #expect(recent.map(\.title) == ["T2", "T1"])
    }

    @Test func reopenReturnsTaskToActiveList() throws {
        let store = try TaskStore.inMemory()
        let task = DailyTask(title: "Oops")
        try store.save(task)
        try store.complete(id: task.id)
        try store.reopen(id: task.id)
        #expect(try store.activeTasks().map(\.id) == [task.id])
        #expect(try store.completedTasks().isEmpty)
    }

    @Test func deleteRemovesTask() throws {
        let store = try TaskStore.inMemory()
        let task = DailyTask(title: "Gone")
        try store.save(task)
        try store.delete(id: task.id)
        #expect(try store.task(id: task.id) == nil)
    }

    @Test func dataPersistsAcrossReopen() throws {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "DailyCoreTests-\(UUID().uuidString)")
            .appending(path: "tasks.sqlite")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        let active = DailyTask(title: "Still here", dueDay: DayKey(year: 2026, month: 10, day: 1))
        let done = DailyTask(title: "Done")
        do {
            let store = try TaskStore.open(at: url)
            try store.save(active)
            try store.save(done)
            try store.complete(id: done.id)
        }

        let reopened = try TaskStore.open(at: url)
        #expect(try reopened.activeTasks() == [active])
        #expect(try reopened.completedTasks().map(\.id) == [done.id])
        #expect(try reopened.database.userVersion == 3)
    }

    @Test func handlesQuotesAndUnicodeInText() throws {
        let store = try TaskStore.inMemory()
        let task = DailyTask(title: "Robert'); DROP TABLE tasks;-- 🎉", notes: "“quotes” & ümlauts")
        try store.save(task)
        #expect(try store.task(id: task.id) == task)
    }

    @Test func unreadableRowDoesNotHideOtherTasks() throws {
        let store = try TaskStore.inMemory()
        let good = DailyTask(title: "Good")
        try store.save(good)
        try store.database.run(
            "INSERT INTO tasks (id, title, created_at, updated_at) VALUES ('not-a-uuid', 'Bad', 0, 0)"
        )
        #expect(try store.activeTasks().map(\.id) == [good.id])
    }

    @Test func migratesVersion1Database() throws {
        let db = try SQLiteDatabase(path: ":memory:")
        // The exact v1 schema as shipped in Phase 2, with one existing task.
        try db.execute("""
            CREATE TABLE tasks (
                id TEXT PRIMARY KEY NOT NULL, title TEXT NOT NULL, notes TEXT NOT NULL DEFAULT '',
                due_day TEXT, due_minutes INTEGER, reminder TEXT, priority INTEGER NOT NULL DEFAULT 0,
                links TEXT NOT NULL DEFAULT '[]', recurrence TEXT, notifications_muted INTEGER NOT NULL DEFAULT 0,
                series_id TEXT, created_at REAL NOT NULL, updated_at REAL NOT NULL, completed_at REAL
            );
            CREATE INDEX tasks_active ON tasks(completed_at, due_day);
            INSERT INTO tasks (id, title, due_day, created_at, updated_at)
                VALUES ('0A000000-0000-4000-8000-000000000001', 'Old task', '2026-09-28', 0, 0);
            PRAGMA user_version = 1;
            """)
        let store = try TaskStore(database: db)
        #expect(try db.userVersion == 3)
        let tasks = try store.activeTasks()
        #expect(tasks.map(\.title) == ["Old task"])
        #expect(tasks.first?.snoozedUntil == nil)
    }
}
