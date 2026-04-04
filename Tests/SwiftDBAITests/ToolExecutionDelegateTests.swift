// ToolExecutionDelegateTests.swift
// SwiftDBAITests

import Foundation
import Testing
@testable import SwiftDBAI

@Suite("DestructiveClassification")
struct DestructiveClassificationTests {

    // MARK: - Safe statements

    @Test("SELECT is classified as safe")
    func selectIsSafe() {
        let result = classifySQL("SELECT * FROM users")
        #expect(result == .safe)
        #expect(!result.requiresConfirmation)
        #expect(!result.isMutating)
    }

    @Test("WITH (CTE) is classified as safe")
    func withIsSafe() {
        let result = classifySQL("WITH cte AS (SELECT 1) SELECT * FROM cte")
        #expect(result == .safe)
    }

    // MARK: - Mutation statements

    @Test("INSERT is classified as mutation")
    func insertIsMutation() {
        let result = classifySQL("INSERT INTO users (name) VALUES ('Alice')")
        #expect(result == .mutation(.insert))
        #expect(!result.requiresConfirmation)
        #expect(result.isMutating)
    }

    @Test("UPDATE is classified as mutation")
    func updateIsMutation() {
        let result = classifySQL("UPDATE users SET name = 'Bob' WHERE id = 1")
        #expect(result == .mutation(.update))
        #expect(!result.requiresConfirmation)
        #expect(result.isMutating)
    }

    // MARK: - Destructive statements

    @Test("DELETE is classified as destructive")
    func deleteIsDestructive() {
        let result = classifySQL("DELETE FROM users WHERE id = 1")
        #expect(result == .destructive(.delete))
        #expect(result.requiresConfirmation)
        #expect(result.isMutating)
    }

    @Test("DROP is classified as destructive")
    func dropIsDestructive() {
        let result = classifySQL("DROP TABLE users")
        #expect(result == .destructive(.drop))
        #expect(result.requiresConfirmation)
    }

    @Test("ALTER is classified as destructive")
    func alterIsDestructive() {
        let result = classifySQL("ALTER TABLE users ADD COLUMN age INTEGER")
        #expect(result == .destructive(.alter))
        #expect(result.requiresConfirmation)
    }

    @Test("TRUNCATE is classified as destructive")
    func truncateIsDestructive() {
        let result = classifySQL("TRUNCATE TABLE users")
        #expect(result == .destructive(.truncate))
        #expect(result.requiresConfirmation)
    }

    // MARK: - Case insensitivity

    @Test("Classification is case-insensitive")
    func caseInsensitive() {
        #expect(classifySQL("delete from users") == .destructive(.delete))
        #expect(classifySQL("Drop Table foo") == .destructive(.drop))
        #expect(classifySQL("select 1") == .safe)
        #expect(classifySQL("INSERT into t values (1)") == .mutation(.insert))
    }

    // MARK: - Leading whitespace

    @Test("Classification ignores leading whitespace")
    func leadingWhitespace() {
        #expect(classifySQL("  \n  DELETE FROM users") == .destructive(.delete))
        #expect(classifySQL("\t SELECT 1") == .safe)
    }

    // MARK: - SQLStatementKind

    @Test("Destructive kinds are correct")
    func destructiveKinds() {
        #expect(SQLStatementKind.delete.isDestructive)
        #expect(SQLStatementKind.drop.isDestructive)
        #expect(SQLStatementKind.alter.isDestructive)
        #expect(SQLStatementKind.truncate.isDestructive)
        #expect(!SQLStatementKind.select.isDestructive)
        #expect(!SQLStatementKind.insert.isDestructive)
        #expect(!SQLStatementKind.update.isDestructive)
    }

    @Test("Mutation kinds are correct")
    func mutationKinds() {
        #expect(SQLStatementKind.insert.isMutation)
        #expect(SQLStatementKind.update.isMutation)
        #expect(!SQLStatementKind.select.isMutation)
        #expect(!SQLStatementKind.delete.isMutation)
    }
}

@Suite("ToolExecutionDelegate")
struct ToolExecutionDelegateProtocolTests {

    @Test("AutoApproveDelegate approves all operations")
    func autoApprove() async {
        let delegate = AutoApproveDelegate()
        let context = DestructiveOperationContext(
            sql: "DELETE FROM users",
            statementKind: .delete,
            classification: .destructive(.delete),
            description: "Delete all rows from users"
        )
        let result = await delegate.confirmDestructiveOperation(context)
        #expect(result == true)
    }

    @Test("RejectAllDelegate rejects all operations")
    func rejectAll() async {
        let delegate = RejectAllDelegate()
        let context = DestructiveOperationContext(
            sql: "DROP TABLE users",
            statementKind: .drop,
            classification: .destructive(.drop),
            description: "Drop the users table"
        )
        let result = await delegate.confirmDestructiveOperation(context)
        #expect(result == false)
    }

    @Test("Default delegate implementation rejects destructive operations")
    func defaultRejects() async {
        struct EmptyDelegate: ToolExecutionDelegate {}
        let delegate = EmptyDelegate()
        let context = DestructiveOperationContext(
            sql: "DELETE FROM users",
            statementKind: .delete,
            classification: .destructive(.delete),
            description: "Delete rows"
        )
        let result = await delegate.confirmDestructiveOperation(context)
        #expect(result == false)
    }
}

// MARK: - Tracking Delegate for Integration Tests

/// A delegate that records all calls for verification in tests.
private final class TrackingDelegate: ToolExecutionDelegate, @unchecked Sendable {
    private let lock = NSLock()

    private var _confirmCalls: [DestructiveOperationContext] = []
    private var _willExecuteCalls: [(sql: String, classification: DestructiveClassification)] = []
    private var _didExecuteCalls: [(sql: String, success: Bool)] = []
    private var _confirmResult: Bool

    var confirmCalls: [DestructiveOperationContext] {
        lock.withLock { _confirmCalls }
    }

    var willExecuteCalls: [(sql: String, classification: DestructiveClassification)] {
        lock.withLock { _willExecuteCalls }
    }

    var didExecuteCalls: [(sql: String, success: Bool)] {
        lock.withLock { _didExecuteCalls }
    }

    init(confirmResult: Bool) {
        self._confirmResult = confirmResult
    }

    func confirmDestructiveOperation(_ context: DestructiveOperationContext) async -> Bool {
        lock.withLock { _confirmCalls.append(context) }
        return _confirmResult
    }

    func willExecuteSQL(_ sql: String, classification: DestructiveClassification) async {
        lock.withLock { _willExecuteCalls.append((sql: sql, classification: classification)) }
    }

    func didExecuteSQL(_ sql: String, success: Bool) async {
        lock.withLock { _didExecuteCalls.append((sql: sql, success: success)) }
    }
}

@Suite("ToolExecutionDelegate - ChatEngine Integration")
struct DelegateIntegrationTests {

    @Test("DestructiveOperationContext captures target table")
    func contextCapturesTable() {
        let context = DestructiveOperationContext(
            sql: "DELETE FROM users WHERE id = 1",
            statementKind: .delete,
            classification: .destructive(.delete),
            description: "Delete from users",
            targetTable: "users"
        )
        #expect(context.targetTable == "users")
        #expect(context.statementKind == .delete)
        #expect(context.classification.requiresConfirmation)
    }

    @Test("classifySQL returns destructive for DELETE")
    func classifySQLDestructive() {
        let result = classifySQL("DELETE FROM orders WHERE id = 5")
        #expect(result == .destructive(.delete))
        #expect(result.requiresConfirmation)
    }

    @Test("classifySQL returns safe for SELECT")
    func classifySQLSafe() {
        let result = classifySQL("SELECT * FROM users")
        #expect(result == .safe)
        #expect(!result.requiresConfirmation)
    }

    @Test("classifySQL returns mutation for INSERT")
    func classifySQLMutation() {
        let result = classifySQL("INSERT INTO users (name) VALUES ('test')")
        #expect(result == .mutation(.insert))
        #expect(!result.requiresConfirmation)
    }

    @Test("DestructiveClassification.isMutating is true for mutations and destructive")
    func isMutatingCovers() {
        #expect(DestructiveClassification.mutation(.insert).isMutating)
        #expect(DestructiveClassification.mutation(.update).isMutating)
        #expect(DestructiveClassification.destructive(.delete).isMutating)
        #expect(!DestructiveClassification.safe.isMutating)
    }
}
