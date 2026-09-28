import DailyCore
import SwiftUI

/// "Good morning — Monday, September 28 — You have 4 tasks today…" with Today,
/// Overdue and Upcoming lists and an Open Tasks button.
struct BriefingView: View {
    static let width: CGFloat = 380
    private static let listLimit = 8
    private static let upcomingLimit = 4

    let model: TaskListModel
    let settings: AppSettings
    let height: BriefingHeight
    let onOpenTasks: () -> Void
    let onDismiss: () -> Void

    private var groups: TaskGroups { model.groups }
    private var upcoming: [DailyTask] { groups.tomorrow + groups.upcoming }

    /// Today's tasks in time order (untimed last), which reads better as an agenda
    /// than the panel's priority order.
    private var todayByTime: [DailyTask] {
        groups.today.enumerated().sorted { a, b in
            switch (a.element.dueMinutes, b.element.dueMinutes) {
            case let (x?, y?) where x != y: x < y
            case (_?, nil): true
            case (nil, _?): false
            default: a.offset < b.offset
            }
        }.map(\.element)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            Divider()
            if settings.briefingIncludeOverdue && !groups.overdue.isEmpty {
                section("Overdue", tint: Theme.red) {
                    ForEach(groups.overdue.prefix(Self.listLimit)) { task in
                        row(task, leading: "●", leadingColor: Theme.red, trailing: model.dueLabel(for: task, in: .overdue))
                    }
                    more(groups.overdue.count - Self.listLimit)
                }
            }
            section("Today") {
                if groups.today.isEmpty {
                    Text("Nothing due today.")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
                ForEach(todayByTime.prefix(Self.listLimit)) { task in
                    row(task, leading: task.dueMinutes.map { DueFormatting.time(minutes: $0, calendar: model.calendar) } ?? "",
                        leadingColor: model.isPastDue(task) ? Theme.red : .secondary, trailing: nil)
                }
                more(groups.today.count - Self.listLimit)
            }
            if settings.briefingIncludeUpcoming && !upcoming.isEmpty {
                section("Upcoming") {
                    ForEach(upcoming.prefix(Self.upcomingLimit)) { task in
                        row(task, leading: "", leadingColor: .secondary, trailing: model.dueLabel(for: task, in: .upcoming))
                    }
                    more(upcoming.count - Self.upcomingLimit)
                }
            }
            HStack {
                Spacer()
                Button("Dismiss", action: onDismiss)
                    .keyboardShortcut(.cancelAction)
                Button("Open Tasks", action: onOpenTasks)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(22)
        .frame(width: Self.width, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height.value = $0 }
        .frame(maxHeight: .infinity, alignment: .top)
        .background(VisualEffectBackground(material: .popover))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.primary.opacity(0.1), lineWidth: 0.5))
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(BriefingPolicy.greeting(hour: model.calendar.component(.hour, from: model.now)).uppercased())
                .font(.system(size: 11, weight: .semibold))
                .tracking(0.8)
                .foregroundStyle(.secondary)
            Text(model.now.formatted(.dateTime.weekday(.wide).month(.wide).day()))
                .font(.system(size: 20, weight: .semibold))
            Text(summary)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }

    /// "4 tasks today · 1 overdue · 3 upcoming"
    private var summary: String {
        var parts = ["\(groups.today.count) task\(groups.today.count == 1 ? "" : "s") today"]
        if settings.briefingIncludeOverdue && !groups.overdue.isEmpty { parts.append("\(groups.overdue.count) overdue") }
        if settings.briefingIncludeUpcoming && !upcoming.isEmpty { parts.append("\(upcoming.count) upcoming") }
        return parts.joined(separator: " · ")
    }

    private func section<Content: View>(_ title: String, tint: Color = .secondary, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionHeader(title: title, tint: tint)
            content()
        }
    }

    private func row(_ task: DailyTask, leading: String, leadingColor: Color, trailing: String?) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(leading)
                .font(.system(size: 12).monospacedDigit())
                .foregroundStyle(leadingColor)
                .frame(width: 62, alignment: .trailing)
            Text(task.title)
                .font(.system(size: 13))
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 4)
            if let trailing {
                Text(trailing)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func more(_ count: Int) -> some View {
        if count > 0 {
            Text("+ \(count) more")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .padding(.leading, 72)
        }
    }
}
