import DailyCore
import SwiftUI

/// Repeat control for the task editor: common presets, plus a custom rule editor.
/// Choosing a repeat on an undated task dates it today; the due date is always moved to
/// a day the rule actually includes.
struct RepeatEditor: View {
    @Binding var task: DailyTask
    let calendar: Calendar
    @State private var isCustom: Bool

    init(task: Binding<DailyTask>, calendar: Calendar) {
        _task = task
        self.calendar = calendar
        let initial = task.wrappedValue
        _isCustom = State(initialValue: initial.recurrence.map { Self.preset(for: $0, task: initial, calendar: calendar) == nil } ?? false)
    }

    private enum Choice: Hashable {
        case none, daily, weekdays, weekly, monthly, custom
    }

    private var anchorDay: DayKey { task.dueDay ?? DayKey(Date(), calendar: calendar) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("Repeat", selection: choice) {
                Text("None").tag(Choice.none)
                Divider()
                Text("Every day").tag(Choice.daily)
                Text("Every weekday").tag(Choice.weekdays)
                Text("Weekly on \(weekdayName(anchorDay.weekday(calendar: calendar)))").tag(Choice.weekly)
                Text("Monthly on the \(ordinal(anchorDay.day))").tag(Choice.monthly)
                Divider()
                Text("Custom…").tag(Choice.custom)
            }
            .labelsHidden()
            .fixedSize()
            .controlSize(.small)

            if isCustom, let rule = task.recurrence {
                customEditor(rule)
                Text(rule.summary(calendar: calendar))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Presets

    private static func preset(for rule: Recurrence, task: DailyTask, calendar: Calendar) -> Choice? {
        let day = task.dueDay ?? DayKey(Date(), calendar: calendar)
        if rule == .daily { return .daily }
        if rule == .weekdaysOnly { return .weekdays }
        if rule == Recurrence(frequency: .weekly, weekdays: [day.weekday(calendar: calendar)]) { return .weekly }
        if rule == Recurrence(frequency: .monthly, monthDay: day.day) { return .monthly }
        return nil
    }

    private var choice: Binding<Choice> {
        Binding(
            get: {
                guard let rule = task.recurrence else { return .none }
                if isCustom { return .custom }
                return Self.preset(for: rule, task: task, calendar: calendar) ?? .custom
            },
            set: { newChoice in
                isCustom = newChoice == .custom
                let day = anchorDay
                switch newChoice {
                case .none: task.recurrence = nil
                case .daily: apply(.daily)
                case .weekdays: apply(.weekdaysOnly)
                case .weekly: apply(Recurrence(frequency: .weekly, weekdays: [day.weekday(calendar: calendar)]))
                case .monthly: apply(Recurrence(frequency: .monthly, monthDay: day.day))
                case .custom: apply(task.recurrence ?? Recurrence(frequency: .weekly, weekdays: [day.weekday(calendar: calendar)]))
                }
            }
        )
    }

    /// Sets the rule and moves the due date onto a day the rule includes.
    private func apply(_ rule: Recurrence) {
        let start = anchorDay
        task.recurrence = rule
        task.dueDay = rule.firstOccurrence(onOrAfter: start, calendar: calendar)
    }

    // MARK: - Custom

    @ViewBuilder
    private func customEditor(_ rule: Recurrence) -> some View {
        HStack(spacing: 6) {
            Text("Every")
            TextField("1", value: intervalBinding(rule), format: .number)
                .frame(width: 36)
                .multilineTextAlignment(.trailing)
            Picker("Unit", selection: frequencyBinding(rule)) {
                Text(rule.interval == 1 ? "day" : "days").tag(Recurrence.Frequency.daily)
                Text(rule.interval == 1 ? "week" : "weeks").tag(Recurrence.Frequency.weekly)
                Text(rule.interval == 1 ? "month" : "months").tag(Recurrence.Frequency.monthly)
            }
            .labelsHidden()
            .fixedSize()
        }
        .controlSize(.small)
        .font(.system(size: 12))

        switch rule.frequency {
        case .daily:
            EmptyView()
        case .weekly:
            weekdayToggles(rule)
        case .monthly:
            monthlyOptions(rule)
        }
    }

    private func weekdayToggles(_ rule: Recurrence) -> some View {
        // Monday-first, matching how the rule counts weeks.
        HStack(spacing: 4) {
            ForEach([2, 3, 4, 5, 6, 7, 1], id: \.self) { weekday in
                let selected = rule.weekdays.contains(weekday)
                Button {
                    var days = Set(rule.weekdays)
                    if selected { days.remove(weekday) } else { days.insert(weekday) }
                    guard !days.isEmpty else { return } // at least one day
                    apply(Recurrence(frequency: .weekly, interval: rule.interval, weekdays: Array(days)))
                } label: {
                    Text(calendar.veryShortWeekdaySymbols[weekday - 1])
                        .font(.system(size: 11, weight: .semibold))
                        .frame(width: 24, height: 22)
                        .background(RoundedRectangle(cornerRadius: 5).fill(selected ? Theme.accent : Color.primary.opacity(0.07)))
                        .foregroundStyle(selected ? Color.white : Color.primary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(calendar.weekdaySymbols[weekday - 1])
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
    }

    @ViewBuilder
    private func monthlyOptions(_ rule: Recurrence) -> some View {
        let byPosition = rule.ordinal != nil
        Picker("Monthly by", selection: Binding(
            get: { byPosition },
            set: { usePosition in
                let day = anchorDay
                if usePosition {
                    let position = (day.day - 1) / 7 + 1
                    apply(Recurrence(frequency: .monthly, interval: rule.interval, ordinal: min(position, 4), ordinalWeekday: day.weekday(calendar: calendar)))
                } else {
                    apply(Recurrence(frequency: .monthly, interval: rule.interval, monthDay: day.day))
                }
            }
        )) {
            Text("On day \(rule.monthDay ?? anchorDay.day)").tag(false)
            Text("On a weekday").tag(true)
        }
        .pickerStyle(.radioGroup)
        .labelsHidden()
        .controlSize(.small)
        .font(.system(size: 12))

        if byPosition, let ordinalValue = rule.ordinal, let weekday = rule.ordinalWeekday {
            HStack(spacing: 6) {
                Picker("Position", selection: Binding(
                    get: { ordinalValue },
                    set: { apply(Recurrence(frequency: .monthly, interval: rule.interval, ordinal: $0, ordinalWeekday: weekday)) }
                )) {
                    ForEach([1, 2, 3, 4, -1], id: \.self) { value in
                        Text(value == -1 ? "Last" : ordinal(value)).tag(value)
                    }
                }
                Picker("Weekday", selection: Binding(
                    get: { weekday },
                    set: { apply(Recurrence(frequency: .monthly, interval: rule.interval, ordinal: ordinalValue, ordinalWeekday: $0)) }
                )) {
                    ForEach([2, 3, 4, 5, 6, 7, 1], id: \.self) { day in
                        Text(weekdayName(day)).tag(day)
                    }
                }
            }
            .labelsHidden()
            .fixedSize()
            .controlSize(.small)
        }
    }

    private func intervalBinding(_ rule: Recurrence) -> Binding<Int> {
        Binding(
            get: { rule.interval },
            set: { value in
                var updated = rule
                updated.interval = min(max(value, 1), 99)
                apply(updated)
            }
        )
    }

    private func frequencyBinding(_ rule: Recurrence) -> Binding<Recurrence.Frequency> {
        Binding(
            get: { rule.frequency },
            set: { frequency in
                let day = anchorDay
                switch frequency {
                case .daily: apply(Recurrence(frequency: .daily, interval: rule.interval))
                case .weekly: apply(Recurrence(frequency: .weekly, interval: rule.interval, weekdays: [day.weekday(calendar: calendar)]))
                case .monthly: apply(Recurrence(frequency: .monthly, interval: rule.interval, monthDay: day.day))
                }
            }
        )
    }

    private func weekdayName(_ weekday: Int) -> String {
        calendar.weekdaySymbols[weekday - 1]
    }

    private func ordinal(_ n: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .ordinal
        return formatter.string(from: NSNumber(value: n)) ?? "\(n)"
    }
}
