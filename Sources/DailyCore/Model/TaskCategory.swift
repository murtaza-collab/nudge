import Foundation

/// An optional grouping such as Work, Freelance or Personal. A task has at most one.
public struct TaskCategory: Identifiable, Hashable, Codable, Sendable {
    public var id: UUID
    public var name: String
    /// Index into the app's color palette.
    public var color: Int
    public var createdAt: Date

    public static let paletteSize = 8

    public init(id: UUID = UUID(), name: String, color: Int, createdAt: Date = Date()) {
        self.id = id
        self.name = name
        self.color = color
        self.createdAt = createdAt
    }

    /// "#freelance_acme" → "Freelance acme". Underscores become spaces; the first letter is capitalized.
    public static func displayName(fromTag tag: String) -> String {
        let spaced = tag.replacingOccurrences(of: "_", with: " ").trimmingCharacters(in: .whitespaces)
        return spaced.prefix(1).uppercased() + spaced.dropFirst()
    }

    /// Case, spaces, dashes and underscores are ignored, so "#personalstuff" matches "Personal Stuff".
    public static func matchKey(_ name: String) -> String {
        name.lowercased().filter { !$0.isWhitespace && $0 != "_" && $0 != "-" }
    }

    /// The first category whose name matches `tag`, if any.
    public static func matching(_ tag: String, in categories: [TaskCategory]) -> TaskCategory? {
        let key = matchKey(tag)
        return categories.first { matchKey($0.name) == key }
    }

    /// Categories whose name starts with `prefix` (for #-completion).
    public static func completions(for prefix: String, in categories: [TaskCategory]) -> [TaskCategory] {
        let key = matchKey(prefix)
        return categories.filter { matchKey($0.name).hasPrefix(key) }
    }
}

extension TaskGroups {
    /// Only tasks in `category`; nil returns everything.
    public func filtered(by category: UUID?) -> TaskGroups {
        guard let category else { return self }
        var result = TaskGroups()
        result.overdue = overdue.filter { $0.categoryID == category }
        result.today = today.filter { $0.categoryID == category }
        result.tomorrow = tomorrow.filter { $0.categoryID == category }
        result.upcoming = upcoming.filter { $0.categoryID == category }
        return result
    }
}
