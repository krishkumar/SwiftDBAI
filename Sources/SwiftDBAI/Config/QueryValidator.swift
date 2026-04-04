// QueryValidator.swift
// SwiftDBAI
//
// Extensible query validation protocol for custom pre-execution checks.

import Foundation

/// A protocol for custom SQL query validation.
///
/// Implement this protocol to add domain-specific validation rules that run
/// after the built-in allowlist and safety checks. Validators receive the
/// parsed SQL string and its detected operation type.
///
/// Example — restrict queries to specific tables:
/// ```swift
/// struct TableAllowlistValidator: QueryValidator {
///     let allowedTables: Set<String>
///
///     func validate(sql: String, operation: SQLOperation) throws {
///         let upper = sql.uppercased()
///         for table in allowedTables {
///             // Simple check — real implementation might parse FROM/JOIN clauses
///             if upper.contains(table.uppercased()) { return }
///         }
///         throw QueryValidationError.rejected("Query references tables outside the allowlist.")
///     }
/// }
/// ```
public protocol QueryValidator: Sendable {
    /// Validates a SQL query before execution.
    ///
    /// - Parameters:
    ///   - sql: The cleaned SQL statement about to be executed.
    ///   - operation: The detected operation type (SELECT, INSERT, etc.).
    /// - Throws: ``QueryValidationError`` or any `Error` to reject the query.
    func validate(sql: String, operation: SQLOperation) throws
}

/// Errors thrown by custom ``QueryValidator`` implementations.
public enum QueryValidationError: Error, LocalizedError, Sendable, Equatable {
    /// The query was rejected by a custom validator with the given reason.
    case rejected(String)

    public var errorDescription: String? {
        switch self {
        case .rejected(let reason):
            return "Query rejected: \(reason)"
        }
    }
}

// MARK: - Built-in Validators

/// A validator that restricts queries to a specific set of table names.
///
/// This performs a simple keyword check — it verifies that the SQL references
/// at least one of the allowed tables. This is a best-effort check, not a
/// full SQL parser.
public struct TableAllowlistValidator: QueryValidator {
    /// The set of table names queries are allowed to reference.
    public let allowedTables: Set<String>

    /// Creates a validator with the given allowed table names.
    public init(allowedTables: Set<String>) {
        self.allowedTables = allowedTables
    }

    public func validate(sql: String, operation: SQLOperation) throws {
        let upper = sql.uppercased()
        let found = allowedTables.contains { table in
            let pattern = table.uppercased()
            return upper.contains(pattern)
        }
        guard found else {
            throw QueryValidationError.rejected(
                "Query does not reference any allowed tables: \(allowedTables.sorted().joined(separator: ", "))"
            )
        }
    }
}

/// A validator that enforces a maximum row limit on SELECT queries
/// by checking for a LIMIT clause.
public struct MaxRowLimitValidator: QueryValidator {
    /// The maximum number of rows allowed.
    public let maxRows: Int

    /// Creates a validator that requires SELECT queries to include a LIMIT clause
    /// not exceeding `maxRows`.
    public init(maxRows: Int) {
        self.maxRows = maxRows
    }

    public func validate(sql: String, operation: SQLOperation) throws {
        guard operation == .select else { return }

        let upper = sql.uppercased()
        // Check if LIMIT is present
        guard let limitRange = upper.range(of: #"LIMIT\s+(\d+)"#, options: .regularExpression) else {
            throw QueryValidationError.rejected(
                "SELECT queries must include a LIMIT clause (max \(maxRows) rows)."
            )
        }

        // Extract the limit value
        let limitSubstring = upper[limitRange]
        let digits = limitSubstring.components(separatedBy: .decimalDigits.inverted).joined()
        if let value = Int(digits), value > maxRows {
            throw QueryValidationError.rejected(
                "LIMIT \(value) exceeds the maximum allowed (\(maxRows))."
            )
        }
    }
}
