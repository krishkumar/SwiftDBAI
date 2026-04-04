// ToolResult.swift
// SwiftDBAI
//
// Structured result for tool calling responses.

import Foundation

/// A structured result from executing a SQL query via ``DatabaseTool``,
/// designed for returning to an LLM as a tool call response.
///
/// Provides multiple output formats:
/// - ``jsonString`` for returning to the LLM as a tool response
/// - ``markdownTable`` for display in UI
/// - ``textSummary`` for plain text output
public struct ToolResult: Sendable, Codable, Equatable {

    /// Column names in the order they appear in the result set.
    public let columns: [String]

    /// Row data as an array of dictionaries mapping column name to string value.
    /// All values are converted to strings for reliable JSON serialization.
    public let rows: [[String: String]]

    /// Total number of rows returned.
    public let rowCount: Int

    /// Time taken to execute the query, in seconds.
    public let executionTime: TimeInterval

    /// The SQL statement that was executed.
    public let sql: String

    public init(
        columns: [String],
        rows: [[String: String]],
        rowCount: Int,
        executionTime: TimeInterval,
        sql: String
    ) {
        self.columns = columns
        self.rows = rows
        self.rowCount = rowCount
        self.executionTime = executionTime
        self.sql = sql
    }

    /// Creates a ``ToolResult`` from a ``QueryResult``.
    init(queryResult: QueryResult) {
        self.columns = queryResult.columns
        self.rows = queryResult.rows.map { row in
            var stringRow: [String: String] = [:]
            for (key, value) in row {
                stringRow[key] = value.description
            }
            return stringRow
        }
        self.rowCount = queryResult.rowCount
        self.executionTime = queryResult.executionTime
        self.sql = queryResult.sql
    }

    // MARK: - Output Formats

    /// Formats the result as a JSON string for returning to the LLM as a tool response.
    public var jsonString: String {
        let payload: [String: Any] = [
            "columns": columns,
            "rows": rows,
            "row_count": rowCount,
            "execution_time_seconds": executionTime,
            "sql": sql,
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys]),
              let str = String(data: data, encoding: .utf8) else {
            return "{\"error\": \"Failed to serialize result\"}"
        }
        return str
    }

    /// Formats the result as a markdown table for display.
    public var markdownTable: String {
        guard !rows.isEmpty else {
            return "_No results._"
        }

        var lines: [String] = []

        // Header
        lines.append("| " + columns.joined(separator: " | ") + " |")
        lines.append("| " + columns.map { _ in "---" }.joined(separator: " | ") + " |")

        // Rows
        for row in rows {
            let vals = columns.map { row[$0] ?? "NULL" }
            lines.append("| " + vals.joined(separator: " | ") + " |")
        }

        return lines.joined(separator: "\n")
    }

    /// Formats a plain text summary of the result.
    public var textSummary: String {
        if rows.isEmpty {
            return "Query returned no results. (\(String(format: "%.3f", executionTime))s)"
        }
        return "Query returned \(rowCount) row\(rowCount == 1 ? "" : "s") with columns: \(columns.joined(separator: ", ")). (\(String(format: "%.3f", executionTime))s)"
    }
}
