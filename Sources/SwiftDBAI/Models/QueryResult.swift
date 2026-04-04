// QueryResult.swift
// SwiftDBAI
//
// Structured result from SQL query execution.

import Foundation

/// Represents the result of executing a SQL query against the database.
///
/// Contains raw row data as dictionaries, column metadata, row count,
/// the original SQL string, and execution timing.
public struct QueryResult: Sendable, Equatable {

    /// A single cell value from a query result.
    ///
    /// Wraps SQLite's dynamic value types into a type-safe, Sendable enum.
    public enum Value: Sendable, Equatable, CustomStringConvertible {
        case text(String)
        case integer(Int64)
        case real(Double)
        case blob(Data)
        case null

        public var description: String {
            switch self {
            case .text(let s): return s
            case .integer(let i): return String(i)
            case .real(let d):
                if d == d.rounded() && abs(d) < 1e15 {
                    return String(format: "%.0f", d)
                }
                return String(d)
            case .blob(let data): return "<\(data.count) bytes>"
            case .null: return "NULL"
            }
        }

        /// Returns the value as a `Double` if it is numeric, nil otherwise.
        public var doubleValue: Double? {
            switch self {
            case .integer(let i): return Double(i)
            case .real(let d): return d
            case .text(let s): return Double(s)
            default: return nil
            }
        }

        /// Returns the value as a `String` (non-nil for all cases).
        public var stringValue: String { description }

        /// Returns `true` if this value is `.null`.
        public var isNull: Bool {
            if case .null = self { return true }
            return false
        }
    }

    /// Column names in the order they appear in the result set.
    public let columns: [String]

    /// Row data as an array of dictionaries mapping column name to value.
    public let rows: [[String: Value]]

    /// Total number of rows returned.
    public var rowCount: Int { rows.count }

    /// The SQL statement that was executed.
    public let sql: String

    /// Time taken to execute the query, in seconds.
    public let executionTime: TimeInterval

    /// Number of rows affected (for INSERT/UPDATE/DELETE). Nil for SELECT.
    public let rowsAffected: Int?

    public init(
        columns: [String],
        rows: [[String: Value]],
        sql: String,
        executionTime: TimeInterval,
        rowsAffected: Int? = nil
    ) {
        self.columns = columns
        self.rows = rows
        self.sql = sql
        self.executionTime = executionTime
        self.rowsAffected = rowsAffected
    }

    // MARK: - Convenience Accessors

    /// Returns all values for a given column, in row order.
    public func values(forColumn column: String) -> [Value] {
        rows.compactMap { $0[column] }
    }

    /// Returns a compact tabular string representation of the results.
    ///
    /// Useful for embedding query results into LLM prompts.
    public var tabularDescription: String {
        guard !rows.isEmpty else {
            return "(empty result set)"
        }

        var lines: [String] = []

        // Header
        lines.append(columns.joined(separator: " | "))
        lines.append(String(repeating: "-", count: lines[0].count))

        // Rows (cap at 50 for prompt size)
        let displayRows = rows.prefix(50)
        for row in displayRows {
            let vals = columns.map { col in
                row[col]?.description ?? "NULL"
            }
            lines.append(vals.joined(separator: " | "))
        }

        if rows.count > 50 {
            lines.append("... and \(rows.count - 50) more rows")
        }

        return lines.joined(separator: "\n")
    }

    /// Returns true if the result looks like a single aggregate value
    /// (1 row, 1-3 columns, all numeric).
    public var isAggregate: Bool {
        guard rowCount == 1, columns.count <= 3 else { return false }
        let firstRow = rows[0]
        return columns.allSatisfy { col in
            firstRow[col]?.doubleValue != nil
        }
    }
}
