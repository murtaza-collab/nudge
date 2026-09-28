import AppKit
import DailyCore
import Observation
import os
@preconcurrency import UserNotifications

/// Turns the `NotificationPlanner` plan into scheduled macOS notifications and handles
/// the Complete / Remind Me Later / Don't Notify Again actions.
@MainActor
@Observable
final class NotificationController: NSObject {
    private let model: TaskListModel
    private let settings: AppSettings
    @ObservationIgnored private let center = UNUserNotificationCenter.current()
    @ObservationIgnored private var resyncTimer: Timer?
    /// Serializes syncs so remove-then-add passes never interleave.
    @ObservationIgnored private var syncChain: Task<Void, Never>?

    /// Current macOS permission; the panel shows a hint when it's denied.
    private(set) var authorization: UNAuthorizationStatus = .notDetermined

    private static let log = Logger(subsystem: "com.murtazacollab.nudge", category: "Notifications")
    private static let categoryID = "TASK_DUE"
    nonisolated private static let taskIDKey = "taskID"

    private enum ActionID {
        static let complete = "COMPLETE"
        static let snooze = "SNOOZE"
        static let mute = "MUTE"
    }

    init(model: TaskListModel, settings: AppSettings) {
        self.model = model
        self.settings = settings
        super.init()
        center.delegate = self
        center.setNotificationCategories([
            UNNotificationCategory(
                identifier: Self.categoryID,
                actions: [
                    UNNotificationAction(identifier: ActionID.complete, title: "Complete"),
                    UNNotificationAction(identifier: ActionID.snooze, title: "Remind Me Later"),
                    UNNotificationAction(identifier: ActionID.mute, title: "Don't Notify Again", options: [.destructive]),
                ],
                // Closing an alert only clears it; repeats continue until the task is
                // completed, muted ("Don't Notify Again") or rescheduled.
                intentIdentifiers: []
            ),
        ])
    }

    var isDenied: Bool { authorization == .denied }

    /// Starts keeping the schedule in sync, and asks for permission if never asked.
    /// Syncing doesn't wait for the answer: a permission change triggers a re-sync.
    func start(requestPermission: Bool = true) {
        observeChanges { [weak self] in self?.scheduleSync() }
        Task {
            await refreshAuthorization()
            if requestPermission { requestPermissionIfNeeded() }
        }
    }

    /// Shows the macOS permission prompt if it has never been answered.
    func requestPermissionIfNeeded() {
        Task {
            await refreshAuthorization()
            guard authorization == .notDetermined, settings.notificationsEnabled else { return }
            _ = try? await center.requestAuthorization(options: [.alert, .sound])
            await refreshAuthorization()
        }
    }

    func refreshAuthorization() async {
        authorization = await center.notificationSettings().authorizationStatus
    }

    func openSystemSettings() {
        let id = Bundle.main.bundleIdentifier ?? ""
        if let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension?id=\(id)") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: - Scheduling

    /// Reads the observable inputs (so changes trigger a re-sync) and queues a sync.
    private func scheduleSync() {
        let tasks = model.activeTasks
        let enabled = settings.notificationsEnabled && authorization != .denied
        let planner = NotificationPlanner(
            repeatInterval: TimeInterval(settings.repeatIntervalMinutes * 60),
            persistent: settings.persistentReminders
        )
        let previous = syncChain
        syncChain = Task {
            await previous?.value
            await sync(tasks: tasks, enabled: enabled, planner: planner)
        }
    }

    private func sync(tasks: [DailyTask], enabled: Bool, planner: NotificationPlanner) async {
        let now = Date()
        let calendar = model.calendar
        let plan = enabled ? planner.plan(for: tasks, now: now, calendar: calendar) : []

        center.removeAllPendingNotificationRequests()
        let byID = Dictionary(uniqueKeysWithValues: tasks.map { ($0.id, $0) })
        for item in plan {
            guard let task = byID[item.taskID] else { continue }
            let request = UNNotificationRequest(
                identifier: "\(task.id.uuidString).\(Int(item.fireDate.timeIntervalSince1970))",
                content: content(for: task, kind: item.kind, firing: item.fireDate, calendar: calendar),
                trigger: UNCalendarNotificationTrigger(
                    dateMatching: calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: item.fireDate),
                    repeats: false
                )
            )
            try? await center.add(request)
        }

        Self.log.notice("Scheduled \(plan.count, privacy: .public) notifications; next at \(plan.first?.fireDate.description ?? "none", privacy: .public); permission \(self.authorization.rawValue, privacy: .public)")

        await cleanUpDelivered(tasks: tasks, enabled: enabled, calendar: calendar)

        // Re-plan just after the next one fires, to tidy up and top the queue back up.
        resyncTimer?.invalidate()
        if let next = plan.first?.fireDate {
            let timer = Timer(fire: next.addingTimeInterval(2), interval: 0, repeats: false) { [weak self] _ in
                MainActor.assumeIsolated { self?.scheduleSync() }
            }
            timer.tolerance = 2
            RunLoop.main.add(timer, forMode: .common)
            resyncTimer = timer
        }
    }

    /// Keeps Notification Center to one entry per task and removes entries for tasks
    /// that no longer need attention (completed, muted, dismissed, deleted).
    private func cleanUpDelivered(tasks: [DailyTask], enabled: Bool, calendar: Calendar) async {
        let delivered = await center.deliveredNotifications()
        let notifiable = Set(tasks.filter { NotificationPlanner.isNotifiable($0, calendar: calendar) }.map(\.id.uuidString))
        var newestPerTask: [String: UNNotification] = [:]
        var stale: [String] = []
        for notification in delivered {
            guard let taskID = notification.request.content.userInfo[Self.taskIDKey] as? String else { continue }
            guard enabled, notifiable.contains(taskID) else {
                stale.append(notification.request.identifier)
                continue
            }
            if let kept = newestPerTask[taskID] {
                let older = kept.date < notification.date ? kept : notification
                stale.append(older.request.identifier)
                if older === kept { newestPerTask[taskID] = notification }
            } else {
                newestPerTask[taskID] = notification
            }
        }
        if !stale.isEmpty { center.removeDeliveredNotifications(withIdentifiers: stale) }
    }

    private func content(for task: DailyTask, kind: PlannedNotification.Kind, firing: Date, calendar: Calendar) -> UNNotificationContent {
        let content = UNMutableNotificationContent()
        content.title = task.title
        content.subtitle = subtitle(for: task, kind: kind, firing: firing, calendar: calendar)
        if let firstLine = task.notes.split(whereSeparator: \.isNewline).first {
            content.body = String(firstLine)
        }
        content.sound = .default
        content.categoryIdentifier = Self.categoryID
        content.threadIdentifier = task.id.uuidString
        content.userInfo = [Self.taskIDKey: task.id.uuidString]
        return content
    }

    private func subtitle(for task: DailyTask, kind: PlannedNotification.Kind, firing: Date, calendar: Calendar) -> String {
        let today = DayKey(firing, calendar: calendar)
        let due = DueFormatting.dueLabel(for: task, today: today, calendar: calendar)
        switch kind {
        case .reminder:
            return due.map { "Reminder · due \($0)" } ?? "Reminder"
        case .due:
            return task.hasDueTime ? "Due now" : "Reminder"
        case .repeated:
            guard let dueDate = task.dueDate(calendar: calendar), dueDate < firing else { return "Still to do" }
            let minutes = Int(firing.timeIntervalSince(dueDate) / 60)
            let overdue = minutes < 60 ? "\(minutes) min" : minutes < 1440 ? "\(minutes / 60) hr" : "\(minutes / 1440) d"
            return "Overdue by \(overdue)" + (due.map { " · was due \($0)" } ?? "")
        }
    }

    // MARK: - Responses

    fileprivate func handle(action: String, taskID: String) {
        guard let id = UUID(uuidString: taskID) else { return }
        Self.log.notice("Notification response \(action, privacy: .public) for \(taskID, privacy: .public)")
        switch action {
        case ActionID.complete:
            model.complete(id: id)
        case ActionID.snooze:
            model.snooze(id: id, for: TimeInterval(settings.repeatIntervalMinutes * 60))
        case ActionID.mute:
            model.muteNotifications(id: id)
        default:
            // Clicked the notification itself.
            onOpen?()
        }
    }

    /// Called when the user clicks a notification's body; the app opens the task panel.
    @ObservationIgnored var onOpen: (() -> Void)?
}

extension NotificationController: UNUserNotificationCenterDelegate {
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let action = response.actionIdentifier
        guard let taskID = response.notification.request.content.userInfo[Self.taskIDKey] as? String else { return }
        await MainActor.run { handle(action: action, taskID: taskID) }
    }

    /// Show notifications even while the task panel is open.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }
}
