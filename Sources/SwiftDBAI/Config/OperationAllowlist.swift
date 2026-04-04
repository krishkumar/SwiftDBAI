/// Defines which SQL operations the LLM is permitted to generate.
///
/// The default is ``readOnly`` (SELECT only). Write operations require
/// explicit opt-in. This is the safety-by-default principle.
public struct OperationAllowlist: Sendable, Equatable {
    /// The set of permitted SQL operation types.
    public let allowedOperations: Set<SQLOperation>

    /// Creates an allowlist from the given set of operations.
    public init(_ operations: Set<SQLOperation>) {
        self.allowedOperations = operations
    }

    /// Read-only: only SELECT queries are permitted. This is the default.
    public static let readOnly = OperationAllowlist([.select])

    /// Standard read-write: SELECT, INSERT, and UPDATE are permitted.
    public static let standard = OperationAllowlist([.select, .insert, .update])

    /// Unrestricted: all operations including DELETE are permitted.
    /// DELETE still requires confirmation via `ToolExecutionDelegate`.
    public static let unrestricted = OperationAllowlist([.select, .insert, .update, .delete])

    /// Returns true if the given operation is allowed.
    public func isAllowed(_ operation: SQLOperation) -> Bool {
        allowedOperations.contains(operation)
    }

    /// Returns a human-readable description of what's allowed, for inclusion
    /// in the LLM system prompt.
    func describeForLLM() -> String {
        if allowedOperations == [.select] {
            return "You may ONLY generate SELECT queries. No data modifications are allowed."
        }

        let sorted = allowedOperations.sorted { $0.rawValue < $1.rawValue }
        let names = sorted.map { $0.rawValue.uppercased() }
        var desc = "Allowed SQL operations: \(names.joined(separator: ", "))."

        if allowedOperations.contains(.delete) {
            desc += " DELETE operations are destructive and require user confirmation before execution."
        }

        return desc
    }
}

/// The types of SQL operations that can be controlled via the allowlist.
public enum SQLOperation: String, Sendable, Hashable, CaseIterable {
    case select
    case insert
    case update
    case delete
}
