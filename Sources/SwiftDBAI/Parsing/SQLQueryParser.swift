// SQLQueryParser.swift
// SwiftDBAI
//
// Extracts and validates SQL statements from raw LLM response text.

import Foundation

/// Errors that can occur during SQL parsing and validation.
public enum SQLParsingError: Error, Sendable, Equatable, CustomStringConvertible {
    /// No SQL statement could be found in the LLM response.
    case noSQLFound

    /// The SQL statement uses an operation not in the allowlist.
    case operationNotAllowed(SQLOperation)

    /// A destructive operation (DELETE) requires user confirmation.
    case confirmationRequired(sql: String, operation: SQLOperation)

    /// The mutation targets a table not in the allowed mutation tables.
    case tableNotAllowed(table: String, operation: SQLOperation)

    /// The SQL contains a disallowed keyword (e.g., DROP, ALTER, TRUNCATE).
    case dangerousOperation(String)

    /// Multiple SQL statements were found but only single-statement execution is supported.
    case multipleStatements

    public var description: String {
        switch self {
        case .noSQLFound:
            return "No SQL statement found in the response."
        case .operationNotAllowed(let op):
            return "Operation '\(op.rawValue.uppercased())' is not allowed by the current configuration."
        case .confirmationRequired(let sql, let op):
            return "The \(op.rawValue.uppercased()) operation requires confirmation: \(sql)"
        case .tableNotAllowed(let table, let op):
            return "The \(op.rawValue.uppercased()) operation is not allowed on table '\(table)'."
        case .dangerousOperation(let keyword):
            return "Dangerous SQL operation '\(keyword)' is never allowed."
        case .multipleStatements:
            return "Only single SQL statements are supported."
        }
    }
}

/// Result of successfully parsing SQL from an LLM response.
public struct ParsedSQL: Sendable, Equatable {
    /// The cleaned SQL statement ready for execution.
    public let sql: String

    /// The detected operation type.
    public let operation: SQLOperation

    /// Whether this operation requires user confirmation before execution.
    public let requiresConfirmation: Bool

    public init(sql: String, operation: SQLOperation, requiresConfirmation: Bool = false) {
        self.sql = sql
        self.operation = operation
        self.requiresConfirmation = requiresConfirmation
    }
}

/// Extracts SQL statements from raw LLM response text and validates them
/// against the configured ``OperationAllowlist``.
///
/// The parser handles common LLM output patterns:
/// - SQL in markdown code blocks (```sql ... ```)
/// - SQL in generic code blocks (``` ... ```)
/// - Raw SQL statements in plain text
/// - SQL prefixed with labels like "SQL:" or "Query:"
public struct SQLQueryParser: Sendable {

    /// Keywords that are never allowed regardless of allowlist configuration.
    private static let dangerousKeywords: Set<String> = [
        "DROP", "ALTER", "TRUNCATE", "CREATE", "GRANT", "REVOKE",
        "ATTACH", "DETACH", "PRAGMA", "VACUUM", "REINDEX"
    ]

    /// The operation allowlist to validate against.
    private let allowlist: OperationAllowlist

    /// The mutation policy for table-level restrictions.
    private let mutationPolicy: MutationPolicy?

    /// Creates a parser with the given operation allowlist.
    /// - Parameter allowlist: The set of permitted operations. Defaults to read-only.
    public init(allowlist: OperationAllowlist = .readOnly) {
        self.allowlist = allowlist
        self.mutationPolicy = nil
    }

    /// Creates a parser with a mutation policy (preferred initializer).
    /// - Parameter mutationPolicy: The mutation policy controlling operations and table access.
    public init(mutationPolicy: MutationPolicy) {
        self.allowlist = mutationPolicy.operationAllowlist
        self.mutationPolicy = mutationPolicy
    }

    /// Extracts and validates a SQL statement from raw LLM response text.
    ///
    /// - Parameter text: The raw text from the LLM response.
    /// - Returns: A ``ParsedSQL`` containing the validated statement.
    /// - Throws: ``SQLParsingError`` if extraction or validation fails.
    public func parse(_ text: String) throws -> ParsedSQL {
        let sql = try extractSQL(from: text)
        return try validate(sql)
    }

    // MARK: - Extraction

    /// Attempts to extract a SQL statement from the LLM response text.
    /// Tries multiple strategies in order of confidence.
    func extractSQL(from text: String) throws -> String {
        // Strategy 1: SQL in markdown fenced code block with sql language tag
        if let sql = extractFromSQLCodeBlock(text) {
            return sql
        }

        // Strategy 2: SQL in generic fenced code block
        if let sql = extractFromGenericCodeBlock(text) {
            return sql
        }

        // Strategy 3: SQL after a label like "SQL:" or "Query:"
        if let sql = extractFromLabel(text) {
            return sql
        }

        // Strategy 4: Direct SQL detection in plain text
        if let sql = extractDirectSQL(text) {
            return sql
        }

        // Strategy 5: Strip markdown fence markers (3+ backticks with optional
        // language tag) and retry. Only removes fences, not single backticks
        // used for SQLite identifier quoting like `column name`.
        let defenced = stripMarkdownFences(text)
        if defenced != text, let sql = extractDirectSQL(defenced) {
            return sql
        }

        throw SQLParsingError.noSQLFound
    }

    /// Removes markdown fence markers (```) while preserving single backtick
    /// identifier quoting. Handles: ```sql, ```, and trailing ```.
    private func stripMarkdownFences(_ text: String) -> String {
        text.replacingOccurrences(
            of: #"`{3,}\s*(?:sql|SQL)?\s*"#,
            with: " ",
            options: .regularExpression
        ).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Extracts SQL from a ```sql ... ``` code block.
    private func extractFromSQLCodeBlock(_ text: String) -> String? {
        let pattern = #"```sql\s*\n([\s\S]*?)```"#
        return firstMatch(pattern: pattern, in: text, group: 1)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nonEmptyOrNil
    }

    /// Extracts SQL from a generic ``` ... ``` code block.
    private func extractFromGenericCodeBlock(_ text: String) -> String? {
        let pattern = #"```\s*\n([\s\S]*?)```"#
        guard let content = firstMatch(pattern: pattern, in: text, group: 1)?
            .trimmingCharacters(in: .whitespacesAndNewlines) else {
            return nil
        }
        // Only accept if it looks like SQL
        guard looksLikeSQL(content) else { return nil }
        return content.nonEmptyOrNil
    }

    /// Extracts SQL after labels like "SQL:", "Query:", "Here's the query:"
    private func extractFromLabel(_ text: String) -> String? {
        // Match the SQL keyword up to end-of-line (handling multi-line SQL with indentation)
        let pattern = #"(?:SQL|Query|Statement)\s*:\s*\n?\s*((?:SELECT|INSERT|UPDATE|DELETE|WITH)\b.+?)(?:\n(?!\s)|$)"#
        guard let content = firstMatch(pattern: pattern, in: text, group: 1, options: [.caseInsensitive, .dotMatchesLineSeparators])?
            .trimmingCharacters(in: .whitespacesAndNewlines) else {
            return nil
        }
        guard looksLikeSQL(content) else { return nil }
        return content.nonEmptyOrNil
    }

    /// Detects SQL directly in the text by matching known statement patterns.
    private func extractDirectSQL(_ text: String) -> String? {
        // Match SQL statement, allowing semicolons inside single-quoted string literals
        let pattern = #"(?:^|\n)\s*((?:SELECT|INSERT|UPDATE|DELETE)\b(?:[^;']|'[^']*')*;?)"#
        guard let content = firstMatch(pattern: pattern, in: text, group: 1, options: .caseInsensitive)?
            .trimmingCharacters(in: .whitespacesAndNewlines) else {
            return nil
        }
        return content.nonEmptyOrNil
    }

    // MARK: - Validation

    /// Validates a SQL string against the allowlist and safety rules.
    func validate(_ sql: String) throws -> ParsedSQL {
        let cleaned = cleanSQL(sql)

        guard !cleaned.isEmpty else {
            throw SQLParsingError.noSQLFound
        }

        // Check for multiple statements (semicolons in non-trivial positions)
        if containsMultipleStatements(cleaned) {
            throw SQLParsingError.multipleStatements
        }

        // Check for dangerous operations first (before allowlist)
        try checkDangerousKeywords(cleaned)

        // Detect the operation type
        let operation = detectOperation(cleaned)

        // Check against the allowlist
        guard allowlist.isAllowed(operation) else {
            throw SQLParsingError.operationNotAllowed(operation)
        }

        // Check table-level restrictions for mutation operations
        if let policy = mutationPolicy, operation != .select,
           let targetTable = extractTargetTable(from: cleaned, operation: operation) {
            guard policy.isAllowed(operation: operation, on: targetTable) else {
                throw SQLParsingError.tableNotAllowed(table: targetTable, operation: operation)
            }
        }

        // DELETE requires confirmation when policy says so, or always by default
        let requiresConfirmation: Bool
        if let policy = mutationPolicy {
            requiresConfirmation = policy.requiresConfirmation(for: operation)
        } else {
            requiresConfirmation = operation == .delete
        }

        return ParsedSQL(
            sql: cleaned,
            operation: operation,
            requiresConfirmation: requiresConfirmation
        )
    }

    // MARK: - Helpers

    /// Cleans a SQL string by removing trailing semicolons (outside string literals) and excess whitespace.
    private func cleanSQL(_ sql: String) -> String {
        var cleaned = sql.trimmingCharacters(in: .whitespacesAndNewlines)
        // Remove trailing semicolons only if they're outside string literals
        while cleaned.hasSuffix(";") && !isInsideStringLiteral(sql: cleaned, position: cleaned.index(before: cleaned.endIndex)) {
            cleaned = String(cleaned.dropLast()).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        // Collapse internal whitespace outside string literals
        cleaned = collapseWhitespace(cleaned)
        return cleaned
    }

    /// Collapses whitespace while preserving string literal contents.
    private func collapseWhitespace(_ sql: String) -> String {
        var result = ""
        var inString = false
        var prevWasSpace = false
        for ch in sql {
            if ch == "'" {
                inString.toggle()
                prevWasSpace = false
                result.append(ch)
            } else if inString {
                result.append(ch)
            } else if ch.isWhitespace {
                if !prevWasSpace {
                    result.append(" ")
                    prevWasSpace = true
                }
            } else {
                prevWasSpace = false
                result.append(ch)
            }
        }
        return result
    }

    /// Returns true if the character at the given position is inside a single-quoted string literal.
    private func isInsideStringLiteral(sql: String, position: String.Index) -> Bool {
        var inString = false
        for idx in sql.indices {
            if idx == position { return inString }
            if sql[idx] == "'" { inString.toggle() }
        }
        return false
    }

    /// Checks whether cleaned SQL contains multiple statements.
    private func containsMultipleStatements(_ sql: String) -> Bool {
        // Remove string literals before checking for semicolons
        var inString = false
        for ch in sql {
            if ch == "'" {
                inString.toggle()
            } else if ch == ";" && !inString {
                return true
            }
        }
        return false
    }

    /// Checks for dangerous SQL keywords that are never allowed.
    private func checkDangerousKeywords(_ sql: String) throws {
        let upper = sql.uppercased()
        // Tokenize to avoid partial matches (e.g., "DROPDOWN" matching "DROP")
        let tokens = upper.components(separatedBy: .alphanumerics.inverted)
            .filter { !$0.isEmpty }

        for keyword in Self.dangerousKeywords {
            if tokens.contains(keyword) {
                throw SQLParsingError.dangerousOperation(keyword)
            }
        }
    }

    /// Detects the SQL operation type from the first keyword.
    private func detectOperation(_ sql: String) -> SQLOperation {
        let upper = sql.uppercased().trimmingCharacters(in: .whitespaces)

        if upper.hasPrefix("SELECT") || upper.hasPrefix("WITH") {
            return .select
        } else if upper.hasPrefix("INSERT") {
            return .insert
        } else if upper.hasPrefix("UPDATE") {
            return .update
        } else if upper.hasPrefix("DELETE") {
            return .delete
        }

        // Default to select for unrecognized patterns (e.g. EXPLAIN)
        return .select
    }

    /// Extracts the target table name from a mutation SQL statement.
    ///
    /// Handles common patterns:
    /// - `INSERT INTO table_name ...`
    /// - `UPDATE table_name SET ...`
    /// - `DELETE FROM table_name ...`
    private func extractTargetTable(from sql: String, operation: SQLOperation) -> String? {
        let pattern: String
        switch operation {
        case .insert:
            pattern = #"INSERT\s+INTO\s+[`"\[]?(\w+)[`"\]]?"#
        case .update:
            pattern = #"UPDATE\s+[`"\[]?(\w+)[`"\]]?"#
        case .delete:
            pattern = #"DELETE\s+FROM\s+[`"\[]?(\w+)[`"\]]?"#
        case .select:
            return nil
        }
        return firstMatch(pattern: pattern, in: sql, group: 1, options: .caseInsensitive)
    }

    /// Returns true if the text looks like a SQL statement.
    private func looksLikeSQL(_ text: String) -> Bool {
        let upper = text.uppercased().trimmingCharacters(in: .whitespaces)
        let sqlPrefixes = ["SELECT", "INSERT", "UPDATE", "DELETE", "WITH"]
        return sqlPrefixes.contains { upper.hasPrefix($0) }
    }

    /// Extracts the first regex match group from the text.
    private func firstMatch(
        pattern: String,
        in text: String,
        group: Int,
        options: NSRegularExpression.Options = []
    ) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else {
            return nil
        }
        let range = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, range: range),
              match.numberOfRanges > group,
              let groupRange = Range(match.range(at: group), in: text) else {
            return nil
        }
        return String(text[groupRange])
    }
}

// MARK: - String Extension

private extension String {
    /// Returns nil if the string is empty, otherwise returns self.
    var nonEmptyOrNil: String? {
        isEmpty ? nil : self
    }
}
