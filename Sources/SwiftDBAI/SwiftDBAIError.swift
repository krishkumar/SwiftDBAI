// SwiftDBAIError.swift
// SwiftDBAI
//
// Unified error type for the SwiftDBAI package.

import Foundation

/// The top-level error type for SwiftDBAI operations.
///
/// `SwiftDBAIError` provides a single, typed error surface that covers
/// every failure mode a consumer of SwiftDBAI may encounter — from invalid
/// SQL and LLM failures to schema mismatches and safety violations.
///
/// Every case includes a user-friendly `localizedDescription` suitable for
/// displaying directly in a chat interface.
public enum SwiftDBAIError: Error, LocalizedError, Sendable, Equatable {

    // MARK: - SQL Errors

    /// No SQL statement could be extracted from the LLM response.
    case noSQLGenerated

    /// The generated SQL is syntactically invalid or failed execution.
    case invalidSQL(sql: String, reason: String)

    /// The SQL uses an operation (e.g. DELETE) not in the developer's allowlist.
    case operationNotAllowed(operation: String)

    /// Multiple SQL statements were generated but only single-statement execution is supported.
    case multipleStatementsNotSupported

    /// A dangerous SQL keyword (DROP, ALTER, TRUNCATE) was detected.
    case dangerousOperationBlocked(keyword: String)

    // MARK: - LLM Errors

    /// The LLM failed to produce a response.
    case llmFailure(reason: String)

    /// The LLM response could not be parsed into an actionable result.
    case llmResponseUnparseable(response: String)

    /// The LLM request timed out.
    case llmTimeout(seconds: TimeInterval)

    // MARK: - Schema Errors

    /// Schema introspection of the database failed.
    case schemaIntrospectionFailed(reason: String)

    /// The generated SQL references a table that does not exist in the schema.
    case tableNotFound(tableName: String)

    /// The generated SQL references a column that does not exist on the given table.
    case columnNotFound(columnName: String, tableName: String)

    /// The database schema is empty (no user tables found).
    case emptySchema

    // MARK: - Safety & Validation Errors

    /// A destructive operation requires explicit user confirmation before execution.
    case confirmationRequired(sql: String, operation: String)

    /// A mutation targets a table not in the allowed mutation tables.
    case tableNotAllowedForMutation(tableName: String, operation: String)

    /// A custom query validator rejected the query.
    case queryRejected(reason: String)

    // MARK: - Database Errors

    /// The underlying database operation failed.
    case databaseError(reason: String)

    /// The query exceeded the configured execution timeout.
    case queryTimedOut(seconds: TimeInterval)

    // MARK: - Configuration Errors

    /// The engine has not been configured correctly.
    case configurationError(reason: String)

    // MARK: - Error Classification

    /// Whether this error represents a safety/permissions issue (not a bug).
    public var isSafetyError: Bool {
        switch self {
        case .operationNotAllowed, .dangerousOperationBlocked,
             .confirmationRequired, .tableNotAllowedForMutation, .queryRejected:
            return true
        default:
            return false
        }
    }

    /// Whether this error is recoverable by rephrasing the user's question.
    public var isRecoverable: Bool {
        switch self {
        case .noSQLGenerated, .llmResponseUnparseable, .invalidSQL,
             .tableNotFound, .columnNotFound:
            return true
        default:
            return false
        }
    }

    /// Whether this error requires user action (e.g. confirmation).
    public var requiresUserAction: Bool {
        if case .confirmationRequired = self { return true }
        return false
    }

    // MARK: - LocalizedError

    public var errorDescription: String? {
        switch self {
        // SQL
        case .noSQLGenerated:
            return "I couldn't generate a SQL query from your request. Could you rephrase your question?"
        case .invalidSQL(let sql, let reason):
            return "The generated query is invalid — \(reason). Query: \(sql)"
        case .operationNotAllowed(let operation):
            return "The \(operation.uppercased()) operation is not allowed by the current configuration."
        case .multipleStatementsNotSupported:
            return "Only single SQL statements are supported. Please ask one question at a time."
        case .dangerousOperationBlocked(let keyword):
            return "The \(keyword.uppercased()) operation is blocked for safety. This operation is never allowed."

        // LLM
        case .llmFailure(let reason):
            return "The language model encountered an error: \(reason)"
        case .llmResponseUnparseable(let response):
            return "I received a response but couldn't understand it. Raw response: \(response.prefix(200))"
        case .llmTimeout(let seconds):
            return "The language model did not respond within \(Int(seconds)) seconds. Please try again."

        // Schema
        case .schemaIntrospectionFailed(let reason):
            return "Failed to read the database schema: \(reason)"
        case .tableNotFound(let tableName):
            return "The table '\(tableName)' does not exist in this database."
        case .columnNotFound(let columnName, let tableName):
            return "The column '\(columnName)' does not exist on table '\(tableName)'."
        case .emptySchema:
            return "This database has no tables. There's nothing to query yet."

        // Safety
        case .confirmationRequired(let sql, let operation):
            return "The \(operation.uppercased()) operation requires your confirmation before running: \(sql)"
        case .tableNotAllowedForMutation(let tableName, let operation):
            return "The \(operation.uppercased()) operation is not allowed on table '\(tableName)'."
        case .queryRejected(let reason):
            return "Query rejected: \(reason)"

        // Database
        case .databaseError(let reason):
            return "A database error occurred: \(reason)"
        case .queryTimedOut(let seconds):
            return "The query timed out after \(Int(seconds)) seconds. Try a simpler query."

        // Configuration
        case .configurationError(let reason):
            return "Configuration error: \(reason)"
        }
    }
}

// MARK: - Conversion from SQLParsingError

extension SQLParsingError {
    /// Maps a ``SQLParsingError`` to the corresponding ``SwiftDBAIError`` case.
    ///
    /// - Parameter rawResponse: The raw LLM response text (used for context in `.noSQLFound`).
    /// - Returns: A ``SwiftDBAIError`` with the same semantic meaning.
    func toSwiftDBAIError(rawResponse: String = "") -> SwiftDBAIError {
        switch self {
        case .noSQLFound:
            if rawResponse.isEmpty {
                return .noSQLGenerated
            }
            return .llmResponseUnparseable(response: rawResponse)
        case .operationNotAllowed(let op):
            return .operationNotAllowed(operation: op.rawValue)
        case .confirmationRequired(let sql, let op):
            return .confirmationRequired(sql: sql, operation: op.rawValue)
        case .tableNotAllowed(let table, let op):
            return .tableNotAllowedForMutation(tableName: table, operation: op.rawValue)
        case .dangerousOperation(let keyword):
            return .dangerousOperationBlocked(keyword: keyword)
        case .multipleStatements:
            return .multipleStatementsNotSupported
        }
    }
}

// MARK: - Conversion from ChatEngineError

extension ChatEngineError {
    /// Maps a ``ChatEngineError`` to the corresponding ``SwiftDBAIError`` case.
    func toSwiftDBAIError() -> SwiftDBAIError {
        switch self {
        case .sqlParsingFailed(let parsingError):
            return parsingError.toSwiftDBAIError()
        case .confirmationRequired(let sql, let operation):
            return .confirmationRequired(sql: sql, operation: operation.rawValue)
        case .schemaIntrospectionFailed(let reason):
            return .schemaIntrospectionFailed(reason: reason)
        case .queryTimedOut(let seconds):
            return .queryTimedOut(seconds: seconds)
        case .validationFailed(let reason):
            return .queryRejected(reason: reason)
        }
    }
}
