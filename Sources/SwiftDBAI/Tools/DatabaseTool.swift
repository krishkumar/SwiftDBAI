// DatabaseTool.swift
// SwiftDBAI
//
// A standalone tool calling API for integrating SwiftDBAI into
// existing LLM tool calling setups (OpenAI function calling,
// Anthropic tools, Apple Foundation Models, etc.).

import Foundation
import GRDB

/// A standalone database tool for LLM tool calling integrations.
///
/// Provides everything needed to register a "query database" tool with any LLM:
/// - Tool name, description, and parameter schema for registration
/// - Schema context for the LLM's system prompt
/// - SQL execution with allowlist validation
///
/// ## Usage
///
/// ```swift
/// // 1. Create the tool
/// let tool = try await DatabaseTool(databasePath: "path/to/db.sqlite")
///
/// // 2. Get the tool definition for your LLM
/// let definition = tool.openAIFunctionDefinition
/// // Register with your OpenAI/Anthropic/etc. client...
///
/// // 3. Include schema in system prompt
/// let systemPrompt = "You are a helpful assistant.\n\n" + tool.systemPromptSnippet
///
/// // 4. When the LLM calls the tool, execute it
/// let result = try tool.execute(sql: llmGeneratedSQL)
/// // Return result.jsonString back to the LLM as the tool response
/// ```
@available(iOS 17.0, macOS 14.0, visionOS 1.0, *)
public struct DatabaseTool: Sendable {

    private let database: any DatabaseWriter
    private let allowlist: OperationAllowlist
    private let schema: DatabaseSchema

    // MARK: - Initialization

    /// Creates a database tool from a file path.
    ///
    /// - Parameters:
    ///   - databasePath: Path to the SQLite database file.
    ///   - allowlist: The set of permitted SQL operations. Defaults to read-only.
    public init(databasePath: String, allowlist: OperationAllowlist = .readOnly) async throws {
        let dbQueue = try DatabaseQueue(path: databasePath)
        self.database = dbQueue
        self.allowlist = allowlist
        self.schema = try await SchemaIntrospector.introspect(database: dbQueue)
    }

    /// Creates a database tool from an existing GRDB database connection.
    ///
    /// - Parameters:
    ///   - database: A GRDB `DatabaseWriter` (DatabaseQueue or DatabasePool).
    ///   - allowlist: The set of permitted SQL operations. Defaults to read-only.
    public init(database: any DatabaseWriter, allowlist: OperationAllowlist = .readOnly) async throws {
        self.database = database
        self.allowlist = allowlist
        self.schema = try await SchemaIntrospector.introspect(database: database)
    }

    // MARK: - Tool Definition

    /// The tool name for LLM function calling registration.
    public var name: String { "execute_sql" }

    /// The tool description for LLM function calling registration.
    public var description: String {
        "Execute a SQL query against a SQLite database. \(allowlist.describeForLLM())"
    }

    /// JSON Schema for the tool's parameters, compatible with OpenAI/Anthropic tool definitions.
    public var parametersSchema: [String: Any] {
        [
            "type": "object",
            "properties": [
                "sql": [
                    "type": "string",
                    "description": "The SQL query to execute against the database.",
                ] as [String: Any],
            ] as [String: Any],
            "required": ["sql"],
        ]
    }

    /// The database schema as a string, for including in the LLM's system prompt.
    public var schemaContext: String {
        schema.schemaDescription
    }

    /// A system prompt snippet that describes the database and how to use the tool.
    ///
    /// Include this in your LLM's system prompt so it knows the database structure
    /// and how to use the `execute_sql` tool.
    public var systemPromptSnippet: String {
        """
        You have access to a SQLite database with the following schema:

        \(schema.schemaDescription)

        \(allowlist.describeForLLM())

        Use the `execute_sql` tool to query this database. Pass a single SQL statement as the `sql` parameter.
        """
    }

    // MARK: - Execution

    /// Execute a SQL query, returning a structured ``ToolResult``.
    ///
    /// Validates the SQL against the configured allowlist before execution.
    /// This is the method to call when the LLM invokes the tool.
    ///
    /// - Parameter sql: The SQL query to execute.
    /// - Returns: A ``ToolResult`` with the query results.
    /// - Throws: ``SQLParsingError`` if the SQL is not allowed, or a database error.
    public func execute(sql: String) throws -> ToolResult {
        let queryResult = try executeRaw(sql: sql)
        return ToolResult(queryResult: queryResult)
    }

    /// Execute a SQL query and return the raw ``QueryResult``.
    ///
    /// For advanced use cases where you need the full `QueryResult.Value` types
    /// rather than the string-based ``ToolResult``.
    ///
    /// - Parameter sql: The SQL query to execute.
    /// - Returns: A ``QueryResult`` with typed values.
    /// - Throws: ``SQLParsingError`` if the SQL is not allowed, or a database error.
    public func executeRaw(sql: String) throws -> QueryResult {
        // Validate against the allowlist
        let parser = SQLQueryParser(allowlist: allowlist)
        let parsed = try parser.validate(sql)

        let startTime = CFAbsoluteTimeGetCurrent()
        let trimmed = sql.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let isSelect = trimmed.hasPrefix("SELECT") || trimmed.hasPrefix("WITH")

        if isSelect {
            let result = try database.read { db -> (columns: [String], rows: [[String: QueryResult.Value]]) in
                let statement = try db.makeStatement(sql: parsed.sql)
                let columnNames = statement.columnNames

                var rows: [[String: QueryResult.Value]] = []
                let cursor = try Row.fetchCursor(statement)
                while let row = try cursor.next() {
                    var dict: [String: QueryResult.Value] = [:]
                    for col in columnNames {
                        dict[col] = Self.extractValue(row: row, column: col)
                    }
                    rows.append(dict)
                }
                return (columns: columnNames, rows: rows)
            }

            let elapsed = CFAbsoluteTimeGetCurrent() - startTime
            return QueryResult(
                columns: result.columns,
                rows: result.rows,
                sql: parsed.sql,
                executionTime: elapsed
            )
        } else {
            let affected = try database.write { db -> Int in
                try db.execute(sql: parsed.sql)
                return db.changesCount
            }

            let elapsed = CFAbsoluteTimeGetCurrent() - startTime
            return QueryResult(
                columns: [],
                rows: [],
                sql: parsed.sql,
                executionTime: elapsed,
                rowsAffected: affected
            )
        }
    }

    // MARK: - Private Helpers

    private static func extractValue(row: Row, column: String) -> QueryResult.Value {
        let dbValue: DatabaseValue = row[column]
        switch dbValue.storage {
        case .null:
            return .null
        case .int64(let i):
            return .integer(i)
        case .double(let d):
            return .real(d)
        case .string(let s):
            return .text(s)
        case .blob(let data):
            return .blob(data)
        }
    }
}

// MARK: - OpenAI / Anthropic Compatibility

@available(iOS 17.0, macOS 14.0, visionOS 1.0, *)
extension DatabaseTool {

    /// Returns an OpenAI-compatible function definition dictionary.
    ///
    /// This can be serialized to JSON and passed directly to the OpenAI API's
    /// `tools` parameter, or adapted for Anthropic's tool definitions.
    ///
    /// ```swift
    /// let tool = try await DatabaseTool(databasePath: "db.sqlite")
    /// let definition = tool.openAIFunctionDefinition
    /// // Serialize to JSON for the API call
    /// let data = try JSONSerialization.data(withJSONObject: definition)
    /// ```
    public var openAIFunctionDefinition: [String: Any] {
        [
            "type": "function",
            "function": [
                "name": name,
                "description": description,
                "parameters": parametersSchema,
            ] as [String: Any],
        ]
    }
}
