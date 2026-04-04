// ToolExecutionDelegate.swift
// SwiftDBAI
//
// Delegate protocol for controlling SQL tool execution, including
// confirmation of destructive operations before they reach the database.

import Foundation

// MARK: - Destructive SQL Classification

/// Classifies SQL statements by their destructive potential.
///
/// A statement is considered **destructive** if it modifies or removes data
/// or schema objects. The classification drives the confirmation flow:
/// destructive statements require explicit user approval via
/// ``ToolExecutionDelegate/confirmDestructiveOperation(_:)``.
public enum DestructiveClassification: Sendable, Equatable {
    /// The statement is read-only (e.g. SELECT). No confirmation needed.
    case safe

    /// The statement modifies existing data (INSERT, UPDATE).
    case mutation(SQLStatementKind)

    /// The statement deletes data or alters/drops schema objects.
    /// These always require confirmation, even when the operation is allowed.
    case destructive(SQLStatementKind)

    /// Returns `true` when the statement requires user confirmation.
    public var requiresConfirmation: Bool {
        switch self {
        case .safe:
            return false
        case .mutation:
            return false
        case .destructive:
            return true
        }
    }

    /// Returns `true` when the statement modifies data or schema in any way.
    public var isMutating: Bool {
        switch self {
        case .safe:
            return false
        case .mutation, .destructive:
            return true
        }
    }
}

/// The kind of SQL statement, used for classification and display.
public enum SQLStatementKind: String, Sendable, Hashable, CaseIterable {
    case select = "SELECT"
    case insert = "INSERT"
    case update = "UPDATE"
    case delete = "DELETE"
    case drop = "DROP"
    case alter = "ALTER"
    case truncate = "TRUNCATE"

    /// All kinds that are classified as destructive.
    public static let destructiveKinds: Set<SQLStatementKind> = [
        .delete, .drop, .alter, .truncate
    ]

    /// All kinds that are classified as mutations (data-modifying but not destructive).
    public static let mutationKinds: Set<SQLStatementKind> = [
        .insert, .update
    ]

    /// Whether this kind of statement is destructive.
    public var isDestructive: Bool {
        Self.destructiveKinds.contains(self)
    }

    /// Whether this kind of statement is a mutation (INSERT/UPDATE).
    public var isMutation: Bool {
        Self.mutationKinds.contains(self)
    }
}

// MARK: - Classification Function

/// Classifies a SQL statement string by its destructive potential.
///
/// The classifier inspects the first keyword token of the statement
/// (case-insensitive) to determine the statement kind, then maps it
/// to a ``DestructiveClassification``.
///
/// - Parameter sql: The SQL statement to classify.
/// - Returns: The classification for the statement.
public func classifySQL(_ sql: String) -> DestructiveClassification {
    guard let kind = detectStatementKind(sql) else {
        return .safe
    }

    if kind.isDestructive {
        return .destructive(kind)
    } else if kind.isMutation {
        return .mutation(kind)
    } else {
        return .safe
    }
}

/// Detects the ``SQLStatementKind`` from the leading keyword of a SQL string.
///
/// - Parameter sql: The SQL statement to inspect.
/// - Returns: The detected kind, or `nil` if unrecognized.
public func detectStatementKind(_ sql: String) -> SQLStatementKind? {
    let trimmed = sql.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()

    // Check each known statement kind against the first token
    if trimmed.hasPrefix("SELECT") || trimmed.hasPrefix("WITH") {
        return .select
    } else if trimmed.hasPrefix("INSERT") {
        return .insert
    } else if trimmed.hasPrefix("UPDATE") {
        return .update
    } else if trimmed.hasPrefix("DELETE") {
        return .delete
    } else if trimmed.hasPrefix("DROP") {
        return .drop
    } else if trimmed.hasPrefix("ALTER") {
        return .alter
    } else if trimmed.hasPrefix("TRUNCATE") {
        return .truncate
    }

    return nil
}

// MARK: - Destructive Operation Context

/// Context provided to the delegate when a destructive operation needs confirmation.
///
/// Contains all the information a UI or programmatic handler needs to
/// decide whether to allow the operation.
public struct DestructiveOperationContext: Sendable {
    /// The SQL statement that would be executed.
    public let sql: String

    /// The detected kind of statement (DELETE, DROP, ALTER, TRUNCATE).
    public let statementKind: SQLStatementKind

    /// The classification result.
    public let classification: DestructiveClassification

    /// A human-readable description of what the operation will do.
    public let description: String

    /// The target table name, if detected.
    public let targetTable: String?

    public init(
        sql: String,
        statementKind: SQLStatementKind,
        classification: DestructiveClassification,
        description: String,
        targetTable: String? = nil
    ) {
        self.sql = sql
        self.statementKind = statementKind
        self.classification = classification
        self.description = description
        self.targetTable = targetTable
    }
}

// MARK: - ToolExecutionDelegate Protocol

/// A delegate that controls execution of SQL operations, providing
/// confirmation gates for destructive statements.
///
/// Implement this protocol to intercept destructive SQL operations
/// (DELETE, DROP, ALTER, TRUNCATE) before they are executed. The
/// ``ChatEngine`` consults the delegate whenever it encounters a
/// statement classified as ``DestructiveClassification/destructive(_:)``.
///
/// ## Example
///
/// ```swift
/// struct MyDelegate: ToolExecutionDelegate {
///     func confirmDestructiveOperation(
///         _ context: DestructiveOperationContext
///     ) async -> Bool {
///         // Show a confirmation dialog to the user
///         return await showAlert(
///             "Confirm \(context.statementKind.rawValue)",
///             message: context.description
///         )
///     }
/// }
///
/// let engine = ChatEngine(
///     database: pool,
///     model: model,
///     delegate: MyDelegate()
/// )
/// ```
public protocol ToolExecutionDelegate: Sendable {

    /// Called when a destructive SQL operation is about to be executed.
    ///
    /// The delegate should present the operation details to the user and
    /// return `true` to proceed or `false` to cancel.
    ///
    /// - Parameter context: Details about the destructive operation.
    /// - Returns: `true` to allow execution, `false` to reject it.
    func confirmDestructiveOperation(
        _ context: DestructiveOperationContext
    ) async -> Bool

    /// Called before any SQL statement is executed.
    ///
    /// This is an observation hook — the engine does not wait for a
    /// decision. Override to log, audit, or instrument queries.
    ///
    /// - Parameters:
    ///   - sql: The SQL about to be executed.
    ///   - classification: The destructive classification of the statement.
    func willExecuteSQL(
        _ sql: String,
        classification: DestructiveClassification
    ) async

    /// Called after a SQL statement completes execution.
    ///
    /// - Parameters:
    ///   - sql: The SQL that was executed.
    ///   - success: Whether execution succeeded.
    func didExecuteSQL(
        _ sql: String,
        success: Bool
    ) async
}

// MARK: - Default Implementations

extension ToolExecutionDelegate {
    /// Default: rejects all destructive operations.
    public func confirmDestructiveOperation(
        _ context: DestructiveOperationContext
    ) async -> Bool {
        false
    }

    /// Default: no-op.
    public func willExecuteSQL(
        _ sql: String,
        classification: DestructiveClassification
    ) async {}

    /// Default: no-op.
    public func didExecuteSQL(
        _ sql: String,
        success: Bool
    ) async {}
}

// MARK: - Built-in Delegates

/// A delegate that automatically approves all destructive operations.
///
/// Use this only in testing or trusted environments where confirmation
/// is not needed.
public struct AutoApproveDelegate: ToolExecutionDelegate {
    public init() {}

    public func confirmDestructiveOperation(
        _ context: DestructiveOperationContext
    ) async -> Bool {
        true
    }
}

/// A delegate that always rejects destructive operations.
///
/// This is the safest option and matches the default behavior.
public struct RejectAllDelegate: ToolExecutionDelegate {
    public init() {}

    public func confirmDestructiveOperation(
        _ context: DestructiveOperationContext
    ) async -> Bool {
        false
    }
}
