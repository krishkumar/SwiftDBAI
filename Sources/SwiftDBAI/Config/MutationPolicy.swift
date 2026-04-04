// MutationPolicy.swift
// SwiftDBAI
//
// Defines which mutation operations are permitted and optionally restricts
// them to specific tables. Wraps OperationAllowlist with table-level granularity.

import Foundation

/// Controls which SQL mutation operations the LLM may generate and,
/// optionally, which tables those mutations may target.
///
/// `MutationPolicy` builds on ``OperationAllowlist`` by adding per-table
/// restrictions. The default policy is **read-only** — no mutations are
/// allowed on any table. Write operations require explicit opt-in.
///
/// ```swift
/// // Read-only (default) — only SELECT is allowed
/// let readOnly = MutationPolicy.readOnly
///
/// // Allow INSERT and UPDATE on specific tables only
/// let restricted = MutationPolicy(
///     allowedOperations: [.insert, .update],
///     allowedTables: ["orders", "order_items"]
/// )
///
/// // Allow INSERT and UPDATE on all tables
/// let broad = MutationPolicy(allowedOperations: [.insert, .update])
///
/// // Full access including DELETE (requires confirmation)
/// let full = MutationPolicy.unrestricted
/// ```
public struct MutationPolicy: Sendable, Equatable {

    // MARK: - Properties

    /// The underlying operation allowlist (always includes SELECT).
    public let operationAllowlist: OperationAllowlist

    /// Optional set of table names that mutations may target.
    ///
    /// When `nil`, mutations are allowed on all tables (subject to
    /// ``operationAllowlist``). When non-nil, mutation operations
    /// (INSERT, UPDATE, DELETE) are only permitted on the listed tables.
    /// SELECT queries are never restricted by this property.
    public let allowedMutationTables: Set<String>?

    /// When `true`, destructive operations (DELETE) require explicit user
    /// confirmation before execution, even when the operation is allowed.
    /// Defaults to `true`.
    public let requiresDestructiveConfirmation: Bool

    // MARK: - Initialization

    /// Creates a mutation policy with the given operations and optional table restrictions.
    ///
    /// SELECT is always implicitly included — you cannot create a policy
    /// that disallows reads.
    ///
    /// - Parameters:
    ///   - allowedOperations: The mutation operations to permit (INSERT, UPDATE, DELETE).
    ///     SELECT is always allowed regardless of this parameter.
    ///   - allowedTables: Optional set of table names mutations may target.
    ///     Pass `nil` to allow mutations on all tables. Defaults to `nil`.
    ///   - requiresDestructiveConfirmation: Whether DELETE requires user confirmation.
    ///     Defaults to `true`.
    public init(
        allowedOperations: Set<SQLOperation> = [],
        allowedTables: Set<String>? = nil,
        requiresDestructiveConfirmation: Bool = true
    ) {
        // Always include SELECT
        var ops = allowedOperations
        ops.insert(.select)
        self.operationAllowlist = OperationAllowlist(ops)
        self.allowedMutationTables = allowedTables
        self.requiresDestructiveConfirmation = requiresDestructiveConfirmation
    }

    // MARK: - Presets

    /// Read-only policy: only SELECT queries are allowed. This is the default.
    public static let readOnly = MutationPolicy()

    /// Standard read-write: SELECT, INSERT, and UPDATE on all tables.
    public static let readWrite = MutationPolicy(
        allowedOperations: [.insert, .update]
    )

    /// Unrestricted: all operations including DELETE on all tables.
    /// DELETE still requires confirmation by default.
    public static let unrestricted = MutationPolicy(
        allowedOperations: [.insert, .update, .delete]
    )

    // MARK: - Validation

    /// Returns `true` if the given operation is permitted by this policy.
    public func isOperationAllowed(_ operation: SQLOperation) -> Bool {
        operationAllowlist.isAllowed(operation)
    }

    /// Returns `true` if the given mutation operation is permitted on the
    /// specified table.
    ///
    /// SELECT operations always return `true` regardless of table restrictions.
    /// For mutation operations, this checks both the operation allowlist and
    /// the table restrictions (if any).
    ///
    /// - Parameters:
    ///   - operation: The SQL operation type.
    ///   - table: The target table name (case-insensitive comparison).
    /// - Returns: Whether the operation is allowed on the given table.
    public func isAllowed(operation: SQLOperation, on table: String) -> Bool {
        // SELECT is always allowed
        guard operation != .select else { return true }

        // Check operation allowlist first
        guard operationAllowlist.isAllowed(operation) else { return false }

        // If no table restrictions, the operation is allowed
        guard let allowedTables = allowedMutationTables else { return true }

        // Case-insensitive table name check
        let lowerTable = table.lowercased()
        return allowedTables.contains { $0.lowercased() == lowerTable }
    }

    /// Returns `true` if the given operation requires user confirmation.
    public func requiresConfirmation(for operation: SQLOperation) -> Bool {
        operation == .delete && requiresDestructiveConfirmation
    }

    /// Returns a human-readable description for inclusion in the LLM system prompt.
    func describeForLLM() -> String {
        var desc = operationAllowlist.describeForLLM()

        if let tables = allowedMutationTables, !tables.isEmpty {
            let sorted = tables.sorted()
            desc += " Mutations (INSERT/UPDATE/DELETE) are restricted to these tables only: \(sorted.joined(separator: ", "))."
        }

        if requiresDestructiveConfirmation && operationAllowlist.isAllowed(.delete) {
            desc += " DELETE operations require user confirmation before execution."
        }

        return desc
    }
}
