import AppKit
import SwiftUI

/// Owns the floating edge button: a tiny borderless panel that can be dragged,
/// snaps to the nearest left/right edge and remembers its display and position.
@MainActor
final class FloatingButtonController {
    private let model: TaskListModel
    private let settings: AppSettings
    private let state = FloatingButtonState()
    private var panel: NSPanel?
    private var screenObserver: NSObjectProtocol?
    private var knownPastDue: Set<UUID> = []
    private var nudgeTimer: Timer?
    private var hasCheckedNudges = false

    var onClick: () -> Void = {}

    init(model: TaskListModel, settings: AppSettings) {
        self.model = model
        self.settings = settings
        observeChanges { [weak self] in self?.update() }
        observeChanges { [weak self] in self?.updateNudges() }
        // Hover and style change the button's size; follow it.
        observeChanges { [weak self] in
            guard let self else { return }
            _ = self.state.windowSize
            self.resizeForState()
        }
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.layout(animated: false) }
        }
    }

    /// The button's screen frame and edge when visible, for placing the task panel beside it.
    var anchor: (frame: NSRect, edge: ScreenEdge)? {
        guard let panel, panel.isVisible else { return nil }
        return (panel.frame, settings.floatingButtonEdge)
    }

    var window: NSWindow? { panel }

    private func update() {
        state.count = model.badgeCount
        state.attention = settings.floatingButtonShowsAttention && model.needsAttention
        state.showsCount = settings.floatingButtonShowsCount
        state.edge = settings.floatingButtonEdge
        state.style = settings.floatingButtonStyle
        let enabled = settings.floatingButtonEnabled
        let level: NSWindow.Level = settings.floatingButtonAlwaysOnTop ? .floating : .normal

        guard enabled else {
            panel?.orderOut(nil)
            return
        }
        let panel = self.panel ?? makePanel()
        self.panel = panel
        panel.level = level
        layout(animated: false)
        panel.orderFrontRegardless()
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: state.windowSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        // The view draws its own soft shadow; a window shadow outlines the whole
        // transparent window in a hard dark edge.
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        panel.setAccessibilityRole(.button)

        let container = DragContainerView()
        container.onHover = { [weak self] in self?.state.isHovered = $0 }
        container.onClick = { [weak self] in self?.onClick() }
        container.onDragChanged = { [weak self] in self?.state.isDragging = true }
        container.onDragEnded = { [weak self] in
            self?.state.isDragging = false
            self?.snapToEdge()
        }
        let hosting = NSHostingView(rootView: FloatingButtonView(state: state))
        hosting.autoresizingMask = [.width, .height]
        container.addSubview(hosting)
        panel.contentView = container
        hosting.frame = container.bounds
        return panel
    }

    // MARK: - Nudge

    /// Nudges when a task newly becomes due, then keeps a gentle reminder going every
    /// `nudgeIntervalMinutes` while anything is overdue.
    private func updateNudges() {
        let pastDue = model.pastDueIDs
        let enabled = settings.floatingButtonNudges && settings.floatingButtonEnabled
        let interval = TimeInterval(settings.nudgeIntervalMinutes * 60)
        let newlyDue = !pastDue.subtracting(knownPastDue).isEmpty
        knownPastDue = pastDue
        // Tasks already overdue at launch don't count as "just became due".
        defer { hasCheckedNudges = true }

        guard enabled, !pastDue.isEmpty else {
            nudgeTimer?.invalidate()
            nudgeTimer = nil
            return
        }
        if newlyDue && hasCheckedNudges { nudge() }
        // Keep a running timer unless its interval changed, so frequent list updates
        // don't keep postponing the repeat nudge.
        guard nudgeTimer?.timeInterval != interval else { return }
        nudgeTimer?.invalidate()
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.nudge() }
        }
        timer.tolerance = 10
        RunLoop.main.add(timer, forMode: .common)
        nudgeTimer = timer
    }

    func nudge() {
        guard let panel, panel.isVisible, !state.isHovered, !state.isDragging else { return }
        state.nudgeCount += 1
    }

    // MARK: - Positioning

    /// While dragging, resize in place; otherwise re-place from the saved position.
    private func resizeForState() {
        guard let panel, panel.isVisible else { return }
        if state.isDragging {
            var frame = panel.frame
            let size = state.windowSize
            frame.origin.y += (frame.height - size.height) / 2
            frame.size = size
            panel.setFrame(frame, display: true)
        } else {
            layout(animated: false)
        }
    }

    private var screen: NSScreen? {
        NSScreen.withDisplayID(settings.floatingButtonDisplay) ?? NSScreen.main ?? NSScreen.screens.first
    }

    /// Places the button from saved settings: edge, display and vertical fraction.
    private func layout(animated: Bool) {
        guard let panel, let screen else { return }
        let size = state.windowSize
        let visible = screen.visibleFrame
        let x = settings.floatingButtonEdge == .right ? visible.maxX - size.width : visible.minX
        let centerY = visible.minY + visible.height * settings.floatingButtonPosition
        let y = min(max(centerY - size.height / 2, visible.minY + 4), visible.maxY - size.height - 4)
        let frame = NSRect(x: x, y: y, width: size.width, height: size.height)
        if animated {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.18
                panel.animator().setFrame(frame, display: true)
            }
        } else {
            panel.setFrame(frame, display: true)
        }
    }

    /// After a drag: pick the display and nearest side, remember them, and snap there.
    private func snapToEdge() {
        guard let panel else { return }
        let center = NSPoint(x: panel.frame.midX, y: panel.frame.midY)
        guard let screen = NSScreen.containing(center) else { return }
        let visible = screen.visibleFrame
        settings.floatingButtonDisplay = screen.displayID
        settings.floatingButtonEdge = center.x < visible.midX ? .left : .right
        settings.floatingButtonPosition = min(max((center.y - visible.minY) / visible.height, 0), 1)
        state.edge = settings.floatingButtonEdge
        layout(animated: true)
    }
}

/// Receives all mouse events for the button: distinguishes click from drag and moves the window.
private final class DragContainerView: NSView {
    var onClick: () -> Void = {}
    var onHover: (Bool) -> Void = { _ in }
    var onDragChanged: () -> Void = {}
    var onDragEnded: () -> Void = {}

    private var dragStartMouse: NSPoint?
    private var dragStartOrigin: NSPoint?
    private var isDragging = false

    override func hitTest(_ point: NSPoint) -> NSView? {
        frame.contains(point) ? self : nil
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self))
    }

    override func mouseEntered(with event: NSEvent) { onHover(true) }
    override func mouseExited(with event: NSEvent) { onHover(false) }

    override func mouseDown(with event: NSEvent) {
        dragStartMouse = NSEvent.mouseLocation
        dragStartOrigin = window?.frame.origin
        isDragging = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start = dragStartMouse, let origin = dragStartOrigin, let window else { return }
        let mouse = NSEvent.mouseLocation
        let dx = mouse.x - start.x, dy = mouse.y - start.y
        if !isDragging && hypot(dx, dy) > 3 {
            isDragging = true
            onDragChanged()
        }
        if isDragging {
            window.setFrameOrigin(NSPoint(x: origin.x + dx, y: origin.y + dy))
        }
    }

    override func mouseUp(with event: NSEvent) {
        if isDragging { onDragEnded() } else { onClick() }
        isDragging = false
        dragStartMouse = nil
    }
}
