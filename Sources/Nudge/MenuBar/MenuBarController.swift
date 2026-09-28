import AppKit

/// The menu-bar item. Left click toggles the task panel; right click shows a small menu.
@MainActor
final class MenuBarController: NSObject {
    struct Actions {
        var togglePanel: () -> Void
        var addTask: () -> Void
        var showBriefing: () -> Void
        var search: () -> Void
        var showSettings: () -> Void
        var quit: () -> Void
    }

    private let model: TaskListModel
    private let settings: AppSettings
    private let actions: Actions
    private var statusItem: NSStatusItem?

    init(model: TaskListModel, settings: AppSettings, actions: Actions) {
        self.model = model
        self.settings = settings
        self.actions = actions
        super.init()
        observeChanges { [weak self] in self?.update() }
    }

    /// Screen frame of the menu-bar button, for positioning the panel beneath it.
    var buttonFrame: NSRect? {
        guard let button = statusItem?.button, let window = button.window else { return nil }
        return window.convertToScreen(button.convert(button.bounds, to: nil))
    }

    private func update() {
        guard settings.effectiveShowMenuBarIcon else {
            if let statusItem { NSStatusBar.system.removeStatusItem(statusItem) }
            statusItem = nil
            return
        }
        let item = statusItem ?? makeStatusItem()
        statusItem = item
        guard let button = item.button else { return }

        let attention = model.needsAttention
        let count = model.badgeCount
        let symbol = attention ? "exclamationmark.circle" : (count > 0 ? "circle.inset.filled" : "circle")
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: "Nudge")
        image?.isTemplate = true
        button.image = image
        button.imagePosition = .imageLeading
        button.title = settings.showMenuBarCount && count > 0 ? " \(count)" : ""
        button.toolTip = count == 0
            ? "Nothing due today"
            : "\(count) task\(count == 1 ? "" : "s") today" + (attention ? " — something is overdue" : "")
    }

    private func makeStatusItem() -> NSStatusItem {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.target = self
        item.button?.action = #selector(buttonClicked)
        item.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        return item
    }

    @objc private func buttonClicked() {
        let event = NSApp.currentEvent
        if event?.type == .rightMouseUp || event?.modifierFlags.contains(.control) == true {
            showMenu()
        } else {
            actions.togglePanel()
        }
    }

    private func showMenu() {
        guard let button = statusItem?.button else { return }
        let menu = NSMenu()
        menu.addItem(item("Open Tasks", #selector(openTasks)))
        menu.addItem(item("Add Task…", #selector(addTask)))
        menu.addItem(item("Search…", #selector(search)))
        menu.addItem(item("Show Today's Briefing", #selector(showBriefing)))
        menu.addItem(.separator())
        let floating = item("Show Floating Button", #selector(toggleFloatingButton))
        floating.state = settings.floatingButtonEnabled ? .on : .off
        menu.addItem(floating)
        menu.addItem(.separator())
        menu.addItem(item("Settings…", #selector(showSettings), key: ","))
        menu.addItem(item("Quit Nudge…", #selector(quit), key: "q"))
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.height + 4), in: button)
    }

    private func item(_ title: String, _ action: Selector, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        return item
    }

    @objc private func openTasks() { actions.togglePanel() }
    @objc private func addTask() { actions.addTask() }
    @objc private func showBriefing() { actions.showBriefing() }
    @objc private func search() { actions.search() }
    @objc private func showSettings() { actions.showSettings() }
    @objc private func toggleFloatingButton() { settings.floatingButtonEnabled.toggle() }
    @objc private func quit() { actions.quit() }
}
