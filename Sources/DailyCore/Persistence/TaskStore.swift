import Foundation
import os

/// Reads and writes tasks. Completed tasks stay in the same table as history.
public final class TaskStore: @unchecked Sendable {
    public let database: SQLiteDatabase

    private static let log = Logger(subsystem: "com.murtazacollab.nudge", category: "TaskStore")

    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.withoutEscapingSlashes] // keeps URLs searchable as typed
        return encoder
    }()
    private let decoder = JSONDecoder()

    public init(database: SQLiteDatabase) throws {
        self.database = database
        try migrate()
    }

    /// Opens the store at `url`, creating parent directories as needed.
    public static func open(at url: URL) throws -> TaskStore {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        return try TaskStore(database: SQLiteDatabase(path: url.path))
    }

    public static func inMemory() throws -> TaskStore {
        try TaskStore(database: SQLiteDatabase(path: ":memory:"))
    }

    /// ~/Library/Application Support/Nudge/tasks.sqlite
    public static var defaultURL: URL {
        URL.applicationSupportDirectory
            .appending(path: "Nudge", directoryHint: .isDirectory)
            .appending(path: "tasks.sqlite")
    }

    /// Moves data from the app's former name ("MacDailyUtility") to the current folder.
    /// Only runs when the new folder doesn't exist yet, so it can never overwrite data.
    /// Returns true if something was moved.
    @discardableResult
    public static func migrateLegacyFolder(in base: URL = .applicationSupportDirectory) throws -> Bool {
        let fileManager = FileManager.default
        let legacy = base.appending(path: "MacDailyUtility", directoryHint: .isDirectory)
        let current = base.appending(path: "Nudge", directoryHint: .isDirectory)
        guard fileManager.fileExists(atPath: legacy.path), !fileManager.fileExists(atPath: current.path) else { return false }
        try fileManager.moveItem(at: legacy, to: current)
        return true
    }

    // MARK: - Schema

    private func migrate() throws {
        let version = try database.userVersion
        if version < 1 {
            try database.transaction {
                try database.execute("""
                    CREATE TABLE tasks (
                        id TEXT PRIMARY KEY NOT NULL,
                        title TEXT NOT NULL,
                        notes TEXT NOT NULL DEFAULT '',
                        due_day TEXT,
                        due_minutes INTEGER,
                        reminder TEXT,
                        priority INTEGER NOT NULL DEFAULT 0,
                        links TEXT NOT NULL DEFAULT '[]',
                        recurrence TEXT,
                        notifications_muted INTEGER NOT NULL DEFAULT 0,
                        series_id TEXT,
                        created_at REAL NOT NULL,
                        updated_at REAL NOT NULL,
                        completed_at REAL
                    );
                    CREATE INDEX tasks_active ON tasks(completed_at, due_day);
                    """)
                try database.setUserVersion(1)
            }
        }
        if version < 2 {
            try database.transaction {
                try database.execute("""
                    ALTER TABLE tasks ADD COLUMN snoozed_until REAL;
                    ALTER TABLE tasks ADD COLUMN acknowledged_at REAL;
                    """)
                try database.setUserVersion(2)
            }
        }
        if version < 3 {
            try database.transaction {
                try database.execute("""
                    CREATE TABLE categories (
                        id TEXT PRIMARY KEY NOT NULL,
                        name TEXT NOT NULL UNIQUE COLLATE NOCASE,
                        color INTEGER NOT NULL DEFAULT 0,
                        created_at REAL NOT NULL
                    );
                    ALTER TABLE tasks ADD COLUMN category_id TEXT;
                    """)
                try database.setUserVersion(3)
            }
        }
    }

    // MARK: - Reads

    public func task(id: UUID) throws -> DailyTask? {
        try database.query("SELECT * FROM tasks WHERE id = ?", [.text(id.uuidString)]).first.map(decodeTask)
    }

    public func activeTasks() throws -> [DailyTask] {
        try decodeRows(database.query("SELECT * FROM tasks WHERE completed_at IS NULL ORDER BY created_at"))
    }

    /// Completed tasks, most recent first, optionally limited to those completed on or after `since`.
    public func completedTasks(since: Date? = nil) throws -> [DailyTask] {
        if let since {
            return try decodeRows(database.query(
                "SELECT * FROM tasks WHERE completed_at >= ? ORDER BY completed_at DESC",
                [.real(since.timeIntervalSinceReferenceDate)]
            ))
        }
        return try decodeRows(database.query("SELECT * FROM tasks WHERE completed_at IS NOT NULL ORDER BY completed_at DESC"))
    }

    /// Tasks where every word of `query` starts a word in the title, description or links
    /// ("mo" finds "Monday", not "tomorrow"), plus (when given) tasks due on `day`.
    /// A query word containing punctuation ("https://jira") matches anywhere.
    /// Active tasks first, then completed, newest first.
    public func search(_ query: String, day: DayKey? = nil, category: UUID? = nil, limit: Int = 50) throws -> [DailyTask] {
        let words = query.split(whereSeparator: \.isWhitespace).map(String.init)
        var conditions: [String] = []
        var bindings: [SQLValue] = []
        if !words.isEmpty {
            let perWord = "(title LIKE ? ESCAPE '\\' OR notes LIKE ? ESCAPE '\\' OR links LIKE ? ESCAPE '\\')"
            let textMatch = words.map { _ in perWord }.joined(separator: " AND ")
            conditions.append("(\(textMatch))")
            for word in words {
                let pattern = "%" + Self.escapeLike(word) + "%"
                bindings += [.text(pattern), .text(pattern), .text(pattern)]
            }
        }
        if let day {
            conditions.append("due_day = ?")
            bindings.append(.text(day.description))
        }
        var whereClause = conditions.joined(separator: " OR ")
        if let category {
            // A category narrows the results; on its own it lists the whole category.
            whereClause = whereClause.isEmpty ? "category_id = ?" : "(\(whereClause)) AND category_id = ?"
            bindings.append(.text(category.uuidString))
        }
        guard !whereClause.isEmpty else { return [] }
        // SQL narrows by substring; word-start matching is checked on the candidates.
        let candidates = try decodeRows(database.query("""
            SELECT * FROM tasks WHERE \(whereClause)
            ORDER BY completed_at IS NOT NULL, completed_at DESC, due_day IS NULL, due_day, created_at
            """, bindings))
        let matches = candidates.filter { task in
            (day != nil && task.dueDay == day) || Self.matchesWordStarts(task, words: words)
        }
        return Array(matches.prefix(max(limit, 1)))
    }

    static func matchesWordStarts(_ task: DailyTask, words: [String]) -> Bool {
        guard !words.isEmpty else { return true }
        let text = ([task.title, task.notes] + task.links.flatMap { [$0.title, $0.url.absoluteString] }).joined(separator: " ")
        let lowered = text.lowercased()
        let tokens = lowered.split { !$0.isLetter && !$0.isNumber }
        return words.allSatisfy { word in
            let query = word.lowercased()
            if query.contains(where: { !$0.isLetter && !$0.isNumber }) { return lowered.contains(query) }
            return tokens.contains { $0.hasPrefix(query) }
        }
    }

    private static func escapeLike(_ text: String) -> String {
        text.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "%", with: "\\%")
            .replacingOccurrences(of: "_", with: "\\_")
    }

    /// Every task, active and completed (for export).
    public func allTasks() throws -> [DailyTask] {
        try decodeRows(database.query("SELECT * FROM tasks ORDER BY created_at"))
    }

    // MARK: - Writes

    // MARK: - Categories

    public func categories() throws -> [TaskCategory] {
        try database.query("SELECT * FROM categories ORDER BY name COLLATE NOCASE").compactMap { row in
            guard let id = row.string("id").flatMap(UUID.init(uuidString:)), let name = row.string("name") else { return nil }
            return TaskCategory(
                id: id, name: name, color: row.int("color") ?? 0,
                createdAt: Date(timeIntervalSinceReferenceDate: row.double("created_at") ?? 0)
            )
        }
    }

    /// Inserts or updates a category. Names are unique ignoring case; a clash throws.
    public func saveCategory(_ category: TaskCategory) throws {
        try database.run("""
            INSERT INTO categories (id, name, color, created_at) VALUES (?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET name = excluded.name, color = excluded.color
            """, [
                .text(category.id.uuidString),
                .text(category.name.trimmingCharacters(in: .whitespacesAndNewlines)),
                .integer(Int64(category.color)),
                .real(category.createdAt.timeIntervalSinceReferenceDate),
            ])
    }

    /// The existing category matching `tag` (ignoring case and spacing), or a new one
    /// named from it with the next palette color.
    public func findOrCreateCategory(tag: String) throws -> TaskCategory {
        let existing = try categories()
        if let match = TaskCategory.matching(tag, in: existing) { return match }
        let category = TaskCategory(name: TaskCategory.displayName(fromTag: tag), color: existing.count % TaskCategory.paletteSize)
        try saveCategory(category)
        return category
    }

    /// Deletes a category; its tasks keep existing without one.
    public func deleteCategory(id: UUID) throws {
        try database.transaction {
            try database.run("UPDATE tasks SET category_id = NULL WHERE category_id = ?", [.text(id.uuidString)])
            try database.run("DELETE FROM categories WHERE id = ?", [.text(id.uuidString)])
        }
    }

    /// Deletes completed tasks. Active tasks are untouched.
    public func clearHistory() throws {
        try database.run("DELETE FROM tasks WHERE completed_at IS NOT NULL")
    }

    /// Deletes every task.
    public func deleteAll() throws {
        try database.transaction {
            try database.run("DELETE FROM tasks")
            try database.run("DELETE FROM categories")
        }
    }

    /// Inserts or replaces many tasks in one transaction (for import).
    public func save(_ tasks: [DailyTask]) throws {
        try database.transaction {
            for task in tasks { try save(task) }
        }
    }

    /// Inserts the task, or replaces the stored copy with the same id.
    public func save(_ task: DailyTask) throws {
        try database.run("""
            INSERT INTO tasks (id, title, notes, due_day, due_minutes, reminder, priority, links, recurrence, category_id,
                               notifications_muted, snoozed_until, acknowledged_at, series_id,
                               created_at, updated_at, completed_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET
                title = excluded.title, notes = excluded.notes, due_day = excluded.due_day,
                due_minutes = excluded.due_minutes, reminder = excluded.reminder,
                priority = excluded.priority, links = excluded.links, recurrence = excluded.recurrence,
                category_id = excluded.category_id,
                notifications_muted = excluded.notifications_muted, snoozed_until = excluded.snoozed_until,
                acknowledged_at = excluded.acknowledged_at, series_id = excluded.series_id,
                created_at = excluded.created_at, updated_at = excluded.updated_at,
                completed_at = excluded.completed_at
            """, try encodeTask(task))
    }

    public func complete(id: UUID, at date: Date = Date()) throws {
        let time = SQLValue.real(date.timeIntervalSinceReferenceDate)
        try database.run("UPDATE tasks SET completed_at = ?, updated_at = ? WHERE id = ?", [time, time, .text(id.uuidString)])
    }

    /// Saves `completed` as done and inserts `next` (a recurring task's next occurrence)
    /// in one transaction, so a crash can't leave one without the other.
    public func complete(_ completed: DailyTask, at date: Date = Date(), creating next: DailyTask?) throws {
        var done = completed
        done.completedAt = date
        done.updatedAt = date
        if let next { done.seriesID = next.seriesID }
        try database.transaction {
            try save(done)
            if let next { try save(next) }
        }
    }

    /// Replaces `current` with `next` in one transaction (skipping a recurring occurrence).
    public func replace(_ current: DailyTask, with next: DailyTask) throws {
        try database.transaction {
            try delete(id: current.id)
            try save(next)
        }
    }

    /// Moves a completed task back to the active list.
    public func reopen(id: UUID, at date: Date = Date()) throws {
        try database.run(
            "UPDATE tasks SET completed_at = NULL, updated_at = ? WHERE id = ?",
            [.real(date.timeIntervalSinceReferenceDate), .text(id.uuidString)]
        )
    }

    public func delete(id: UUID) throws {
        try database.run("DELETE FROM tasks WHERE id = ?", [.text(id.uuidString)])
    }

    // MARK: - Row mapping

    /// Decodes rows, skipping (and logging) any that are unreadable so one damaged
    /// row can't hide every other task.
    private func decodeRows(_ rows: [SQLRow]) -> [DailyTask] {
        rows.compactMap { row in
            do {
                return try decodeTask(row)
            } catch {
                Self.log.error("Skipping unreadable task row \(row.string("id") ?? "?", privacy: .public): \(error, privacy: .public)")
                return nil
            }
        }
    }

    private func encodeTask(_ task: DailyTask) throws -> [SQLValue] {
        [
            .text(task.id.uuidString),
            .text(task.title),
            .text(task.notes),
            task.dueDay.map { .text($0.description) } ?? .null,
            task.dueMinutes.map { .integer(Int64($0)) } ?? .null,
            try task.reminder.map { .text(try json($0)) } ?? .null,
            .integer(Int64(task.priority.rawValue)),
            .text(try json(task.links)),
            try task.recurrence.map { .text(try json($0)) } ?? .null,
            task.categoryID.map { .text($0.uuidString) } ?? .null,
            .integer(task.notificationsMuted ? 1 : 0),
            task.snoozedUntil.map { .real($0.timeIntervalSinceReferenceDate) } ?? .null,
            task.notificationsAcknowledgedAt.map { .real($0.timeIntervalSinceReferenceDate) } ?? .null,
            task.seriesID.map { .text($0.uuidString) } ?? .null,
            .real(task.createdAt.timeIntervalSinceReferenceDate),
            .real(task.updatedAt.timeIntervalSinceReferenceDate),
            task.completedAt.map { .real($0.timeIntervalSinceReferenceDate) } ?? .null,
        ]
    }

    private func decodeTask(_ row: SQLRow) throws -> DailyTask {
        guard let idString = row.string("id"), let id = UUID(uuidString: idString) else {
            throw SQLiteError(code: -1, message: "Task row has invalid id")
        }
        return DailyTask(
            id: id,
            title: row.string("title") ?? "",
            notes: row.string("notes") ?? "",
            dueDay: row.string("due_day").flatMap(DayKey.init(string:)),
            dueMinutes: row.int("due_minutes"),
            reminder: try row.string("reminder").map { try decoder.decode(Reminder.self, from: Data($0.utf8)) },
            priority: Priority(rawValue: row.int("priority") ?? 0) ?? .none,
            links: try row.string("links").map { try decoder.decode([TaskLink].self, from: Data($0.utf8)) } ?? [],
            recurrence: try row.string("recurrence").map { try decoder.decode(Recurrence.self, from: Data($0.utf8)) },
            categoryID: row.string("category_id").flatMap(UUID.init(uuidString:)),
            notificationsMuted: row.int("notifications_muted") == 1,
            snoozedUntil: row.double("snoozed_until").map(Date.init(timeIntervalSinceReferenceDate:)),
            notificationsAcknowledgedAt: row.double("acknowledged_at").map(Date.init(timeIntervalSinceReferenceDate:)),
            seriesID: row.string("series_id").flatMap(UUID.init(uuidString:)),
            createdAt: Date(timeIntervalSinceReferenceDate: row.double("created_at") ?? 0),
            updatedAt: Date(timeIntervalSinceReferenceDate: row.double("updated_at") ?? 0),
            completedAt: row.double("completed_at").map(Date.init(timeIntervalSinceReferenceDate:))
        )
    }

    private func json<T: Encodable>(_ value: T) throws -> String {
        String(decoding: try encoder.encode(value), as: UTF8.self)
    }
}
