import Foundation
import Testing
@testable import DailyCore

@Suite struct SearchTests {
    func store(_ tasks: [DailyTask]) throws -> TaskStore {
        let store = try TaskStore.inMemory()
        try store.save(tasks)
        return store
    }

    @Test func matchesTitleNotesAndLinksCaseInsensitively() throws {
        let s = try store([
            DailyTask(title: "Fix PayFlow API"),
            DailyTask(title: "Docs", notes: "See the payflow integration guide"),
            DailyTask(title: "Ticket", links: [TaskLink(title: "Jira", url: URL(string: "https://jira.example.com/PAYFLOW-12")!)]),
            DailyTask(title: "Unrelated"),
        ])
        #expect(Set(try s.search("payflow").map(\.title)) == ["Fix PayFlow API", "Docs", "Ticket"])
        #expect(try s.search("https://jira").map(\.title) == ["Ticket"])
    }

    @Test func matchesStartsOfWordsOnly() throws {
        let s = try store([
            DailyTask(title: "Buy milk tomorrow"),
            DailyTask(title: "Monday report"),
            DailyTask(title: "Fix PayFlow API"),
            DailyTask(title: "Deploy v2-beta"),
        ])
        #expect(try s.search("mo").map(\.title) == ["Monday report"])
        #expect(try s.search("pay").map(\.title) == ["Fix PayFlow API"])
        #expect(try s.search("flow").isEmpty)
        #expect(try s.search("beta").map(\.title) == ["Deploy v2-beta"])
        #expect(try s.search("v2-b").map(\.title) == ["Deploy v2-beta"])
    }

    @Test func allWordsMustMatch() throws {
        let s = try store([DailyTask(title: "Call Alex about invoice"), DailyTask(title: "Call bank")])
        #expect(try s.search("call alex").map(\.title) == ["Call Alex about invoice"])
    }

    @Test func includesCompletedAfterActive() throws {
        let done = DailyTask(title: "Report v1", completedAt: Date(timeIntervalSinceReferenceDate: 1000))
        let active = DailyTask(title: "Report v2")
        let s = try store([done, active])
        #expect(try s.search("report").map(\.title) == ["Report v2", "Report v1"])
    }

    @Test func wildcardCharactersAreLiteral() throws {
        let s = try store([DailyTask(title: "Raise 5% budget"), DailyTask(title: "Raise 50 budget"), DailyTask(title: "snake_case"), DailyTask(title: "snakeXcase")])
        #expect(try s.search("5%").map(\.title) == ["Raise 5% budget"])
        #expect(try s.search("snake_").map(\.title) == ["snake_case"])
    }

    @Test func dayMatchesDueDate() throws {
        let day = DayKey(year: 2026, month: 10, day: 1)
        let s = try store([DailyTask(title: "Monthly report", dueDay: day), DailyTask(title: "Other", dueDay: DayKey(year: 2026, month: 10, day: 2))])
        #expect(try s.search("", day: day).map(\.title) == ["Monthly report"])
        #expect(try s.search("").isEmpty)
    }
}

@Suite struct BackupTests {
    let tasks = [
        DailyTask(
            title: "Review metrics", notes: "Dashboard", dueDay: DayKey(year: 2026, month: 10, day: 5), dueMinutes: 600,
            reminder: .at(Date(timeIntervalSince1970: 1_790_000_000)), priority: .high,
            links: [TaskLink(title: "Grafana", url: URL(string: "https://grafana.example.com/d/1")!)],
            recurrence: Recurrence(frequency: .weekly, weekdays: [2]),
            createdAt: Date(timeIntervalSince1970: 1_780_000_000)
        ),
        DailyTask(title: "Done thing", createdAt: Date(timeIntervalSince1970: 1_780_000_000), completedAt: Date(timeIntervalSince1970: 1_780_100_000)),
    ]

    @Test func roundTrips() throws {
        let backup = Backup(tasks: tasks, settings: ["briefing.enabled": .bool(false), "shortcut.quickAdd": .data(Data([1, 2, 3]))], exportedAt: Date(timeIntervalSince1970: 1_790_000_000))
        let decoded = try Backup.read(from: try backup.encoded())
        #expect(decoded.tasks == tasks)
        #expect(decoded.settings == backup.settings)
        #expect(decoded.formatVersion == 1)
    }

    @Test func jsonIsReadable() throws {
        let json = String(decoding: try Backup(tasks: tasks, settings: [:]).encoded(), as: UTF8.self)
        #expect(json.contains("\"title\" : \"Review metrics\""))
        #expect(json.contains("https://grafana.example.com/d/1"))
        #expect(json.contains("\"frequency\" : \"weekly\""))
    }

    @Test func fileName() {
        #expect(Backup.fileName(for: date(2026, 9, 28, 12), calendar: testCalendar) == "Nudge-Backup-2026-09-28.json")
    }

    @Test func rejectsGarbageAndNewerFormats() throws {
        #expect(throws: Backup.ImportError.self) { try Backup.read(from: Data("hello".utf8)) }
        #expect(throws: Backup.ImportError.self) { try Backup.read(from: Data(#"{"tasks": []}"#.utf8)) }

        var future = Backup(tasks: [], settings: [:])
        future.formatVersion = 99
        #expect(throws: Backup.ImportError.newerFormat(99)) { try Backup.read(from: try future.encoded()) }
    }

    @Test func rejectsTasksWithoutTitles() throws {
        let bad = Backup(tasks: [DailyTask(title: "  ")], settings: [:])
        #expect(throws: Backup.ImportError.invalidTasks(count: 1)) { try Backup.read(from: try bad.encoded()) }
    }

    @Test func mergeSkipsExistingIDs() {
        let backup = Backup(tasks: tasks, settings: [:])
        let plan = backup.mergePlan(existingIDs: [tasks[0].id])
        #expect(plan.newTasks == [tasks[1]])
        #expect(plan.existingCount == 1)
        #expect(plan.newActiveCount == 0 && plan.newCompletedCount == 1)
    }

    @Test func storeExportImportCycle() throws {
        let source = try TaskStore.inMemory()
        try source.save(tasks)
        let data = try Backup(tasks: try source.allTasks(), settings: [:]).encoded()

        let target = try TaskStore.inMemory()
        let existing = DailyTask(title: "Already here")
        try target.save(existing)
        let plan = try Backup.read(from: data).mergePlan(existingIDs: Set(try target.allTasks().map(\.id)))
        try target.save(plan.newTasks)
        #expect(try target.allTasks().count == 3)
        #expect(try target.completedTasks().map(\.title) == ["Done thing"])
    }

    @Test func clearHistoryKeepsActive() throws {
        let store = try TaskStore.inMemory()
        try store.save(tasks)
        try store.clearHistory()
        #expect(try store.allTasks().map(\.title) == ["Review metrics"])
    }
}

@Suite struct CategoryTests {
    let now = date(2026, 9, 28, 11)
    let parser = NaturalLanguageParser(calendar: testCalendar, locale: Locale(identifier: "en_US"))

    @Test func parsesTagAnywhere() {
        let end = parser.parse("Logo revisions 4pm #acme", now: now)
        #expect(end.title == "Logo revisions")
        #expect(end.categoryTag == "acme")
        #expect(end.dueMinutes == 16 * 60)

        let middle = parser.parse("Fix #work PayFlow API tomorrow", now: now)
        #expect(middle.title == "Fix PayFlow API")
        #expect(middle.categoryTag == "work")
        #expect(middle.dueDay == DayKey(year: 2026, month: 9, day: 29))

        #expect(parser.parse("#personal buy milk", now: now).title == "buy milk")
    }

    @Test func numericHashIsNotACategory() {
        #expect(parser.parse("Fix issue #123", now: now) == ParsedInput(title: "Fix issue #123"))
        #expect(parser.parse("Fix issue #123 #work", now: now).categoryTag == "work")
    }

    @Test func tagOnlyIsLiteral() {
        #expect(parser.parse("#work", now: now) == ParsedInput(title: "#work"))
    }

    @Test func firstTagWins() {
        let result = parser.parse("Call #work #personal", now: now)
        #expect(result.categoryTag == "work")
        #expect(result.title == "Call #personal")
    }

    @Test func trailingPrefix() {
        #expect(NaturalLanguageParser.trailingTagPrefix("Logo #ac") == "ac")
        #expect(NaturalLanguageParser.trailingTagPrefix("Logo #") == "")
        #expect(NaturalLanguageParser.trailingTagPrefix("Logo #ac ") == nil)
        #expect(NaturalLanguageParser.trailingTagPrefix("issue#12") == nil)
    }

    @Test func matchingIgnoresCaseAndSpacing() {
        let categories = [TaskCategory(name: "Personal Stuff", color: 0), TaskCategory(name: "Acme", color: 1)]
        #expect(TaskCategory.matching("personal_stuff", in: categories)?.name == "Personal Stuff")
        #expect(TaskCategory.matching("ACME", in: categories)?.name == "Acme")
        #expect(TaskCategory.matching("acm", in: categories) == nil)
        #expect(TaskCategory.completions(for: "ac", in: categories).map(\.name) == ["Acme"])
        #expect(TaskCategory.displayName(fromTag: "freelance_acme") == "Freelance acme")
    }

    @Test func storeFindOrCreateAndDelete() throws {
        let store = try TaskStore.inMemory()
        let work = try store.findOrCreateCategory(tag: "work")
        #expect(work.name == "Work")
        #expect(try store.findOrCreateCategory(tag: "WORK").id == work.id)
        let acme = try store.findOrCreateCategory(tag: "acme")
        #expect(acme.color != work.color)

        let task = DailyTask(title: "Invoice", categoryID: acme.id)
        try store.save(task)
        #expect(try store.task(id: task.id)?.categoryID == acme.id)

        try store.deleteCategory(id: acme.id)
        #expect(try store.task(id: task.id)?.categoryID == nil)
        #expect(try store.categories().map(\.name) == ["Work"])
    }

    @Test func duplicateNamesAreRejected() throws {
        let store = try TaskStore.inMemory()
        _ = try store.findOrCreateCategory(tag: "work")
        #expect(throws: (any Error).self) { try store.saveCategory(TaskCategory(name: "WORK", color: 2)) }
    }

    @Test func searchWithinCategory() throws {
        let store = try TaskStore.inMemory()
        let work = try store.findOrCreateCategory(tag: "work")
        try store.save([DailyTask(title: "Report", categoryID: work.id), DailyTask(title: "Report for home")])
        #expect(try store.search("report", category: work.id).map(\.title) == ["Report"])
        #expect(try store.search("", category: work.id).map(\.title) == ["Report"])
    }

    @Test func groupsFilter() {
        let work = UUID()
        var groups = TaskGroups()
        groups.today = [DailyTask(title: "A", categoryID: work), DailyTask(title: "B")]
        #expect(groups.filtered(by: work).today.map(\.title) == ["A"])
        #expect(groups.filtered(by: nil).today.count == 2)
    }

    @Test func backupMergesCategoriesByName() throws {
        let backupWork = TaskCategory(name: "Work", color: 3)
        let backupAcme = TaskCategory(name: "Acme", color: 4)
        let tasks = [DailyTask(title: "W", categoryID: backupWork.id), DailyTask(title: "A", categoryID: backupAcme.id)]
        let backup = try Backup.read(from: try Backup(tasks: tasks, categories: [backupWork, backupAcme], settings: [:]).encoded())

        let localWork = TaskCategory(name: "work", color: 0)
        let plan = backup.mergePlan(existingIDs: [], existingCategories: [localWork])
        #expect(plan.newCategories.map(\.name) == ["Acme"])
        #expect(plan.newTasks.first { $0.title == "W" }?.categoryID == localWork.id)
        #expect(plan.newTasks.first { $0.title == "A" }?.categoryID == backupAcme.id)
    }

    @Test func version2DatabaseMigrates() throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "cat-\(UUID().uuidString).sqlite")
        defer { try? FileManager.default.removeItem(at: url) }
        do {
            let store = try TaskStore.open(at: url)
            try store.save(DailyTask(title: "Before categories"))
            // Roll back to the v2 shape.
            try store.database.execute("DROP TABLE categories; ALTER TABLE tasks DROP COLUMN category_id; PRAGMA user_version = 2;")
        }
        let reopened = try TaskStore.open(at: url)
        #expect(try reopened.database.userVersion == 3)
        #expect(try reopened.activeTasks().map(\.title) == ["Before categories"])
        #expect(try reopened.categories().isEmpty)
    }
}

@Suite struct DateQueryTests {
    let parser = NaturalLanguageParser(calendar: testCalendar, locale: Locale(identifier: "en_US"))
    let now = date(2026, 9, 28, 11)

    @Test func recognizesDateOnlyQueries() {
        #expect(parser.day(inQuery: "tomorrow", now: now) == DayKey(year: 2026, month: 9, day: 29))
        #expect(parser.day(inQuery: "oct 1", now: now) == DayKey(year: 2026, month: 10, day: 1))
        #expect(parser.day(inQuery: "friday", now: now) == DayKey(year: 2026, month: 10, day: 2))
    }

    @Test func ignoresOtherQueries() {
        #expect(parser.day(inQuery: "payflow", now: now) == nil)
        #expect(parser.day(inQuery: "report tomorrow", now: now) == nil)
        #expect(parser.day(inQuery: "3pm", now: now) == nil)
    }
}

@Suite struct LegacyFolderTests {
    func tempBase() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: "legacy-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test func movesOldFolderWithData() throws {
        let base = try tempBase()
        defer { try? FileManager.default.removeItem(at: base) }
        let old = base.appending(path: "MacDailyUtility")
        try FileManager.default.createDirectory(at: old, withIntermediateDirectories: true)
        try Data("db".utf8).write(to: old.appending(path: "tasks.sqlite"))

        #expect(try TaskStore.migrateLegacyFolder(in: base))
        #expect(try Data(contentsOf: base.appending(path: "Nudge/tasks.sqlite")) == Data("db".utf8))
        #expect(!FileManager.default.fileExists(atPath: old.path))
    }

    @Test func neverOverwritesExistingNewFolder() throws {
        let base = try tempBase()
        defer { try? FileManager.default.removeItem(at: base) }
        for (folder, content) in [("MacDailyUtility", "old"), ("Nudge", "new")] {
            let dir = base.appending(path: folder)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try Data(content.utf8).write(to: dir.appending(path: "tasks.sqlite"))
        }
        #expect(try !TaskStore.migrateLegacyFolder(in: base))
        #expect(try Data(contentsOf: base.appending(path: "Nudge/tasks.sqlite")) == Data("new".utf8))
    }

    @Test func nothingToMove() throws {
        let base = try tempBase()
        defer { try? FileManager.default.removeItem(at: base) }
        #expect(try !TaskStore.migrateLegacyFolder(in: base))
    }
}
