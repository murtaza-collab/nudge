import AppKit
import Observation
import SwiftUI

/// Where the panel opens from, which decides where it's placed.
enum PanelAnchor {
    case floatingButton
    case statusItem
    /// Keyboard-triggered: on the display with the mouse pointer.
    case activeScreen
}

/// A request to open one task's editor. The token makes repeated requests for the same task distinct.
struct EditRequest: Equatable {
    let taskID: UUID
    let token = UUID()
}

enum PanelMode {
    case tasks, history, search
}

/// State the panel's SwiftUI content reads from its controller.
@MainActor
@Observable
final class PanelState {
    var mode: PanelMode = .tasks
    var searchQuery = ""
    /// Opens a task's editor from keyboard navigation in search.
    var editRequest: EditRequest?
    /// Height available to the task list before it scrolls.
    var maxListHeight: CGFloat = 480
    /// Incremented to ask the add field to take focus.
    var focusAddFieldRequest = 0
    /// The content's ideal height, reported by the SwiftUI view; the panel follows it.
    var contentHeight: CGFloat = 0
}

/// The floating task panel: a borderless, non-activating panel sized to its content.
@MainActor
final class TaskPanelController {
    static let width: CGFloat = 400
    static let maxHeight: CGFloat = 600
    /// Approximate height of everything above the list (header + add field).
    private static let chromeHeight: CGFloat = 100

    private let model: TaskListModel
    private let settings: AppSettings
    private let notifications: NotificationController
    private let state = PanelState()
    private var panel: FloatingPanel?
    private var anchor: PanelAnchor = .activeScreen
    /// Top edge chosen when the panel opened; kept while its height changes so the add
    /// field doesn't jump while typing.
    private var anchoredTop: CGFloat?
    private var outsideClickMonitor: Any?
    private var escapeMonitor: Any?

    var floatingButtonAnchor: () -> (frame: NSRect, edge: ScreenEdge)? = { nil }
    var statusItemFrame: () -> NSRect? = { nil }
    var onShowShortcuts: () -> Void = {}
    var onShowBriefing: () -> Void = {}
    var onShowSettings: () -> Void = {}

    init(model: TaskListModel, settings: AppSettings, notifications: NotificationController) {
        self.model = model
        self.settings = settings
        self.notifications = notifications
        observeChanges { [weak self] in
            guard let self else { return }
            _ = self.state.contentHeight
            self.layout()
        }
    }

    var isVisible: Bool { panel?.isVisible == true }
    var window: NSWindow? { panel }

    func toggle(from anchor: PanelAnchor) {
        isVisible ? close() : show(from: anchor)
    }

    func show(from anchor: PanelAnchor, focusAddField: Bool = false, mode: PanelMode = .tasks) {
        state.mode = mode
        self.anchor = anchor
        let panel = self.panel ?? makePanel()
        self.panel = panel
        model.reload()
        // Permission may have changed in System Settings since last time.
        Task { await notifications.refreshAuthorization() }
        anchoredTop = nil
        // Let SwiftUI measure before the first appearance so the panel opens at the right size.
        panel.contentView?.layoutSubtreeIfNeeded()
        layout()
        panel.makeKeyAndOrderFront(nil)
        if focusAddField { state.focusAddFieldRequest += 1 }
        installMonitors()
    }

    #if DEBUG
    func debugSetMode(_ mode: PanelMode, query: String) {
        state.searchQuery = query
        state.mode = mode
    }
    #endif

    func close() {
        panel?.orderOut(nil)
        removeMonitors()
    }

    // MARK: - Window

    private func makePanel() -> FloatingPanel {
        let panel = FloatingPanel(
            contentRect: NSRect(x: 0, y: 0, width: Self.width, height: 300),
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
        panel.animationBehavior = .utilityWindow
        panel.onClose = { [weak self] in self?.close() }

        let background = NSVisualEffectView()
        background.material = .popover
        background.blendingMode = .behindWindow
        background.state = .active
        background.wantsLayer = true
        background.layer?.cornerRadius = 12
        background.layer?.cornerCurve = .continuous
        background.layer?.masksToBounds = true

        let content = TaskPanelView(model: model, settings: settings, notifications: notifications, panelState: state, onClose: { [weak self] in self?.close() }, onShowShortcuts: { [weak self] in
            self?.close()
            self?.onShowShortcuts()
        }, onShowBriefing: { [weak self] in
            self?.close()
            self?.onShowBriefing()
        }, onShowSettings: { [weak self] in
            self?.close()
            self?.onShowSettings()
        })
        let hosting = NSHostingView(rootView: content)
        hosting.sizingOptions = []
        hosting.autoresizingMask = [.width, .height]
        background.addSubview(hosting)
        panel.contentView = background
        hosting.frame = background.bounds
        return panel
    }

    /// Sizes the panel to its content and positions it for the current anchor.
    private func layout() {
        guard let panel, state.contentHeight > 0 else { return }
        let screen = targetScreen
        let visible = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let maxHeight = min(Self.maxHeight, visible.height - 16)
        state.maxListHeight = max(maxHeight - Self.chromeHeight, 120)

        let height = min(state.contentHeight, maxHeight)
        let size = NSSize(width: Self.width, height: height)
        let top = anchoredTop ?? initialTop(for: size, in: visible)
        anchoredTop = top

        var frame = NSRect(x: initialX(for: size, in: visible), y: top - size.height, width: size.width, height: size.height)
        frame.origin.y = max(frame.minY, visible.minY + 8)
        frame.origin.x = min(max(frame.minX, visible.minX + 8), visible.maxX - size.width - 8)
        panel.setFrame(frame, display: true)
        panel.invalidateShadow()
    }

    private var targetScreen: NSScreen? {
        switch anchor {
        case .floatingButton:
            floatingButtonAnchor().flatMap { NSScreen.containing(NSPoint(x: $0.frame.midX, y: $0.frame.midY)) } ?? .active
        case .statusItem:
            statusItemFrame().flatMap { NSScreen.containing(NSPoint(x: $0.midX, y: $0.midY)) } ?? .active
        case .activeScreen:
            .active
        }
    }

    private func initialTop(for size: NSSize, in visible: NSRect) -> CGFloat {
        switch anchor {
        case .floatingButton:
            // Vertically centered on the button, kept on screen.
            guard let button = floatingButtonAnchor()?.frame else { return visible.maxY - visible.height * 0.18 }
            let top = button.midY + size.height / 2
            return min(max(top, visible.minY + size.height + 8), visible.maxY - 8)
        case .statusItem:
            return (statusItemFrame()?.minY).map { $0 - 6 } ?? visible.maxY - 6
        case .activeScreen:
            return visible.maxY - visible.height * 0.18
        }
    }

    private func initialX(for size: NSSize, in visible: NSRect) -> CGFloat {
        switch anchor {
        case .floatingButton:
            guard let (button, edge) = floatingButtonAnchor() else { return visible.midX - size.width / 2 }
            return edge == .right ? button.minX - size.width - 8 : button.maxX + 8
        case .statusItem:
            guard let item = statusItemFrame() else { return visible.maxX - size.width - 8 }
            return item.midX - size.width / 2
        case .activeScreen:
            return visible.midX - size.width / 2
        }
    }

    // MARK: - Dismissal

    private func installMonitors() {
        removeMonitors()
        if settings.panelClosesOnOutsideClick {
            // Global monitors only see clicks in other apps; clicks on our own
            // floating button or menu-bar item toggle the panel themselves.
            outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
                MainActor.assumeIsolated { self?.close() }
            }
        }
        // Esc closes the panel even while a text field has focus (field editors swallow cancelOperation).
        escapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.keyCode == 53 else { return event }
            let eventWindow = event.window.map(ObjectIdentifier.init)
            let handled = MainActor.assumeIsolated {
                guard let self, let panel = self.panel, eventWindow == ObjectIdentifier(panel) else { return false }
                // Esc steps back from History/Search to the task list before closing.
                if self.state.mode != .tasks {
                    self.state.mode = .tasks
                } else {
                    self.close()
                }
                return true
            }
            return handled ? nil : event
        }
    }

    private func removeMonitors() {
        if let outsideClickMonitor { NSEvent.removeMonitor(outsideClickMonitor) }
        if let escapeMonitor { NSEvent.removeMonitor(escapeMonitor) }
        outsideClickMonitor = nil
        escapeMonitor = nil
    }
}

/// Borderless panel that can still take keyboard focus without activating the app,
/// like Spotlight: the app you were in stays frontmost.
final class FloatingPanel: NSPanel {
    var onClose: () -> Void = {}

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func cancelOperation(_ sender: Any?) { onClose() }

    /// Standard editing shortcuts, which normally come from the main menu. A non-activating
    /// panel of a menu-bar app can't rely on that, so route them directly.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if super.performKeyEquivalent(with: event) { return true }
        guard event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command,
              let key = event.charactersIgnoringModifiers else { return false }
        let action: Selector? = switch key {
        case "x": #selector(NSText.cut(_:))
        case "c": #selector(NSText.copy(_:))
        case "v": #selector(NSText.paste(_:))
        case "a": #selector(NSText.selectAll(_:))
        case "z": Selector(("undo:"))
        case "w": #selector(NSWindow.performClose(_:))
        default: nil
        }
        if action == #selector(NSWindow.performClose(_:)) {
            onClose()
            return true
        }
        return action.map { NSApp.sendAction($0, to: nil, from: self) } ?? false
    }
}
