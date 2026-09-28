import AppKit
import DailyCore
import Foundation
import Observation

/// Observable view state over the task store, shared by all app surfaces.
@MainActor
@Observable
final class TaskListModel {
    struct UndoAction: Identifiable {
        let id = UUID()
        let message: String
        /// The task exactly as it was before the action; saving it restores it.
        let snapshot: DailyTask
        /// A recurring task's next occurrence created by the action, removed on undo.
        var createdID: UUID?
    }

    private let store: TaskStore
    let calendar = Calendar.autoupdatingCurrent

    private(set) var groups = TaskGroups()
    /// All incomplete tasks, unsorted. Notification planning reads this.
    private(set) var activeTasks: [DailyTask] = []
    /// All categories, sorted by name.
    private(set) var categories: [TaskCategory] = []
    /// Completed within the last `historyDays`, newest first.
    private(set) var history: [DailyTask] = []

    /// Set from settings.
    var historyDays = 30 { didSet { reload() } }
    /// Heads-up reminder for new tasks with a due time (minutes before), from settings.
    var defaultReminderMinutes: Int?
    /// The time the groups were computed for. Views use it for "past due" styling.
    private(set) var now = Date()
    private(set) var lastError: String?
    private(set) var pendingUndo: UndoAction?

    @ObservationIgnored private var refreshTimer: Timer?
    @ObservationIgnored private var undoTimer: Timer?
    @ObservationIgnored private var observers: [(NotificationCenter, NSObjectProtocol)] = []

    init(store: TaskStore) {
        self.store = store
        reload()
        observeSystemChanges()
    }

    var today: DayKey { DayKey(now, calendar: calendar) }

    /// Count shown on the menu-bar icon and floating button: what needs doing today.
    var badgeCount: Int { groups.overdue.count + groups.today.count }

    /// Tasks that are overdue or whose due time today has passed.
    var pastDueIDs: Set<UUID> {
        Set(groups.overdue.map(\.id) + groups.today.filter(isPastDue).map(\.id))
    }

    /// Something is overdue or its due time today has passed.
    var needsAttention: Bool {
        !groups.overdue.isEmpty || groups.today.contains(where: isPastDue)
    }

    func isPastDue(_ task: DailyTask) -> Bool {
        TaskGrouping.isPastDue(task, now: now, calendar: calendar)
    }

    /// The due label as shown under a section heading, which already implies the day
    /// for Today and Tomorrow.
    func dueLabel(for task: DailyTask, in section: TaskSection) -> String? {
        let implied: DayKey? = switch section {
        case .today: today
        case .tomorrow: today.adding(days: 1, calendar: calendar)
        case .overdue, .upcoming: nil
        }
        return DueFormatting.dueLabel(for: task, today: today, impliedDay: implied, calendar: calendar)
    }

    // MARK: - Loading

    func reload() {
        perform {
            let tasks = try store.activeTasks()
            activeTasks = tasks
            categories = try store.categories()
            let since = calendar.date(byAdding: .day, value: -historyDays, to: DayKey(Date(), calendar: calendar).startDate(calendar: calendar))
            history = try store.completedTasks(since: since)
            now = Date()
            groups = TaskGrouping.group(tasks, now: now, calendar: calendar)
            scheduleRefresh(at: TaskGrouping.nextRefreshDate(for: tasks, now: now, calendar: calendar))
        }
    }

    /// One timer for the next moment the list changes on its own (a due time passing or
    /// midnight) instead of polling.
    private func scheduleRefresh(at date: Date) {
        refreshTimer?.invalidate()
        let timer = Timer(fire: date.addingTimeInterval(0.5), interval: 0, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.reload() }
        }
        timer.tolerance = 1
        RunLoop.main.add(timer, forMode: .common)
        refreshTimer = timer
    }

    /// Timers don't fire during sleep and the clock can jump, so regroup on these events too.
    private func observeSystemChanges() {
        let reloadOnMain: @Sendable (Notification) -> Void = { [weak self] _ in
            MainActor.assumeIsolated { self?.reload() }
        }
        let workspace = NSWorkspace.shared.notificationCenter
        let center = NotificationCenter.default
        observers = [
            (workspace, workspace.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main, using: reloadOnMain)),
            (center, center.addObserver(forName: .NSCalendarDayChanged, object: nil, queue: .main, using: reloadOnMain)),
            (center, center.addObserver(forName: .NSSystemClockDidChange, object: nil, queue: .main, using: reloadOnMain)),
            (center, center.addObserver(forName: .NSSystemTimeZoneDidChange, object: nil, queue: .main, using: reloadOnMain)),
        ]
    }

    // MARK: - Editing

    /// Parses dates, times and repeats out of `text` ("Call Alex tomorrow 11am").
    func parse(_ text: String) -> ParsedInput {
        NaturalLanguageParser(calendar: calendar, locale: .autoupdatingCurrent).parse(text, now: Date())
    }

    /// Adds a task from quick-add text, reading any date/time/repeat phrases and "#category".
    @discardableResult
    func add(parsing text: String) -> DailyTask? {
        let parsed = parse(text)
        guard !parsed.title.isEmpty else { return nil }
        var task = DailyTask(title: parsed.title, dueDay: parsed.dueDay, dueMinutes: parsed.dueMinutes, recurrence: parsed.recurrence)
        if task.hasDueTime, let minutes = defaultReminderMinutes {
            task.reminder = minutes == 0 ? .atDueTime : .minutesBefore(minutes)
        }
        perform {
            if let tag = parsed.categoryTag {
                task.categoryID = try store.findOrCreateCategory(tag: tag).id
            }
            try store.save(task)
        }
        reload()
        return task
    }

    // MARK: - Search & history

    /// Active and completed tasks matching `query`. "#work" narrows to a category and a
    /// date phrase ("tomorrow", "oct 1") also matches tasks due that day.
    func search(_ query: String) -> [DailyTask] {
        let (text, tag) = NaturalLanguageParser.extractTag(query.trimmingCharacters(in: .whitespaces))
        let category = tag.flatMap { TaskCategory.matching($0, in: categories) }
        if tag != nil && category == nil { return [] }
        let day = NaturalLanguageParser(calendar: calendar, locale: .autoupdatingCurrent).day(inQuery: text)
        var results: [DailyTask] = []
        perform { results = try store.search(day == nil ? text : "", day: day, category: category?.id) }
        if day != nil, !text.isEmpty {
            // "tomorrow" could also be a word in a title; include those too.
            var seen = Set(results.map(\.id))
            perform {
                for task in try store.search(text, category: category?.id) where seen.insert(task.id).inserted {
                    results.append(task)
                }
            }
        }
        return results
    }

    /// Puts a completed task back on the active list.
    func restore(_ task: DailyTask) {
        perform { try store.reopen(id: task.id) }
        reload()
    }

    func clearHistory() {
        perform { try store.clearHistory() }
        reload()
    }

    // MARK: - Backup

    func makeBackup(settings: [String: Backup.SettingValue]) throws -> Backup {
        Backup(tasks: try store.allTasks(), categories: try store.categories(), settings: settings)
    }

    func importPlan(for backup: Backup) throws -> Backup.ImportPlan {
        backup.mergePlan(existingIDs: Set(try store.allTasks().map(\.id)), existingCategories: try store.categories())
    }

    func apply(_ plan: Backup.ImportPlan) throws {
        try store.database.transaction {
            for category in plan.newCategories { try store.saveCategory(category) }
            for task in plan.newTasks { try store.save(task) }
        }
        reload()
    }

    /// Deletes every task and category.
    func deleteAllData() {
        perform { try store.deleteAll() }
        reload()
    }

    var databaseURL: URL? {
        store.database.path.map(URL.init(fileURLWithPath:))
    }

    // MARK: - Categories

    func category(for task: DailyTask) -> TaskCategory? {
        task.categoryID.flatMap { id in categories.first { $0.id == id } }
    }

    /// Creates a category named `name`, or returns the existing one with that name.
    @discardableResult
    func createCategory(named name: String) -> TaskCategory? {
        var result: TaskCategory?
        perform { result = try store.findOrCreateCategory(tag: name.trimmingCharacters(in: .whitespacesAndNewlines)) }
        reload()
        return result
    }

    /// Renames or recolors. Returns an error message if the name is taken or empty.
    func saveCategory(_ category: TaskCategory) -> String? {
        let name = category.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return "A category needs a name." }
        if categories.contains(where: { $0.id != category.id && $0.name.caseInsensitiveCompare(name) == .orderedSame }) {
            return "There's already a category called “\(name)”."
        }
        perform { try store.saveCategory(category) }
        reload()
        return nil
    }

    /// Deletes the category; its tasks stay, without a category.
    func deleteCategory(_ category: TaskCategory) {
        perform { try store.deleteCategory(id: category.id) }
        reload()
    }

    /// Adds a task with `title` exactly as typed.
    @discardableResult
    func add(title: String) -> DailyTask? {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let task = DailyTask(title: trimmed)
        perform { try store.save(task) }
        reload()
        return task
    }

    func save(_ task: DailyTask) {
        var task = task
        task.title = task.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !task.title.isEmpty else { return }
        task.updatedAt = Date()
        // Rescheduling restarts reminders: drop any snooze or dismissal from the old time.
        if let old = activeTasks.first(where: { $0.id == task.id }), task.scheduleDiffers(from: old) {
            task.snoozedUntil = nil
            task.notificationsAcknowledgedAt = nil
        }
        perform { try store.save(task) }
        reload()
    }

    func update(_ task: DailyTask, _ change: (inout DailyTask) -> Void) {
        var copy = task
        change(&copy)
        save(copy)
    }

    /// Completes the task; a recurring one gets its next occurrence in the same step.
    func complete(_ task: DailyTask) {
        let next = RecurringTasks.nextOccurrence(of: task, today: DayKey(Date(), calendar: calendar), calendar: calendar)
        perform { try store.complete(task, creating: next) }
        let message = next?.dueDay.map { "Completed “\(task.title)” · next \(DueFormatting.dayLabel($0, today: today, calendar: calendar))" }
        offerUndo(message ?? "Completed “\(task.title)”", restoring: task, created: next?.id)
        reload()
    }

    /// Moves a recurring task to its next occurrence without recording a completion.
    func skipOccurrence(_ task: DailyTask) {
        guard let next = RecurringTasks.nextOccurrence(of: task, today: DayKey(Date(), calendar: calendar), calendar: calendar) else { return }
        perform { try store.replace(task, with: next) }
        let label = next.dueDay.map { DueFormatting.dayLabel($0, today: today, calendar: calendar) } ?? ""
        offerUndo("Skipped to \(label)", restoring: task, created: next.id)
        reload()
    }

    // MARK: - Notification responses (by id: the task may have changed since it was sent)

    func complete(id: UUID) {
        guard let task = task(id: id), !task.isCompleted else { return }
        complete(task)
    }

    func snooze(id: UUID, for interval: TimeInterval) {
        guard let task = task(id: id) else { return }
        update(task) { $0.snoozedUntil = Date().addingTimeInterval(interval) }
    }

    func muteNotifications(id: UUID) {
        guard let task = task(id: id) else { return }
        update(task) { $0.notificationsMuted = true }
    }

    private func task(id: UUID) -> DailyTask? {
        var result: DailyTask?
        perform { result = try store.task(id: id) }
        return result
    }

    func delete(_ task: DailyTask) {
        perform { try store.delete(id: task.id) }
        offerUndo("Deleted “\(task.title)”", restoring: task)
        reload()
    }

    func undo() {
        guard let action = pendingUndo else { return }
        perform {
            try store.database.transaction {
                if let created = action.createdID { try store.delete(id: created) }
                try store.save(action.snapshot)
            }
        }
        dismissUndo()
        reload()
    }

    func dismissUndo() {
        undoTimer?.invalidate()
        pendingUndo = nil
    }

    private func offerUndo(_ message: String, restoring snapshot: DailyTask, created: UUID? = nil) {
        let action = UndoAction(message: message, snapshot: snapshot, createdID: created)
        pendingUndo = action
        undoTimer?.invalidate()
        undoTimer = Timer.scheduledTimer(withTimeInterval: 6, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                if self?.pendingUndo?.id == action.id { self?.pendingUndo = nil }
            }
        }
    }

    private func perform(_ body: () throws -> Void) {
        do {
            try body()
            lastError = nil
        } catch {
            lastError = "\(error)"
        }
    }
}
