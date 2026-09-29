import AppKit
import DailyCore
import Observation
import os
import SwiftUI

/// Shows the daily briefing on launch, wake, unlock or at the preferred time,
/// as allowed by `BriefingPolicy` and the user's settings.
@MainActor
final class BriefingController {
    private static let log = Logger(subsystem: "com.murtazacollab.nudge", category: "Briefing")
    private static let lastShownKey = "briefing.lastShownDay"

    private let model: TaskListModel
    private let settings: AppSettings
    private let height = BriefingHeight()
    private var panel: FloatingPanel?
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []
    private var timeTimer: Timer?
    private var pendingWake: DispatchWorkItem?

    var onOpenTasks: () -> Void = {}

    init(model: TaskListModel, settings: AppSettings) {
        self.model = model
        self.settings = settings
    }

    var window: NSWindow? { panel }

    /// Starts listening for wake/unlock and evaluates the launch trigger.
    func start() {
        let wake: @Sendable (Notification) -> Void = { [weak self] _ in
            MainActor.assumeIsolated { self?.scheduleWakeCheck() }
        }
        let workspace = NSWorkspace.shared.notificationCenter
        let distributed = DistributedNotificationCenter.default()
        observers = [
            (workspace, workspace.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main, using: wake)),
            (workspace, workspace.addObserver(forName: NSWorkspace.screensDidWakeNotification, object: nil, queue: .main, using: wake)),
            (workspace, workspace.addObserver(forName: NSWorkspace.sessionDidBecomeActiveNotification, object: nil, queue: .main, using: wake)),
            (distributed, distributed.addObserver(forName: Notification.Name("com.apple.screenIsUnlocked"), object: nil, queue: .main, using: wake)),
        ]
        observeChanges { [weak self] in
            guard let self else { return }
            _ = self.settings.briefingTimeMinutes
            self.scheduleTimeTrigger()
        }
        // Give the menu bar and data a moment to settle after login.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in self?.evaluate(.launch) }
    }

    /// Always shows, from the menu.
    func showNow() {
        evaluate(.manual)
    }

    #if DEBUG
    /// Shows the window without recording it as today's briefing.
    func debugPresent() { present(focus: false) }
    #endif

    func close() {
        panel?.orderOut(nil)
    }

    // MARK: - Triggers

    /// Wake, display wake and unlock often arrive together; coalesce and wait until the
    /// screen is usable.
    private func scheduleWakeCheck() {
        pendingWake?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.evaluate(.wake) }
        pendingWake = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 2, execute: work)
    }

    private func scheduleTimeTrigger() {
        timeTimer?.invalidate()
        guard let minutes = settings.briefingTimeMinutes else { return }
        let calendar = model.calendar
        let now = Date()
        var fire = calendar.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: now) ?? now
        if fire <= now { fire = calendar.date(byAdding: .day, value: 1, to: fire) ?? fire }
        let timer = Timer(fire: fire, interval: 0, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.evaluate(.scheduled)
                self?.scheduleTimeTrigger()
            }
        }
        timer.tolerance = 30
        RunLoop.main.add(timer, forMode: .common)
        timeTimer = timer
    }

    private func evaluate(_ trigger: BriefingTrigger) {
        model.reload()
        let now = Date()
        let today = DayKey(now, calendar: model.calendar)
        let lastShown = UserDefaults.standard.string(forKey: Self.lastShownKey).flatMap(DayKey.init(string:))
        let hasTasks = !model.groups.overdue.isEmpty || !model.groups.today.isEmpty
        let show = BriefingPolicy.shouldShow(
            trigger,
            preferences: settings.briefingPreferences,
            today: today,
            lastShown: lastShown,
            hasTasks: hasTasks,
            isWeekend: model.calendar.isDateInWeekend(now)
        )
        Self.log.notice("Briefing \(String(describing: trigger), privacy: .public): \(show ? "show" : "skip", privacy: .public)")
        guard show else { return }
        // Opening it from the menu doesn't use up the day's automatic briefing.
        if trigger != .manual {
            UserDefaults.standard.set(today.description, forKey: Self.lastShownKey)
        }
        present(focus: trigger == .manual)
    }

    // MARK: - Window

    private func present(focus: Bool) {
        let panel = self.panel ?? makePanel()
        self.panel = panel
        panel.contentView?.layoutSubtreeIfNeeded()
        position(panel)
        if focus {
            panel.makeKeyAndOrderFront(nil)
        } else {
            // Automatic: appear without taking the keyboard from whatever the user is typing in.
            panel.orderFrontRegardless()
        }
    }

    private func makePanel() -> FloatingPanel {
        let panel = FloatingPanel(
            contentRect: NSRect(x: 0, y: 0, width: BriefingView.width, height: 300),
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        panel.isMovableByWindowBackground = true
        panel.onClose = { [weak self] in self?.close() }

        let view = BriefingView(model: model, settings: settings, height: height, onOpenTasks: { [weak self] in
            self?.close()
            self?.onOpenTasks()
        }, onDismiss: { [weak self] in self?.close() })
        let hosting = NSHostingView(rootView: view)
        hosting.sizingOptions = []
        hosting.autoresizingMask = [.width, .height]
        panel.contentView = hosting
        observeChanges { [weak self, weak panel] in
            guard let self, let panel else { return }
            _ = self.height.value
            if panel.isVisible { self.resize(panel) }
        }
        return panel
    }

    /// Centered horizontally, in the upper part of the display with the mouse pointer.
    private func position(_ panel: NSPanel) {
        guard let screen = NSScreen.active else { return }
        let visible = screen.visibleFrame
        let h = min(height.value, visible.height - 40)
        let top = visible.maxY - visible.height * 0.15
        panel.setFrame(NSRect(x: visible.midX - BriefingView.width / 2, y: max(top - h, visible.minY + 20), width: BriefingView.width, height: h), display: true)
    }

    private func resize(_ panel: NSPanel) {
        var frame = panel.frame
        let top = frame.maxY
        frame.size.height = height.value
        frame.origin.y = top - height.value
        panel.setFrame(frame, display: true)
        panel.invalidateShadow()
    }
}

@MainActor
@Observable
final class BriefingHeight {
    var value: CGFloat = 300
}
