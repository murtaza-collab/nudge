import DailyCore
import SwiftUI

/// Popover editor for a single task. Core fields are always visible;
/// description and links sit under "More" unless they already have content.
struct TaskEditorView: View {
    let model: TaskListModel
    let calendar: Calendar
    let onSave: (DailyTask) -> Void
    let onCancel: () -> Void

    @State private var draft: DailyTask
    @State private var links: [LinkDraft]
    @State private var showMore: Bool
    @FocusState private var titleFocused: Bool
    @State private var newCategoryName: String?

    init(task: DailyTask, model: TaskListModel, onSave: @escaping (DailyTask) -> Void, onCancel: @escaping () -> Void) {
        self.model = model
        self.calendar = model.calendar
        self.onSave = onSave
        self.onCancel = onCancel
        _draft = State(initialValue: task)
        _links = State(initialValue: task.links.map(LinkDraft.init))
        _showMore = State(initialValue: !task.notes.isEmpty || !task.links.isEmpty)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            TextField("Title", text: $draft.title, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: 15, weight: .semibold))
                .lineLimit(1...4)
                .focused($titleFocused)

            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 12, verticalSpacing: 10) {
                GridRow {
                    label("Due")
                    dueControls
                }
                if draft.dueDay != nil {
                    GridRow {
                        label("Time")
                        timeControls
                    }
                }
                GridRow {
                    label("Repeat")
                    RepeatEditor(task: $draft, calendar: calendar)
                }
                GridRow {
                    label("Reminder")
                    reminderControls
                }
                GridRow {
                    label("Category")
                    categoryControls
                }
                GridRow {
                    label("Priority")
                    Picker("Priority", selection: $draft.priority) {
                        ForEach(Priority.allCases.reversed(), id: \.self) { priority in
                            Label(priority.title, systemImage: priority.symbol).tag(priority)
                        }
                    }
                    .labelsHidden()
                    .fixedSize()
                }
            }

            DisclosureGroup(isExpanded: $showMore) {
                VStack(alignment: .leading, spacing: 12) {
                    notesEditor
                    linksEditor
                }
                .padding(.top, 8)
            } label: {
                label("More")
            }

            HStack {
                Spacer()
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button("Save", action: save)
                    .keyboardShortcut(.defaultAction)
                    .disabled(draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(16)
        .frame(width: 340)
        .onAppear { titleFocused = true }
    }

    // MARK: - Due date & time

    private var dueControls: some View {
        HStack(spacing: 6) {
            if draft.dueDay != nil {
                DatePicker("Due date", selection: dueDateBinding, displayedComponents: .date)
                    .labelsHidden()
                    .datePickerStyle(.field)
                clearButton("Remove due date") {
                    draft.dueDay = nil
                    draft.dueMinutes = nil
                    draft.recurrence = nil
                }
            } else {
                Button("Today") { draft.dueDay = DayKey(Date(), calendar: calendar) }
                Button("Tomorrow") { draft.dueDay = DayKey(Date(), calendar: calendar).adding(days: 1, calendar: calendar) }
                Button("Pick…") { draft.dueDay = DayKey(Date(), calendar: calendar) }
            }
        }
        .controlSize(.small)
    }

    @ViewBuilder
    private var timeControls: some View {
        HStack(spacing: 6) {
            if draft.dueMinutes != nil {
                DatePicker("Due time", selection: dueTimeBinding, displayedComponents: .hourAndMinute)
                    .labelsHidden()
                    .datePickerStyle(.field)
                clearButton("Remove time") { draft.dueMinutes = nil }
            } else {
                Button("Add time") { draft.dueMinutes = defaultMinutes }
            }
        }
        .controlSize(.small)
    }

    private var dueDateBinding: Binding<Date> {
        Binding(
            get: { (draft.dueDay ?? DayKey(Date(), calendar: calendar)).startDate(calendar: calendar) },
            set: { draft.dueDay = DayKey($0, calendar: calendar) }
        )
    }

    private var dueTimeBinding: Binding<Date> {
        Binding(
            get: {
                let minutes = draft.dueMinutes ?? defaultMinutes
                return calendar.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: Date())!
            },
            set: {
                let c = calendar.dateComponents([.hour, .minute], from: $0)
                draft.dueMinutes = (c.hour ?? 0) * 60 + (c.minute ?? 0)
            }
        )
    }

    /// The next whole hour, so a newly added time is usually close to what's wanted.
    private var defaultMinutes: Int {
        min(calendar.component(.hour, from: Date()) + 1, 23) * 60
    }

    // MARK: - Reminder

    private enum ReminderChoice: Hashable {
        case none, atDueTime, before(Int), custom
    }

    private static let presetOffsets = [5, 10, 15, 30, 60]

    @ViewBuilder
    private var reminderControls: some View {
        VStack(alignment: .leading, spacing: 6) {
            Picker("Reminder", selection: reminderChoice) {
                Text("None").tag(ReminderChoice.none)
                Divider()
                Text("At due time").tag(ReminderChoice.atDueTime)
                ForEach(offsetChoices, id: \.self) { minutes in
                    Text(Self.offsetTitle(minutes)).tag(ReminderChoice.before(minutes))
                }
                Divider()
                Text("Custom date & time…").tag(ReminderChoice.custom)
            }
            .labelsHidden()
            .fixedSize()
            .controlSize(.small)

            if case .at = draft.reminder {
                DatePicker("Remind at", selection: customReminderBinding)
                    .labelsHidden()
                    .datePickerStyle(.field)
                    .controlSize(.small)
            } else if draft.reminder != nil && !draft.hasDueTime {
                Text("Set a due time for this reminder to fire.")
                    .font(.caption)
                    .foregroundStyle(Theme.orange)
            }
        }
    }

    /// Presets plus any non-preset offset the task already uses.
    private var offsetChoices: [Int] {
        if case .minutesBefore(let m) = draft.reminder, !Self.presetOffsets.contains(m) {
            return (Self.presetOffsets + [m]).sorted()
        }
        return Self.presetOffsets
    }

    private static func offsetTitle(_ minutes: Int) -> String {
        if minutes % 60 == 0 {
            let hours = minutes / 60
            return hours == 1 ? "1 hour before" : "\(hours) hours before"
        }
        return "\(minutes) minutes before"
    }

    private var reminderChoice: Binding<ReminderChoice> {
        Binding(
            get: {
                switch draft.reminder {
                case nil: .none
                case .atDueTime: .atDueTime
                case .minutesBefore(let m): .before(m)
                case .at: .custom
                }
            },
            set: { choice in
                switch choice {
                case .none: draft.reminder = nil
                case .atDueTime: draft.reminder = .atDueTime
                case .before(let m): draft.reminder = .minutesBefore(m)
                case .custom:
                    let start = draft.reminderDate(calendar: calendar)
                        ?? draft.dueDate(calendar: calendar)
                        ?? Date().addingTimeInterval(3600)
                    draft.reminder = .at(start)
                }
            }
        )
    }

    private var customReminderBinding: Binding<Date> {
        Binding(
            get: { if case .at(let date) = draft.reminder { date } else { Date() } },
            set: { draft.reminder = .at($0) }
        )
    }

    // MARK: - Category

    private static let newCategoryTag = UUID()

    @ViewBuilder
    private var categoryControls: some View {
        if let name = newCategoryName {
            HStack(spacing: 6) {
                TextField("New category", text: Binding(get: { name }, set: { newCategoryName = $0 }))
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 140)
                    .onSubmit(commitNewCategory)
                Button("Add", action: commitNewCategory)
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                clearButton("Cancel new category") { newCategoryName = nil }
            }
            .controlSize(.small)
        } else {
            Picker("Category", selection: Binding(
                get: { draft.categoryID },
                set: { value in
                    if value == Self.newCategoryTag { newCategoryName = "" } else { draft.categoryID = value }
                }
            )) {
                Text("None").tag(UUID?.none)
                if !model.categories.isEmpty { Divider() }
                ForEach(model.categories) { category in
                    Text(category.name).tag(UUID?.some(category.id))
                }
                Divider()
                Text("New Category…").tag(UUID?.some(Self.newCategoryTag))
            }
            .labelsHidden()
            .fixedSize()
            .controlSize(.small)
        }
    }

    private func commitNewCategory() {
        guard let name = newCategoryName, !name.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        draft.categoryID = model.createCategory(named: name)?.id
        newCategoryName = nil
    }

    // MARK: - Description & links

    private var notesEditor: some View {
        VStack(alignment: .leading, spacing: 4) {
            label("Description")
            TextEditor(text: $draft.notes)
                .font(.system(size: 13))
                .scrollContentBackground(.hidden)
                .padding(4)
                .frame(minHeight: 60, maxHeight: 140)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.05)))
        }
    }

    private var linksEditor: some View {
        VStack(alignment: .leading, spacing: 6) {
            label("Links")
            ForEach($links) { $link in
                HStack(spacing: 6) {
                    TextField("Title", text: $link.title)
                        .frame(width: 90)
                    TextField("https://…", text: $link.url)
                        .foregroundStyle(link.isValid || link.url.isEmpty ? Color.primary : Theme.red)
                    clearButton("Remove link") { links.removeAll { $0.id == link.id } }
                }
                .textFieldStyle(.roundedBorder)
                .controlSize(.small)
            }
            Button {
                links.append(LinkDraft())
            } label: {
                Label("Add link", systemImage: "plus")
            }
            .buttonStyle(.link)
            .font(.system(size: 12))
        }
    }

    // MARK: - Helpers

    private func label(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
    }

    private func clearButton(_ accessibility: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: "xmark.circle.fill")
                .foregroundStyle(.tertiary)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibility)
    }

    private func save() {
        var task = draft
        task.links = links.compactMap(\.taskLink)
        onSave(task)
    }
}

/// Editable link fields; converted to `TaskLink` on save. Invalid URLs are dropped.
private struct LinkDraft: Identifiable {
    let id = UUID()
    var title = ""
    var url = ""

    init() {}

    init(_ link: TaskLink) {
        title = link.title
        url = link.url.absoluteString
    }

    private var normalizedURL: URL? {
        let trimmed = url.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, !trimmed.contains(" ") else { return nil }
        let withScheme = trimmed.contains("://") ? trimmed : "https://\(trimmed)"
        guard let url = URL(string: withScheme), url.scheme != nil, url.host() != nil else { return nil }
        return url
    }

    var isValid: Bool { normalizedURL != nil }

    var taskLink: TaskLink? {
        guard let url = normalizedURL else { return nil }
        let name = title.trimmingCharacters(in: .whitespaces)
        return TaskLink(title: name.isEmpty ? (url.host() ?? url.absoluteString) : name, url: url)
    }
}
