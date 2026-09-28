import DailyCore
import SwiftUI

/// Recently completed tasks, grouped by the day they were completed.
struct HistoryView: View {
    let model: TaskListModel
    var maxListHeight: CGFloat
    let onClearHistory: () -> Void

    @State private var contentHeight: CGFloat = 0

    private var days: [(DayKey, [DailyTask])] {
        var order: [DayKey] = []
        var byDay: [DayKey: [DailyTask]] = [:]
        for task in model.history {
            guard let completed = task.completedAt else { continue }
            let day = DayKey(completed, calendar: model.calendar)
            if byDay[day] == nil { order.append(day) }
            byDay[day, default: []].append(task)
        }
        return order.map { ($0, byDay[$0] ?? []) }
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    if model.history.isEmpty {
                        Text("Nothing completed in the last \(model.historyDays) days.")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 8)
                    }
                    ForEach(days, id: \.0) { day, tasks in
                        VStack(alignment: .leading, spacing: 2) {
                            SectionHeader(title: DueFormatting.dayLabel(day, today: model.today, calendar: model.calendar), count: tasks.count)
                                .padding(.horizontal, 8)
                                .padding(.bottom, 4)
                            ForEach(tasks) { task in
                                CompletedRowView(task: task, model: model)
                            }
                        }
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 12)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentHeight = $0 }
            }
            .frame(height: min(contentHeight, maxListHeight))
            .scrollBounceBehavior(.basedOnSize)

            Divider()
            HStack {
                Text("Last \(model.historyDays) days")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Spacer()
                if !model.history.isEmpty {
                    Button("Clear History…", action: onClearHistory)
                        .buttonStyle(.link)
                        .font(.system(size: 11))
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
        }
    }
}

/// "✓ Product meeting · Completed 12:43 PM", with Restore and Delete.
struct CompletedRowView: View {
    let task: DailyTask
    let model: TaskListModel
    var showsCompletionDay = false
    var isSelected = false

    @State private var isHovered = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.secondary)
                .font(.system(size: 14))
            VStack(alignment: .leading, spacing: 2) {
                Text(task.title)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                Text(completedText)
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }
            Spacer(minLength: 0)
            if let category = model.category(for: task) {
                CategoryLabel(category: category)
                    .frame(maxWidth: 110, alignment: .trailing)
            }
            if isHovered {
                Button("Restore") { model.restore(task) }
                    .buttonStyle(.link)
                    .font(.system(size: 11))
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(isHovered || isSelected ? Color.primary.opacity(0.06) : .clear)
        )
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .contextMenu {
            Button("Restore to Tasks") { model.restore(task) }
            Divider()
            Button("Delete", role: .destructive) { model.delete(task) }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAction(named: "Restore") { model.restore(task) }
    }

    private var completedText: String {
        guard let completed = task.completedAt else { return "Completed" }
        let time = completed.formatted(date: .omitted, time: .shortened)
        guard showsCompletionDay else { return "Completed \(time)" }
        let day = DueFormatting.dayLabel(DayKey(completed, calendar: model.calendar), today: model.today, calendar: model.calendar)
        return "Completed \(day), \(time)"
    }
}
