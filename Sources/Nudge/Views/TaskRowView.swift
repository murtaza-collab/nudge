import AppKit
import DailyCore
import SwiftUI

/// One task: checkbox completes, clicking anywhere else opens the editor, right-click for actions.
struct TaskRowView: View {
    let task: DailyTask
    let section: TaskSection
    let model: TaskListModel
    /// True when the list is already filtered to this task's category.
    var hideCategory = false
    /// Opens the editor when it names this task.
    var editRequest: EditRequest?
    /// Keyboard selection highlight (search results).
    var isSelected = false

    @State private var isEditing = false
    @State private var isHovered = false
    @State private var isCompleting = false

    private var pastDue: Bool { model.isPastDue(task) }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            checkbox
            VStack(alignment: .leading, spacing: 2) {
                Text(task.title)
                    .font(.system(size: 13))
                    .lineLimit(2)
                    .strikethrough(isCompleting, color: .secondary)
                    .foregroundStyle(isCompleting ? .secondary : .primary)
                metadata
            }
            Spacer(minLength: 0)
            if let category = model.category(for: task), !hideCategory {
                CategoryLabel(category: category)
                    .frame(maxWidth: 110, alignment: .trailing)
            }
            if let color = task.priority.color, task.priority >= .high {
                Image(systemName: "flag.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(color)
                    .accessibilityLabel("\(task.priority.title) priority")
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(isHovered || isEditing || isSelected ? Color.primary.opacity(0.06) : .clear)
        )
        .onChange(of: editRequest) {
            if editRequest?.taskID == task.id { isEditing = true }
        }
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .onTapGesture { isEditing = true }
        .popover(isPresented: $isEditing, arrowEdge: .trailing) {
            TaskEditorView(task: task, model: model) { edited in
                model.save(edited)
                isEditing = false
            } onCancel: {
                isEditing = false
            }
        }
        .contextMenu { contextMenu }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityDescription)
        .accessibilityHint("Space completes, Return edits")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityAction(named: "Complete") { complete() }
        .accessibilityAction(named: "Edit") { isEditing = true }
    }

    /// One sentence for VoiceOver: "Fix payments API, overdue, due Yesterday · 3:00 PM, High priority, category Work".
    private var accessibilityDescription: String {
        var parts = [task.title]
        if pastDue { parts.append("overdue") }
        if let due = DueFormatting.dueLabel(for: task, today: model.today, calendar: model.calendar) {
            parts.append("due \(due.replacingOccurrences(of: " · ", with: " at "))")
        }
        if task.priority != .none { parts.append("\(task.priority.title) priority") }
        if let category = model.category(for: task) { parts.append("category \(category.name)") }
        if let recurrence = task.recurrence { parts.append(recurrence.summary(calendar: model.calendar)) }
        if task.notificationsMuted { parts.append("notifications off") }
        return parts.joined(separator: ", ")
    }

    // MARK: - Pieces

    private var checkbox: some View {
        Button(action: complete) {
            ZStack {
                Circle()
                    .strokeBorder(task.priority.color ?? Color.secondary.opacity(0.6), lineWidth: 1.5)
                if isCompleting {
                    Circle().fill(Theme.accent)
                    Image(systemName: "checkmark")
                        .font(.system(size: 8, weight: .heavy))
                        .foregroundStyle(.white)
                }
            }
            .frame(width: 16, height: 16)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + 4 }
        .accessibilityLabel("Complete \(task.title)")
    }

    @ViewBuilder
    private var metadata: some View {
        let due = model.dueLabel(for: task, in: section)
        let hasIcons = task.reminder != nil || task.notificationsMuted || task.recurrence != nil || !task.notes.isEmpty || !task.links.isEmpty
        if due != nil || hasIcons {
            HStack(spacing: 6) {
                if let due {
                    Text(due)
                        .foregroundStyle(pastDue ? Theme.red : Color.secondary)
                        .lineLimit(1)
                        .fixedSize()
                }
                if let recurrence = task.recurrence {
                    Image(systemName: "repeat")
                        .help(recurrence.summary(calendar: model.calendar))
                        .accessibilityLabel(recurrence.summary(calendar: model.calendar))
                }
                if task.reminder != nil || task.notificationsMuted {
                    Image(systemName: task.notificationsMuted ? "bell.slash" : "bell")
                        .accessibilityLabel(task.notificationsMuted ? "Notifications off" : "Reminder set")
                }
                if !task.notes.isEmpty {
                    Image(systemName: "text.alignleft").accessibilityLabel("Has description")
                }
                if !task.links.isEmpty {
                    Image(systemName: "link").accessibilityLabel("\(task.links.count) links")
                }
            }
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            .monospacedDigit()
        }
    }

    @ViewBuilder
    private var contextMenu: some View {
        Button("Edit…") { isEditing = true }
        Button("Complete") { complete() }
        if task.recurrence != nil && task.dueDay != nil {
            Button("Skip This Occurrence") { model.skipOccurrence(task) }
        }
        Divider()
        Menu("Due") {
            Button("Today") { reschedule(to: model.today) }
            Button("Tomorrow") { reschedule(to: model.today.adding(days: 1, calendar: model.calendar)) }
            Button("Next Monday") { reschedule(to: nextMonday) }
            Divider()
            Button("No Date") { reschedule(to: nil) }
        }
        if !model.categories.isEmpty {
            Menu("Category") {
                ForEach(model.categories) { category in
                    Toggle(category.name, isOn: Binding(
                        get: { task.categoryID == category.id },
                        set: { on in model.update(task) { $0.categoryID = on ? category.id : nil } }
                    ))
                }
                if task.categoryID != nil {
                    Divider()
                    Button("None") { model.update(task) { $0.categoryID = nil } }
                }
            }
        }
        Menu("Priority") {
            ForEach(Priority.allCases.reversed(), id: \.self) { priority in
                Toggle(priority.title, isOn: Binding(
                    get: { task.priority == priority },
                    set: { _ in model.update(task) { $0.priority = priority } }
                ))
            }
        }
        if task.reminder != nil || task.hasDueTime {
            Button(task.notificationsMuted ? "Resume Notifications" : "Don't Notify Again") {
                model.update(task) { $0.notificationsMuted.toggle() }
            }
        }
        if !task.links.isEmpty {
            Menu("Open Link") {
                ForEach(task.links, id: \.self) { link in
                    Button(link.title) { NSWorkspace.shared.open(link.url) }
                }
            }
        }
        Divider()
        Button("Delete", role: .destructive) { model.delete(task) }
    }

    // MARK: - Actions

    private func complete() {
        guard !isCompleting else { return }
        withAnimation(.easeOut(duration: 0.15)) { isCompleting = true }
        // Brief pause so the checkmark registers before the row disappears.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            withAnimation(.easeOut(duration: 0.2)) { model.complete(task) }
        }
    }

    private func reschedule(to day: DayKey?) {
        model.update(task) {
            $0.dueDay = day
            if day == nil { $0.dueMinutes = nil }
        }
    }

    private var nextMonday: DayKey {
        let weekday = model.calendar.component(.weekday, from: model.now) // 1 = Sunday, 2 = Monday
        let days = (9 - weekday) % 7
        return model.today.adding(days: days == 0 ? 7 : days, calendar: model.calendar)
    }
}
