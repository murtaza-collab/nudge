import Foundation

/// A portable JSON backup: every task (active and completed, with recurrence) plus settings.
public struct Backup: Codable, Sendable {
    public static let currentFormatVersion = 1

    public var formatVersion: Int
    public var exportedAt: Date
    public var tasks: [DailyTask]
    public var categories: [TaskCategory]
    /// App preferences by key. Values are limited to JSON-friendly types.
    public var settings: [String: SettingValue]

    public init(tasks: [DailyTask], categories: [TaskCategory] = [], settings: [String: SettingValue], exportedAt: Date = Date()) {
        self.formatVersion = Self.currentFormatVersion
        self.exportedAt = exportedAt
        self.tasks = tasks
        self.categories = categories
        self.settings = settings
    }

    private enum CodingKeys: String, CodingKey { case formatVersion, exportedAt, tasks, categories, settings }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        formatVersion = try c.decode(Int.self, forKey: .formatVersion)
        exportedAt = try c.decode(Date.self, forKey: .exportedAt)
        tasks = try c.decode([DailyTask].self, forKey: .tasks)
        categories = try c.decodeIfPresent([TaskCategory].self, forKey: .categories) ?? []
        settings = try c.decodeIfPresent([String: SettingValue].self, forKey: .settings) ?? [:]
    }

    public enum SettingValue: Codable, Hashable, Sendable {
        case bool(Bool)
        case int(Int)
        case double(Double)
        case string(String)
        /// Base64 in JSON (used for keyboard shortcuts).
        case data(Data)

        private enum CodingKeys: String, CodingKey { case type, value }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            switch try c.decode(String.self, forKey: .type) {
            case "bool": self = .bool(try c.decode(Bool.self, forKey: .value))
            case "int": self = .int(try c.decode(Int.self, forKey: .value))
            case "double": self = .double(try c.decode(Double.self, forKey: .value))
            case "string": self = .string(try c.decode(String.self, forKey: .value))
            case "data": self = .data(try c.decode(Data.self, forKey: .value))
            case let type:
                throw DecodingError.dataCorruptedError(forKey: .type, in: c, debugDescription: "Unknown setting type \(type)")
            }
        }

        public func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            switch self {
            case .bool(let v): try c.encode("bool", forKey: .type); try c.encode(v, forKey: .value)
            case .int(let v): try c.encode("int", forKey: .type); try c.encode(v, forKey: .value)
            case .double(let v): try c.encode("double", forKey: .type); try c.encode(v, forKey: .value)
            case .string(let v): try c.encode("string", forKey: .type); try c.encode(v, forKey: .value)
            case .data(let v): try c.encode("data", forKey: .type); try c.encode(v, forKey: .value)
            }
        }
    }

    // MARK: - File format

    public static func fileName(for date: Date, calendar: Calendar = .current) -> String {
        "Nudge-Backup-\(DayKey(date, calendar: calendar)).json"
    }

    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(self)
    }

    public enum ImportError: Error, Equatable, CustomStringConvertible {
        case unreadable(String)
        case newerFormat(Int)
        case invalidTasks(count: Int)

        public var description: String {
            switch self {
            case .unreadable(let detail): "This isn't a Nudge backup file (\(detail))."
            case .newerFormat(let version): "This backup was made by a newer version of the app (format \(version))."
            case .invalidTasks(let count): "The backup contains \(count) invalid task\(count == 1 ? "" : "s") (for example, without a title)."
            }
        }
    }

    /// Decodes and validates a backup file. Nothing is changed until the caller applies it.
    public static func read(from data: Data) throws -> Backup {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let backup: Backup
        do {
            backup = try decoder.decode(Backup.self, from: data)
        } catch let error as DecodingError {
            throw ImportError.unreadable(Self.describe(error))
        } catch {
            throw ImportError.unreadable(error.localizedDescription)
        }
        guard backup.formatVersion <= currentFormatVersion else { throw ImportError.newerFormat(backup.formatVersion) }
        let invalid = backup.tasks.filter { $0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.count
        guard invalid == 0 else { throw ImportError.invalidTasks(count: invalid) }
        return backup
    }

    private static func describe(_ error: DecodingError) -> String {
        switch error {
        case .keyNotFound(let key, _): "missing “\(key.stringValue)”"
        case .typeMismatch(_, let context), .valueNotFound(_, let context), .dataCorrupted(let context):
            context.codingPath.isEmpty ? "not valid JSON" : "unexpected value at \(context.codingPath.map(\.stringValue).joined(separator: "."))"
        @unknown default: "unknown format"
        }
    }

    // MARK: - Import planning

    public struct ImportPlan: Equatable, Sendable {
        /// Tasks not already present, to be added. Category ids are already mapped to local ones.
        public var newTasks: [DailyTask]
        /// Categories to create locally (those not matching an existing name).
        public var newCategories: [TaskCategory]
        /// Tasks whose id already exists locally; skipped when merging.
        public var existingCount: Int

        public var newActiveCount: Int { newTasks.filter { !$0.isCompleted }.count }
        public var newCompletedCount: Int { newTasks.filter(\.isCompleted).count }
    }

    /// What merging would do: add tasks that aren't present, never overwrite ones that are.
    /// Categories are matched by name, so "Work" in the backup joins an existing "Work".
    public func mergePlan(existingIDs: Set<UUID>, existingCategories: [TaskCategory] = []) -> ImportPlan {
        var idMap: [UUID: UUID] = [:]
        var newCategories: [TaskCategory] = []
        for category in categories {
            if let match = TaskCategory.matching(category.name, in: existingCategories + newCategories) {
                idMap[category.id] = match.id
            } else {
                newCategories.append(category)
                idMap[category.id] = category.id
            }
        }
        let new = tasks.filter { !existingIDs.contains($0.id) }.map { task in
            var task = task
            task.categoryID = task.categoryID.flatMap { idMap[$0] }
            return task
        }
        return ImportPlan(newTasks: new, newCategories: newCategories, existingCount: tasks.count - new.count)
    }
}
