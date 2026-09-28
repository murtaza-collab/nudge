import DailyCore
import SwiftUI

/// Shows what quick-add text was understood as: "Tomorrow · 3:00 PM · Every Monday · ● Work",
/// plus a ⇥ hint while a #category is being typed. Nothing is shown for a plain title.
struct ParsePreview: View {
    let text: String
    let model: TaskListModel
    var fontSize: CGFloat = 12

    var body: some View {
        let parsed = model.parse(text)
        let completion = CategoryCompletion.suggestion(for: text, in: model.categories)
        if parsed.hasDetails || completion != nil {
            HStack(spacing: 6) {
                if let day = parsed.dueDay {
                    chip(DueFormatting.dayLabel(day, today: model.today, calendar: model.calendar), symbol: "calendar")
                }
                if let minutes = parsed.dueMinutes {
                    chip(DueFormatting.time(minutes: minutes, calendar: model.calendar), symbol: "clock")
                }
                if let recurrence = parsed.recurrence {
                    chip(recurrence.summary(calendar: model.calendar), symbol: "repeat")
                }
                // While a completion is offered the tag is still being typed; don't announce a new category yet.
                if let tag = parsed.categoryTag, completion == nil {
                    if let existing = TaskCategory.matching(tag, in: model.categories) {
                        categoryChip(existing.name, color: existing.swiftUIColor)
                    } else {
                        categoryChip("New: \(TaskCategory.displayName(fromTag: tag))", color: .secondary)
                    }
                }
                Spacer(minLength: 8)
                if let completion {
                    Text("⇥ \(completion.name)")
                        .font(.system(size: fontSize - 1, weight: .medium))
                        .foregroundStyle(.secondary)
                } else {
                    Text("⌥↩ add as typed")
                        .font(.system(size: fontSize - 1))
                        .foregroundStyle(.tertiary)
                }
            }
            .accessibilityElement(children: .combine)
        }
    }

    private func categoryChip(_ name: String, color: Color) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(name).font(.system(size: fontSize, weight: .medium))
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(Capsule().fill(color.opacity(0.14)))
    }

    private func chip(_ text: String, symbol: String) -> some View {
        Label(text, systemImage: symbol)
            .font(.system(size: fontSize, weight: .medium))
            .foregroundStyle(Theme.accent)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(Capsule().fill(Theme.accent.opacity(0.12)))
    }
}

/// Completes a partly typed "#ac" to an existing category.
enum CategoryCompletion {
    /// The category Tab would complete to, if the text ends with a matching partial tag.
    static func suggestion(for text: String, in categories: [TaskCategory]) -> TaskCategory? {
        guard let prefix = NaturalLanguageParser.trailingTagPrefix(text) else { return nil }
        let matches = TaskCategory.completions(for: prefix, in: categories)
        // Nothing to suggest once the tag is already complete.
        guard let first = matches.first, TaskCategory.matchKey(first.name) != TaskCategory.matchKey(prefix) || prefix.isEmpty else { return nil }
        return first
    }

    /// `text` with its trailing partial tag replaced by the full one, or nil.
    static func complete(_ text: String, in categories: [TaskCategory]) -> String? {
        guard let category = suggestion(for: text, in: categories), let hash = text.lastIndex(of: "#") else { return nil }
        return text[..<hash] + "#" + category.name.replacingOccurrences(of: " ", with: "_") + " "
    }
}

extension View {
    /// Tab completes a partly typed #category.
    func onCategoryCompletion(_ text: Binding<String>, categories: [TaskCategory]) -> some View {
        onKeyPress(.tab, phases: .down) { _ in
            guard let completed = CategoryCompletion.complete(text.wrappedValue, in: categories) else { return .ignored }
            text.wrappedValue = completed
            return .handled
        }
    }

    /// Return adds with parsing (via `onSubmit`); Option-Return adds the text literally.
    func onOptionReturn(_ action: @escaping () -> Void) -> some View {
        onKeyPress(.return, phases: .down) { press in
            guard press.modifiers.contains(.option) else { return .ignored }
            action()
            return .handled
        }
    }
}
