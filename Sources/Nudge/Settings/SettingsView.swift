import DailyCore
import SwiftUI

enum SettingsTab: Hashable {
    case general, briefing, notifications, categories, shortcuts, data
}

#if DEBUG
extension SettingsTab {
    init?(debugName: String) {
        let all: [String: SettingsTab] = ["general": .general, "briefing": .briefing, "notifications": .notifications,
                                          "categories": .categories, "shortcuts": .shortcuts, "data": .data]
        guard let tab = all[debugName] else { return nil }
        self = tab
    }
}
#endif

@MainActor
@Observable
final class SettingsNavigation {
    var tab = SettingsTab.general
}

/// The Settings window: intentionally small, one tab per area from the spec.
struct SettingsView: View {
    @Bindable var settings: AppSettings
    let model: TaskListModel
    let notifications: NotificationController
    let shortcuts: ShortcutController
    let data: DataActions
    @Bindable var navigation: SettingsNavigation

    var body: some View {
        TabView(selection: $navigation.tab) {
            GeneralSettings(settings: settings, previewNudge: data.previewNudge)
                .tabItem { Label("General", systemImage: "gearshape") }
                .tag(SettingsTab.general)
            BriefingSettings(settings: settings, showNow: data.showBriefing)
                .tabItem { Label("Briefing", systemImage: "sun.max") }
                .tag(SettingsTab.briefing)
            NotificationSettings(settings: settings, notifications: notifications)
                .tabItem { Label("Notifications", systemImage: "bell") }
                .tag(SettingsTab.notifications)
            CategorySettings(model: model)
                .tabItem { Label("Categories", systemImage: "circle.grid.2x2") }
                .tag(SettingsTab.categories)
            ShortcutsView(controller: shortcuts, settings: settings, onDone: nil)
                .tabItem { Label("Shortcuts", systemImage: "command") }
                .tag(SettingsTab.shortcuts)
            DataSettings(settings: settings, model: model, data: data)
                .tabItem { Label("Data", systemImage: "externaldrive") }
                .tag(SettingsTab.data)
        }
        .frame(width: 500)
        .fixedSize(horizontal: false, vertical: true)
    }
}

/// Things the Data tab asks the app to do (file panels, alerts, restart).
struct DataActions {
    var export: () -> Void
    var importBackup: () -> Void
    var clearHistory: () -> Void
    var resetAll: () -> Void
    var showBriefing: () -> Void
    var previewNudge: () -> Void
}

// MARK: - General

private struct GeneralSettings: View {
    @Bindable var settings: AppSettings
    let previewNudge: () -> Void

    var body: some View {
        Form {
            Section {
                Toggle("Launch at login", isOn: $settings.launchAtLogin)
                if LaunchAtLogin.needsApproval {
                    HStack {
                        Text("macOS needs you to allow this in Login Items.")
                            .foregroundStyle(Theme.orange)
                        Button("Open Login Items…") { LaunchAtLogin.openSystemSettings() }
                    }
                    .font(.caption)
                } else if !LaunchAtLogin.isInstalledCopy {
                    Text("Takes effect for the copy in /Applications.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Section("Appearance") {
                Picker("Appearance", selection: $settings.appearance) {
                    ForEach(AppearanceMode.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
            Section("Menu bar") {
                Toggle("Show menu-bar icon", isOn: $settings.showMenuBarIcon)
                    .disabled(!settings.floatingButtonEnabled)
                Toggle("Show today's count", isOn: $settings.showMenuBarCount)
                if !settings.floatingButtonEnabled {
                    Text("The icon stays visible while the floating button is off.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Section("Floating button") {
                Toggle("Show floating button", isOn: $settings.floatingButtonEnabled)
                Group {
                    Picker("Style", selection: $settings.floatingButtonStyle) {
                        ForEach(FloatingButtonStyle.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    Toggle("Keep above other windows", isOn: $settings.floatingButtonAlwaysOnTop)
                    Toggle("Show today's count", isOn: $settings.floatingButtonShowsCount)
                    Toggle("Turn red when something is overdue", isOn: $settings.floatingButtonShowsAttention)
                    HStack {
                        Toggle("Nudge when a task is due", isOn: $settings.floatingButtonNudges)
                        Button("Preview", action: previewNudge)
                            .controlSize(.small)
                    }
                    Picker("Nudge again while overdue", selection: $settings.nudgeIntervalMinutes) {
                        ForEach([2, 5, 10, 15, 30], id: \.self) { Text("Every \($0) minutes").tag($0) }
                    }
                    .disabled(!settings.floatingButtonNudges)
                }
                .disabled(!settings.floatingButtonEnabled)
            }
            Section("Task panel") {
                Toggle("Close when clicking outside", isOn: $settings.panelClosesOnOutsideClick)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Briefing

private struct BriefingSettings: View {
    @Bindable var settings: AppSettings
    let showNow: () -> Void

    var body: some View {
        Form {
            Section {
                Toggle("Show a daily briefing", isOn: $settings.briefingEnabled)
            }
            Section("When") {
                Toggle("When the Mac starts", isOn: $settings.briefingOnLaunch)
                Toggle("After waking or unlocking", isOn: $settings.briefingOnWake)
                Toggle("Also at a set time", isOn: Binding(
                    get: { settings.briefingTimeMinutes != nil },
                    set: { settings.briefingTimeMinutes = $0 ? 9 * 60 : nil }
                ))
                if let minutes = settings.briefingTimeMinutes {
                    DatePicker("Time", selection: Binding(
                        get: { Calendar.current.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: Date()) ?? Date() },
                        set: {
                            let c = Calendar.current.dateComponents([.hour, .minute], from: $0)
                            settings.briefingTimeMinutes = (c.hour ?? 9) * 60 + (c.minute ?? 0)
                        }
                    ), displayedComponents: .hourAndMinute)
                }
                Toggle("Only once per day", isOn: $settings.briefingOncePerDay)
                Toggle("Only when there are tasks", isOn: $settings.briefingOnlyIfTasks)
                Toggle("Skip weekends", isOn: $settings.briefingSkipWeekends)
            }
            .disabled(!settings.briefingEnabled)
            Section("Include") {
                Toggle("Overdue tasks", isOn: $settings.briefingIncludeOverdue)
                Toggle("Upcoming tasks", isOn: $settings.briefingIncludeUpcoming)
            }
            .disabled(!settings.briefingEnabled)
            Section {
                Button("Show Today's Briefing", action: showNow)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Notifications

private struct NotificationSettings: View {
    @Bindable var settings: AppSettings
    let notifications: NotificationController

    private static let intervals = [5, 10, 15, 30, 60]

    var body: some View {
        Form {
            Section {
                Toggle("Notify when tasks are due", isOn: $settings.notificationsEnabled)
                LabeledContent("macOS permission") {
                    HStack {
                        Text(permissionText)
                            .foregroundStyle(notifications.isDenied ? Theme.orange : .secondary)
                        Button("Notification Settings…") { notifications.openSystemSettings() }
                    }
                }
            }
            Section("Reminders") {
                Picker("Default reminder for new tasks", selection: $settings.defaultReminderMinutes) {
                    Text("None (just at the due time)").tag(Int?.none)
                    ForEach([5, 10, 15, 30, 60], id: \.self) { minutes in
                        Text(minutes == 60 ? "1 hour before" : "\(minutes) minutes before").tag(Int?.some(minutes))
                    }
                }
                Toggle("Keep reminding until done", isOn: $settings.persistentReminders)
                Picker("Remind again every", selection: $settings.repeatIntervalMinutes) {
                    ForEach(intervalChoices, id: \.self) { minutes in
                        Text(minutes == 60 ? "1 hour" : "\(minutes) minutes").tag(minutes)
                    }
                }
                .disabled(!settings.persistentReminders)
                Stepper("Custom: \(settings.repeatIntervalMinutes) min", value: $settings.repeatIntervalMinutes, in: 1...240)
                    .disabled(!settings.persistentReminders)
            }
            .disabled(!settings.notificationsEnabled)
            Section {
                Text("Tip: set the style to **Alerts** in Notification Settings so reminders stay on screen until you act. “Don't Notify Again” on a notification silences just that task.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .task { await notifications.refreshAuthorization() }
    }

    /// Presets plus the current value if it's custom.
    private var intervalChoices: [Int] {
        Self.intervals.contains(settings.repeatIntervalMinutes) ? Self.intervals : (Self.intervals + [settings.repeatIntervalMinutes]).sorted()
    }

    private var permissionText: String {
        switch notifications.authorization {
        case .authorized, .provisional: "Allowed"
        case .denied: "Off — reminders can't alert you"
        default: "Not asked yet"
        }
    }
}

// MARK: - Categories

private struct CategorySettings: View {
    let model: TaskListModel
    @State private var newName = ""
    @State private var error: String?
    @State private var deleting: TaskCategory?

    var body: some View {
        Form {
            Section {
                if model.categories.isEmpty {
                    Text("No categories yet. Type #name in Quick Add (for example “#work”), or add one here.")
                        .foregroundStyle(.secondary)
                }
                ForEach(model.categories) { category in
                    CategoryRow(category: category, model: model, error: $error) { deleting = category }
                }
                HStack {
                    TextField("New category", text: $newName, prompt: Text("New category"))
                        .labelsHidden()
                        .onSubmit(add)
                    Button("Add", action: add)
                        .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            } footer: {
                if let error {
                    Text(error).foregroundStyle(Theme.red)
                } else if !model.categories.isEmpty {
                    Text("Click a name to rename it. Click a dot to change its color.")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .confirmationDialog(
            "Delete “\(deleting?.name ?? "")”?",
            isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
            presenting: deleting
        ) { category in
            Button("Delete Category", role: .destructive) { model.deleteCategory(category) }
        } message: { _ in
            Text("Its tasks are kept, without a category.")
        }
    }

    private func add() {
        let name = newName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        if model.categories.contains(where: { TaskCategory.matchKey($0.name) == TaskCategory.matchKey(name) }) {
            error = "There's already a category called “\(name)”."
            return
        }
        model.createCategory(named: name)
        newName = ""
        error = nil
    }
}

private struct CategoryRow: View {
    let category: TaskCategory
    let model: TaskListModel
    @Binding var error: String?
    let onDelete: () -> Void
    @State private var name: String
    @FocusState private var nameFocused: Bool

    init(category: TaskCategory, model: TaskListModel, error: Binding<String?>, onDelete: @escaping () -> Void) {
        self.category = category
        self.model = model
        _error = error
        self.onDelete = onDelete
        _name = State(initialValue: category.name)
    }

    var body: some View {
        HStack {
            Menu {
                ForEach(TaskCategory.palette.indices, id: \.self) { index in
                    Button(TaskCategory.paletteNames[index]) {
                        var updated = category
                        updated.color = index
                        error = model.saveCategory(updated)
                    }
                }
            } label: {
                Circle().fill(category.swiftUIColor).frame(width: 14, height: 14)
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Change color")
            .accessibilityLabel("Color")
            TextField("Name", text: $name)
                .labelsHidden()
                .textFieldStyle(.plain)
                .multilineTextAlignment(.leading)
                .focused($nameFocused)
                .onSubmit(rename)
                // Also save when clicking elsewhere or closing Settings, not only on Return.
                .onChange(of: nameFocused) { if !nameFocused { rename() } }
                .onDisappear(perform: rename)
            Spacer()
            Button(role: .destructive, action: onDelete) {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Delete \(category.name)")
        }
        .onChange(of: category.name) { name = category.name }
    }

    private func rename() {
        guard name != category.name else { return }
        var updated = category
        updated.name = name
        error = model.saveCategory(updated)
        if error != nil { name = category.name }
    }
}

// MARK: - Data

private struct DataSettings: View {
    @Bindable var settings: AppSettings
    let model: TaskListModel
    let data: DataActions

    var body: some View {
        Form {
            Section("History") {
                Picker("Show completed tasks from the last", selection: $settings.historyDays) {
                    ForEach([7, 30, 90, 365], id: \.self) { days in
                        Text(days == 365 ? "year" : "\(days) days").tag(days)
                    }
                }
                Button("Clear History…", action: data.clearHistory)
            }
            Section("Backup") {
                HStack {
                    Button("Export…", action: data.export)
                    Button("Import…", action: data.importBackup)
                }
                Text("A JSON file with all tasks, completion history, categories and settings. Importing adds tasks you don't already have; nothing is overwritten.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("Storage") {
                if let url = model.databaseURL {
                    LabeledContent("Tasks are stored on this Mac") {
                        Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
                    }
                }
                Button("Reset All Data…", role: .destructive, action: data.resetAll)
            }
        }
        .formStyle(.grouped)
    }
}
