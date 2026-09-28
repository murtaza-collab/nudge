import DailyCore
import SwiftUI

/// ⌘K search across active and completed tasks. ↑↓ to move, Return to edit, Esc to go back.
struct SearchView: View {
    let model: TaskListModel
    @Bindable var state: PanelState
    var maxListHeight: CGFloat

    @State private var selection = 0
    @State private var contentHeight: CGFloat = 0
    @FocusState private var focused: Bool

    private var results: [DailyTask] { model.search(state.searchQuery) }

    var body: some View {
        let results = self.results
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search tasks…", text: $state.searchQuery)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14))
                    .focused($focused)
                    .onKeyPress(.downArrow) {
                        selection = min(selection + 1, max(results.count - 1, 0))
                        return .handled
                    }
                    .onKeyPress(.upArrow) {
                        selection = max(selection - 1, 0)
                        return .handled
                    }
                    .onSubmit { open(results) }
                Text("esc")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Color.primary.opacity(0.15)))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            Divider()

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        if state.searchQuery.trimmingCharacters(in: .whitespaces).isEmpty {
                            hint
                        } else if results.isEmpty {
                            Text("No tasks match “\(state.searchQuery)”.")
                                .font(.system(size: 13))
                                .foregroundStyle(.secondary)
                                .padding(8)
                        }
                        ForEach(Array(results.enumerated()), id: \.element.id) { index, task in
                            Group {
                                if task.isCompleted {
                                    CompletedRowView(task: task, model: model, showsCompletionDay: true, isSelected: index == selection)
                                } else {
                                    // .upcoming shows the full due label ("Tomorrow · 3:00 PM").
                                    TaskRowView(task: task, section: .upcoming, model: model, editRequest: state.editRequest, isSelected: index == selection)
                                }
                            }
                            .id(task.id)
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 10)
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentHeight = $0 }
                }
                .frame(height: min(contentHeight, maxListHeight))
                .scrollBounceBehavior(.basedOnSize)
                .onChange(of: selection) {
                    if results.indices.contains(selection) { proxy.scrollTo(results[selection].id) }
                }
            }
        }
        .onChange(of: state.searchQuery) { selection = 0 }
        .onAppear { focused = true }
    }

    private var hint: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Search titles, descriptions and links, including completed tasks.")
            Text("Try a date (“tomorrow”, “oct 1”) or a category (“#work”).")
        }
        .font(.system(size: 12))
        .foregroundStyle(.secondary)
        .padding(8)
    }

    private func open(_ results: [DailyTask]) {
        guard results.indices.contains(selection) else { return }
        let task = results[selection]
        if !task.isCompleted {
            state.editRequest = EditRequest(taskID: task.id)
        }
    }
}
