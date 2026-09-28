import Foundation
import SQLite3

public enum SQLValue: Hashable, Sendable {
    case null
    case integer(Int64)
    case real(Double)
    case text(String)
}

public struct SQLiteError: Error, CustomStringConvertible {
    public let code: Int32
    public let message: String
    public var description: String { "SQLite error \(code): \(message)" }
}

public struct SQLRow {
    fileprivate let values: [String: SQLValue]

    public subscript(column: String) -> SQLValue { values[column] ?? .null }

    public func string(_ column: String) -> String? {
        if case .text(let s) = self[column] { return s }
        return nil
    }

    public func int(_ column: String) -> Int? {
        if case .integer(let i) = self[column] { return Int(i) }
        return nil
    }

    public func double(_ column: String) -> Double? {
        switch self[column] {
        case .real(let d): d
        case .integer(let i): Double(i)
        default: nil
        }
    }
}

/// Minimal wrapper over the system SQLite library. All access is serialized by a lock.
public final class SQLiteDatabase: @unchecked Sendable {
    private var handle: OpaquePointer?
    private let lock = NSRecursiveLock()
    /// File path, or nil for an in-memory database.
    public let path: String?

    private static let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    /// Opens (creating if needed) the database at `path`. Pass ":memory:" for an in-memory database.
    public init(path: String) throws {
        self.path = path == ":memory:" ? nil : path
        let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX
        let rc = sqlite3_open_v2(path, &handle, flags, nil)
        guard rc == SQLITE_OK else {
            let message = handle.map { String(cString: sqlite3_errmsg($0)) } ?? "unable to open"
            sqlite3_close(handle)
            throw SQLiteError(code: rc, message: message)
        }
        try execute("PRAGMA journal_mode = WAL; PRAGMA foreign_keys = ON;")
    }

    deinit {
        sqlite3_close(handle)
    }

    /// Executes one or more statements without bindings or results.
    public func execute(_ sql: String) throws {
        try locked {
            var error: UnsafeMutablePointer<CChar>?
            let rc = sqlite3_exec(handle, sql, nil, nil, &error)
            if rc != SQLITE_OK {
                let message = error.map { String(cString: $0) } ?? "unknown"
                sqlite3_free(error)
                throw SQLiteError(code: rc, message: message)
            }
        }
    }

    public func run(_ sql: String, _ bindings: [SQLValue] = []) throws {
        _ = try query(sql, bindings)
    }

    public func query(_ sql: String, _ bindings: [SQLValue] = []) throws -> [SQLRow] {
        try locked {
            var statement: OpaquePointer?
            try check(sqlite3_prepare_v2(handle, sql, -1, &statement, nil))
            defer { sqlite3_finalize(statement) }

            for (index, value) in bindings.enumerated() {
                let position = Int32(index + 1)
                switch value {
                case .null: try check(sqlite3_bind_null(statement, position))
                case .integer(let i): try check(sqlite3_bind_int64(statement, position, i))
                case .real(let d): try check(sqlite3_bind_double(statement, position, d))
                case .text(let s): try check(sqlite3_bind_text(statement, position, s, -1, Self.transient))
                }
            }

            var rows: [SQLRow] = []
            while true {
                let rc = sqlite3_step(statement)
                if rc == SQLITE_DONE { break }
                guard rc == SQLITE_ROW else { try check(rc); break }
                var values: [String: SQLValue] = [:]
                for column in 0..<sqlite3_column_count(statement) {
                    let name = String(cString: sqlite3_column_name(statement, column))
                    switch sqlite3_column_type(statement, column) {
                    case SQLITE_INTEGER: values[name] = .integer(sqlite3_column_int64(statement, column))
                    case SQLITE_FLOAT: values[name] = .real(sqlite3_column_double(statement, column))
                    case SQLITE_TEXT: values[name] = .text(String(cString: sqlite3_column_text(statement, column)))
                    default: values[name] = .null
                    }
                }
                rows.append(SQLRow(values: values))
            }
            return rows
        }
    }

    /// Runs `body` inside a transaction, rolling back if it throws.
    public func transaction<T>(_ body: () throws -> T) throws -> T {
        try locked {
            try execute("BEGIN IMMEDIATE")
            do {
                let result = try body()
                try execute("COMMIT")
                return result
            } catch {
                try? execute("ROLLBACK")
                throw error
            }
        }
    }

    public var userVersion: Int {
        get throws { try query("PRAGMA user_version").first?.int("user_version") ?? 0 }
    }

    public func setUserVersion(_ version: Int) throws {
        try execute("PRAGMA user_version = \(version)")
    }

    private func check(_ rc: Int32) throws {
        guard rc == SQLITE_OK || rc == SQLITE_ROW || rc == SQLITE_DONE else {
            throw SQLiteError(code: rc, message: String(cString: sqlite3_errmsg(handle)))
        }
    }

    private func locked<T>(_ body: () throws -> T) rethrows -> T {
        lock.lock()
        defer { lock.unlock() }
        return try body()
    }
}
