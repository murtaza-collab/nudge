import DailyCore
import SwiftUI

/// The grouped task list: add field, sections, empty state and undo bar.
/// The list is as tall as its content up to `maxListHeight`, then scrolls, so the
/// panel hosting it stays small when there are few tasks.
struct TaskListView: View {
    let model: TaskListModel
    var maxListHeight: CGFloat = .infinity
    /// Changing this value focuses the add field.
    var focusAddFieldRequest = 0

    @State private var newTitle = ""
    /// Show only this category's tasks; nil shows all.
    @State private var categoryFilter: UUID?
    @State private var contentHeight: CGFloat = 0
    @FocusState private var addFieldFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            addField
            if !model.categories.isEmpty {
                categoryFilterBar
            }
            Divider()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    if groups.totalCount == 0 {
                        if let category = activeFilter {
                            Text("Nothing in \(category.name).")
                                .font(.system(size: 13))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 8)
                        } else {
                            emptyToday
                        }
                    } else {
                        ForEach(TaskSection.allCases, id: \.self) { section in
                            sectionView(section)
                        }
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 12)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentHeight = $0 }
            }
            .frame(height: min(contentHeight, maxListHeight))
            .scrollBounceBehavior(.basedOnSize)
            if let undo = model.pendingUndo {
                UndoBar(action: undo, onUndo: model.undo, onDismiss: model.dismissUndo)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            if let error = model.lastError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(Theme.red)
                    .padding(8)
            }
        }
        .animation(.easeOut(duration: 0.2), value: model.pendingUndo?.id)
        .onChange(of: focusAddFieldRequest) { addFieldFocused = true }
    }

    private var addField: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: "plus")
                    .foregroundStyle(.secondary)
                TextField("What needs to be done?", text: $newTitle)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14))
                    .focused($addFieldFocused)
                    .onSubmit { add(parsing: true) }
                    .onOptionReturn { add(parsing: false) }
                    .onCategoryCompletion($newTitle, categories: model.categories)
            }
            ParsePreview(text: newTitle, model: model, fontSize: 11)
                .padding(.leading, 22)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    /// The selected filter, if that category still exists.
    private var activeFilter: TaskCategory? {
        categoryFilter.flatMap { id in model.categories.first { $0.id == id } }
    }

    private var groups: TaskGroups {
        model.groups.filtered(by: activeFilter?.id)
    }

    /// While filtered, new tasks join that category unless they name their own.
    private func add(parsing: Bool) {
        guard let task = parsing ? model.add(parsing: newTitle) : model.add(title: newTitle) else { return }
        newTitle = ""
        if let filter = activeFilter, task.categoryID == nil {
            model.update(task) { $0.categoryID = filter.id }
        }
    }

    private var categoryFilterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                filterChip("All", color: nil, selected: activeFilter == nil) { categoryFilter = nil }
                ForEach(model.categories) { category in
                    filterChip(category.name, color: category.swiftUIColor, selected: activeFilter?.id == category.id) {
                        categoryFilter = activeFilter?.id == category.id ? nil : category.id
                    }
                }
            }
            .padding(.horizontal, 14)
        }
        .padding(.bottom, 10)
    }

    private func filterChip(_ title: String, color: Color?, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if let color {
                    Circle().fill(color).frame(width: 7, height: 7)
                }
                Text(title)
                    .font(.system(size: 12, weight: selected ? .semibold : .regular))
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(Capsule().fill(selected ? Color.primary.opacity(0.12) : Color.primary.opacity(0.04)))
            .overlay(Capsule().strokeBorder(Color.primary.opacity(selected ? 0.2 : 0.08), lineWidth: 0.5))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    @ViewBuilder
    private func sectionView(_ section: TaskSection) -> some View {
        let tasks = groups[section]
        // Today is always shown so the day's status is visible; other sections only when non-empty.
        if !tasks.isEmpty || section == .today {
            VStack(alignment: .leading, spacing: 2) {
                SectionHeader(title: section.title, count: tasks.count, tint: section == .overdue ? Theme.red : .secondary)
                    .padding(.horizontal, 8)
                    .padding(.bottom, 4)
                if tasks.isEmpty {
                    Text("Nothing due today.")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                }
                ForEach(tasks) { task in
                    TaskRowView(task: task, section: section, model: model, hideCategory: activeFilter != nil)
                }
            }
        }
    }

    private var emptyToday: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionHeader(title: TaskSection.today.title)
            Text("You're clear. 🎉")
                .font(.system(size: 15, weight: .medium))
                .padding(.top, 6)
            Text("No tasks for today.")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
            Button {
                addFieldFocused = true
            } label: {
                Label("Add task", systemImage: "plus")
                    .font(.system(size: 13))
            }
            .buttonStyle(.link)
            .padding(.top, 4)
        }
        .padding(.horizontal, 8)
    }
}

private struct UndoBar: View {
    let action: TaskListModel.UndoAction
    let onUndo: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        HStack {
            Text(action.message)
                .font(.system(size: 12))
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer()
            Button("Undo", action: onUndo)
                .buttonStyle(.link)
                .font(.system(size: 12, weight: .semibold))
                .keyboardShortcut("z", modifiers: .command)
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .semibold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .accessibilityLabel("Dismiss")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
    }
}
