import SwiftUI

/// Panel content: header (date, Search, History, options), then tasks, history or search.
struct TaskPanelView: View {
    let model: TaskListModel
    @Bindable var settings: AppSettings
    let notifications: NotificationController
    @Bindable var panelState: PanelState
    let onClose: () -> Void
    let onShowShortcuts: () -> Void
    let onShowBriefing: () -> Void
    let onShowSettings: () -> Void

    @State private var confirmingClearHistory = false

    var body: some View {
        VStack(spacing: 0) {
            header
            if notifications.isDenied && settings.notificationsEnabled && panelState.mode == .tasks {
                permissionHint
            }
            switch panelState.mode {
            case .tasks:
                TaskListView(model: model, maxListHeight: panelState.maxListHeight, focusAddFieldRequest: panelState.focusAddFieldRequest)
            case .history:
                HistoryView(model: model, maxListHeight: panelState.maxListHeight) { confirmingClearHistory = true }
            case .search:
                SearchView(model: model, state: panelState, maxListHeight: panelState.maxListHeight)
            }
        }
        .frame(width: TaskPanelController.width)
        // Take the ideal height whatever the window's current size, and report it so the
        // panel can resize to fit (e.g. after adding a task).
        .fixedSize(horizontal: false, vertical: true)
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { panelState.contentHeight = $0 }
        .frame(maxHeight: .infinity, alignment: .top)
        .background {
            // ⌘K opens search from anywhere in the panel.
            Button("") { toggle(.search) }
                .keyboardShortcut("k", modifiers: .command)
                .hidden()
        }
        .confirmationDialog("Clear all completed tasks?", isPresented: $confirmingClearHistory) {
            Button("Clear History", role: .destructive) { model.clearHistory() }
        } message: {
            Text("Completed tasks are deleted permanently. Active tasks aren't affected.")
        }
    }

    private func toggle(_ mode: PanelMode) {
        if mode == .search && panelState.mode != .search { panelState.searchQuery = "" }
        panelState.mode = panelState.mode == mode ? .tasks : mode
    }

    /// Shown when macOS notification permission is off, since reminders then can't alert.
    private var permissionHint: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: "bell.slash")
                .foregroundStyle(Theme.orange)
            Text("Notifications are off in System Settings, so reminders can't alert you.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Button("Turn On…") { notifications.openSystemSettings() }
                .buttonStyle(.link)
                .font(.system(size: 12))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    private var title: String {
        switch panelState.mode {
        case .tasks: model.now.formatted(.dateTime.weekday(.wide).month(.wide).day())
        case .history: "History"
        case .search: "Search"
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 10) {
            if panelState.mode != .tasks {
                Button { panelState.mode = .tasks } label: {
                    Image(systemName: "chevron.left")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .accessibilityLabel("Back to tasks")
            }
            Text(title)
                .font(.system(size: 13, weight: .semibold))
            Spacer()
            headerButton("magnifyingglass", "Search (⌘K)", active: panelState.mode == .search) { toggle(.search) }
            headerButton("clock.arrow.circlepath", "History", active: panelState.mode == .history) { toggle(.history) }
            Menu {
                Button("Settings…", action: onShowSettings)
                    .keyboardShortcut(",", modifiers: .command)
                Button("Show Today's Briefing", action: onShowBriefing)
                Button("Keyboard Shortcuts…", action: onShowShortcuts)
                Divider()
                Button("Quit Nudge…") { AppDelegate.confirmQuit() }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .foregroundStyle(.secondary)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .accessibilityLabel("Options")
            Button(action: onClose) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.tertiary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close")
        }
        .padding(.horizontal, 14)
        .padding(.top, 12)
        .padding(.bottom, 2)
    }

    private func headerButton(_ symbol: String, _ label: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .foregroundStyle(active ? Theme.accent : .secondary)
        }
        .buttonStyle(.plain)
        .help(label)
        .accessibilityLabel(label)
    }
}
