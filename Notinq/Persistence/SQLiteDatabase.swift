import Foundation
import SQLite3

public enum SQLiteValue: Sendable {
    case null
    case text(String)
    case integer(Int64)
    case real(Double)
}

public struct SQLiteRow: Sendable {
    private let storage: [String: String?]

    init(storage: [String: String?]) {
        self.storage = storage
    }

    public func string(_ key: String) -> String? {
        storage[key] ?? nil
    }

    public func int(_ key: String) -> Int? {
        guard let value = string(key) else { return nil }
        return Int(value)
    }

    public func double(_ key: String) -> Double? {
        guard let value = string(key) else { return nil }
        return Double(value)
    }
}

final class SQLiteDatabase {
    enum DatabaseError: LocalizedError {
        case openFailed(String)
        case prepareFailed(String)
        case stepFailed(String)
        case bindFailed(String)

        var errorDescription: String? {
            switch self {
            case .openFailed(let message), .prepareFailed(let message), .stepFailed(let message), .bindFailed(let message):
                return message
            }
        }
    }

    private let url: URL
    private var handle: OpaquePointer?
    private let queue = DispatchQueue(label: "notinq.sqlite.database", qos: .utility)
    private static let memoryURL = URL(fileURLWithPath: ":memory:")

    init(url: URL = SQLiteDatabase.defaultURL()) throws {
        self.url = url
        try open()
    }

    static func makeDefault() -> SQLiteDatabase {
        let preferredURLs = candidateDefaultURLs()
        for url in preferredURLs {
            if let database = try? SQLiteDatabase(url: url) {
                return database
            }
        }

        return try! SQLiteDatabase(url: memoryURL)
    }

    deinit {
        if let handle {
            sqlite3_close_v2(handle)
        }
    }

    func execute(_ sql: String, bindings: [SQLiteValue] = []) throws {
        try queue.sync {
            let statement = try prepare(sql)
            defer { sqlite3_finalize(statement) }
            try bind(bindings, to: statement)
            guard sqlite3_step(statement) == SQLITE_DONE else {
                throw DatabaseError.stepFailed(lastErrorMessage)
            }
        }
    }

    func fetch(_ sql: String, bindings: [SQLiteValue] = []) throws -> [SQLiteRow] {
        try queue.sync {
            let statement = try prepare(sql)
            defer { sqlite3_finalize(statement) }
            try bind(bindings, to: statement)

            var rows: [SQLiteRow] = []
            while true {
                let result = sqlite3_step(statement)
                if result == SQLITE_ROW {
                    rows.append(readRow(from: statement))
                } else if result == SQLITE_DONE {
                    break
                } else {
                    throw DatabaseError.stepFailed(lastErrorMessage)
                }
            }
            return rows
        }
    }

    func transaction(_ block: () throws -> Void) throws {
        try execute("BEGIN TRANSACTION")
        do {
            try block()
            try execute("COMMIT")
        } catch {
            try? execute("ROLLBACK")
            throw error
        }
    }

    var isOpen: Bool {
        handle != nil
    }

    private func open() throws {
        if url != Self.memoryURL {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        }
        let result = sqlite3_open(url.path, &handle)
        guard result == SQLITE_OK, handle != nil else {
            throw DatabaseError.openFailed(lastErrorMessage)
        }
        try execute("PRAGMA foreign_keys = ON")
        _ = try fetch("PRAGMA journal_mode = WAL")
        try execute("PRAGMA synchronous = NORMAL")
    }

    private func prepare(_ sql: String) throws -> OpaquePointer {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw DatabaseError.prepareFailed(lastErrorMessage)
        }
        return statement
    }

    private func bind(_ bindings: [SQLiteValue], to statement: OpaquePointer) throws {
        guard bindings.isEmpty == false else { return }
        for (index, binding) in bindings.enumerated() {
            let parameterIndex = Int32(index + 1)
            let result: Int32
            switch binding {
            case .null:
                result = sqlite3_bind_null(statement, parameterIndex)
            case .text(let value):
                result = sqlite3_bind_text(statement, parameterIndex, value, -1, SQLITE_TRANSIENT)
            case .integer(let value):
                result = sqlite3_bind_int64(statement, parameterIndex, value)
            case .real(let value):
                result = sqlite3_bind_double(statement, parameterIndex, value)
            }
            guard result == SQLITE_OK else {
                throw DatabaseError.bindFailed(lastErrorMessage)
            }
        }
    }

    private func readRow(from statement: OpaquePointer) -> SQLiteRow {
        let columnCount = sqlite3_column_count(statement)
        var storage: [String: String?] = [:]
        storage.reserveCapacity(Int(columnCount))

        for index in 0..<columnCount {
            let columnName = String(cString: sqlite3_column_name(statement, index))
            let columnType = sqlite3_column_type(statement, index)
            switch columnType {
            case SQLITE_INTEGER:
                storage[columnName] = String(sqlite3_column_int64(statement, index))
            case SQLITE_FLOAT:
                storage[columnName] = String(sqlite3_column_double(statement, index))
            case SQLITE_TEXT:
                if let cString = sqlite3_column_text(statement, index) {
                    storage[columnName] = String(cString: cString)
                } else {
                    storage[columnName] = nil
                }
            case SQLITE_NULL:
                storage[columnName] = nil
            default:
                storage[columnName] = nil
            }
        }

        return SQLiteRow(storage: storage)
    }

    private var lastErrorMessage: String {
        guard let handle else { return "Unable to access SQLite handle." }
        return String(cString: sqlite3_errmsg(handle))
    }

    private static func defaultURL() -> URL {
        let baseURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return baseURL
            .appendingPathComponent("Notinq", isDirectory: true)
            .appendingPathComponent("notinq.sqlite", isDirectory: false)
    }

    private static func candidateDefaultURLs() -> [URL] {
        let temporaryBase = FileManager.default.temporaryDirectory
            .appendingPathComponent("Notinq", isDirectory: true)
            .appendingPathComponent("notinq.sqlite", isDirectory: false)

        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil {
            return [temporaryBase, defaultURL()]
        }

        return [defaultURL(), temporaryBase]
    }
}

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
