// DestructiveOperationTests.swift
// SwiftDBAITests
//
// Tests verifying that destructive operations are blocked without confirmation
// and allowed when the delegate approves.

import AnyLanguageModel
import Foundation
import GRDB
import Testing

@testable import SwiftDBAI

// MARK: - Test Delegates

/// A delegate that always rejects destructive operations and tracks calls.
private final class RejectingTrackingDelegate: SwiftDBAI.ToolExecutionDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private var _confirmCalls: [DestructiveOperationContext] = []
    private var _willExecuteCalls: [(sql: String, classification: DestructiveClassification)] = []
    private var _didExecuteCalls: [(sql: String, success: Bool)] = []

    var confirmCalls: [DestructiveOperationContext] {
        lock.withLock { _confirmCalls }
    }

    var willExecuteCalls: [(sql: String, classification: DestructiveClassification)] {
        lock.withLock { _willExecuteCalls }
    }

    var didExecuteCalls: [(sql: String, success: Bool)] {
        lock.withLock { _didExecuteCalls }
    }

    func confirmDestructiveOperation(_ context: DestructiveOperationContext) async -> Bool {
        lock.withLock { _confirmCalls.append(context) }
        return false
    }

    func willExecuteSQL(_ sql: String, classification: DestructiveClassification) async {
        lock.withLock { _willExecuteCalls.append((sql: sql, classification: classification)) }
    }

    func didExecuteSQL(_ sql: String, success: Bool) async {
        lock.withLock { _didExecuteCalls.append((sql: sql, success: success)) }
    }
}

/// A delegate that always approves destructive operations and tracks calls.
private final class ApprovingTrackingDelegate: SwiftDBAI.ToolExecutionDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private var _confirmCalls: [DestructiveOperationContext] = []
    private var _willExecuteCalls: [(sql: String, classification: DestructiveClassification)] = []
    private var _didExecuteCalls: [(sql: String, success: Bool)] = []

    var confirmCalls: [DestructiveOperationContext] {
        lock.withLock { _confirmCalls }
    }

    var willExecuteCalls: [(sql: String, classification: DestructiveClassification)] {
        lock.withLock { _willExecuteCalls }
    }

    var didExecuteCalls: [(sql: String, success: Bool)] {
        lock.withLock { _didExecuteCalls }
    }

    func confirmDestructiveOperation(_ context: DestructiveOperationContext) async -> Bool {
        lock.withLock { _confirmCalls.append(context) }
        return true
    }

    func willExecuteSQL(_ sql: String, classification: DestructiveClassification) async {
        lock.withLock { _willExecuteCalls.append((sql: sql, classification: classification)) }
    }

    func didExecuteSQL(_ sql: String, success: Bool) async {
        lock.withLock { _didExecuteCalls.append((sql: sql, success: success)) }
    }
}

// MARK: - Helpers

/// Creates an in-memory database with test data for destructive operation tests.
/// Users 1 and 2 have orders; user 3 has no orders (safe to delete).
private func makeTestDatabase() throws -> DatabaseQueue {
    let db = try DatabaseQueue(path: ":memory:")
    try db.write { db in
        // Disable FK enforcement for test flexibility, then re-enable
        try db.execute(sql: "PRAGMA foreign_keys = OFF")
        try db.execute(sql: """
            CREATE TABLE users (
                id INTEGER PRIMARY KEY,
                name TEXT NOT NULL,
                email TEXT NOT NULL
            )
            """)
        try db.execute(sql: """
            INSERT INTO users (name, email) VALUES
            ('Alice', 'alice@example.com'),
            ('Bob', 'bob@example.com'),
            ('Charlie', 'charlie@example.com')
            """)
        try db.execute(sql: """
            CREATE TABLE orders (
                id INTEGER PRIMARY KEY,
                user_id INTEGER NOT NULL,
                amount REAL NOT NULL
            )
            """)
        try db.execute(sql: """
            INSERT INTO orders (user_id, amount) VALUES
            (1, 99.99),
            (2, 150.00),
            (3, 25.50)
            """)
    }
    return db
}

/// A sequential mock model for tests. Returns responses in order.
private struct TestSequentialModel: LanguageModel {
    typealias UnavailableReason = Never

    let responses: [String]
    private let callCounter = CallCounter()

    private final class CallCounter: @unchecked Sendable {
        var count = 0
        let lock = NSLock()

        func next() -> Int {
            lock.lock()
            defer { lock.unlock() }
            let c = count
            count += 1
            return c
        }
    }

    init(responses: [String]) {
        self.responses = responses
    }

    func respond<Content>(
        within session: LanguageModelSession,
        to prompt: Prompt,
        generating type: Content.Type,
        includeSchemaInPrompt: Bool,
        options: GenerationOptions
    ) async throws -> LanguageModelSession.Response<Content> where Content: Generable {
        let idx = callCounter.next()
        let text = idx < responses.count ? responses[idx] : "fallback response"
        let rawContent = GeneratedContent(kind: .string(text))
        let content = try Content(rawContent)
        return LanguageModelSession.Response(
            content: content,
            rawContent: rawContent,
            transcriptEntries: [][...]
        )
    }

    func streamResponse<Content>(
        within session: LanguageModelSession,
        to prompt: Prompt,
        generating type: Content.Type,
        includeSchemaInPrompt: Bool,
        options: GenerationOptions
    ) -> sending LanguageModelSession.ResponseStream<Content> where Content: Generable {
        let idx = callCounter.next()
        let text = idx < responses.count ? responses[idx] : "fallback response"
        let rawContent = GeneratedContent(kind: .string(text))
        let content = try! Content(rawContent)
        return LanguageModelSession.ResponseStream(content: content, rawContent: rawContent)
    }
}

// MARK: - Tests: Destructive Operations Blocked Without Confirmation

@Suite("Destructive Operations - Blocked Without Confirmation")
struct DestructiveOperationsBlockedTests {

    @Test("DELETE is blocked when no delegate is provided")
    func deleteBlockedWithoutDelegate() async throws {
        let db = try makeTestDatabase()
        let model = TestSequentialModel(responses: [
            "DELETE FROM users WHERE id = 1"
        ])

        // Unrestricted allowlist permits DELETE, but no delegate to confirm
        let engine = ChatEngine(
            database: db,
            model: model,
            allowlist: .unrestricted
        )

        do {
            _ = try await engine.send("Delete user 1")
            Issue.record("Expected confirmationRequired error but send succeeded")
        } catch let error as SwiftDBAIError {
            guard case .confirmationRequired(let sql, let operation) = error else {
                Issue.record("Expected confirmationRequired, got: \(error)")
                return
            }
            #expect(sql.uppercased().contains("DELETE"))
            #expect(operation == "delete")
        }

        // Verify the user was NOT deleted (data remains intact)
        let count = try await db.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM users WHERE id = 1")
        }
        #expect(count == 1, "User should NOT have been deleted")
    }

    @Test("DELETE is blocked when delegate rejects")
    func deleteBlockedWhenDelegateRejects() async throws {
        let db = try makeTestDatabase()
        let delegate = RejectingTrackingDelegate()
        let model = TestSequentialModel(responses: [
            "DELETE FROM users WHERE id = 2"
        ])

        let engine = ChatEngine(
            database: db,
            model: model,
            allowlist: .unrestricted,
            delegate: delegate
        )

        do {
            _ = try await engine.send("Delete user 2")
            Issue.record("Expected confirmationRequired error but send succeeded")
        } catch let error as SwiftDBAIError {
            guard case .confirmationRequired(let sql, let operation) = error else {
                Issue.record("Expected confirmationRequired, got: \(error)")
                return
            }
            #expect(sql.uppercased().contains("DELETE"))
            #expect(operation == "delete")
        }

        // Verify delegate was consulted
        #expect(delegate.confirmCalls.count == 1)
        #expect(delegate.confirmCalls[0].statementKind == .delete)
        #expect(delegate.confirmCalls[0].sql.uppercased().contains("DELETE"))

        // Verify the data was NOT modified
        let count = try await db.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM users WHERE id = 2")
        }
        #expect(count == 1, "User should NOT have been deleted")

        // Verify no SQL was actually executed (no willExecute/didExecute calls)
        #expect(delegate.willExecuteCalls.isEmpty, "No SQL should have been executed")
        #expect(delegate.didExecuteCalls.isEmpty, "No SQL should have been executed")
    }

    @Test("DELETE is blocked with MutationPolicy and no delegate")
    func deleteBlockedWithMutationPolicyNoDelegate() async throws {
        let db = try makeTestDatabase()
        let model = TestSequentialModel(responses: [
            "DELETE FROM users WHERE id = 3"
        ])

        let policy = MutationPolicy(
            allowedOperations: [.insert, .update, .delete],
            requiresDestructiveConfirmation: true
        )

        let engine = ChatEngine(
            database: db,
            model: model,
            mutationPolicy: policy
        )

        do {
            _ = try await engine.send("Delete user 3")
            Issue.record("Expected confirmationRequired error but send succeeded")
        } catch let error as SwiftDBAIError {
            guard case .confirmationRequired(let sql, let operation) = error else {
                Issue.record("Expected confirmationRequired, got: \(error)")
                return
            }
            #expect(sql.uppercased().contains("DELETE"))
            #expect(operation == "delete")
        }

        // Data intact
        let count = try await db.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM users WHERE id = 3")
        }
        #expect(count == 1, "User should NOT have been deleted")
    }

    @Test("DELETE is blocked with MutationPolicy and rejecting delegate")
    func deleteBlockedWithMutationPolicyRejectingDelegate() async throws {
        let db = try makeTestDatabase()
        let delegate = RejectingTrackingDelegate()
        let model = TestSequentialModel(responses: [
            "DELETE FROM orders WHERE user_id = 1"
        ])

        let policy = MutationPolicy(
            allowedOperations: [.insert, .update, .delete],
            requiresDestructiveConfirmation: true
        )

        let engine = ChatEngine(
            database: db,
            model: model,
            mutationPolicy: policy,
            delegate: delegate
        )

        do {
            _ = try await engine.send("Delete all orders for user 1")
            Issue.record("Expected confirmationRequired error but send succeeded")
        } catch let error as SwiftDBAIError {
            guard case .confirmationRequired = error else {
                Issue.record("Expected confirmationRequired, got: \(error)")
                return
            }
        }

        // Delegate was consulted and rejected
        #expect(delegate.confirmCalls.count == 1)
        #expect(delegate.confirmCalls[0].statementKind == .delete)

        // Orders remain
        let count = try await db.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM orders WHERE user_id = 1")
        }
        #expect(count == 1, "Orders should NOT have been deleted")
    }

    @Test("Default delegate implementation rejects destructive operations")
    func defaultDelegateRejectsDestructive() async {
        struct DefaultDelegate: SwiftDBAI.ToolExecutionDelegate {}
        let delegate = DefaultDelegate()

        let context = DestructiveOperationContext(
            sql: "DELETE FROM users WHERE id = 1",
            statementKind: .delete,
            classification: .destructive(.delete),
            description: "Delete from users"
        )

        let approved = await delegate.confirmDestructiveOperation(context)
        #expect(approved == false, "Default delegate should reject destructive operations")
    }

    @Test("DELETE not in readOnly allowlist is rejected before delegate is consulted")
    func deleteNotInAllowlistRejectedEarly() async throws {
        let db = try makeTestDatabase()
        let delegate = ApprovingTrackingDelegate()
        let model = TestSequentialModel(responses: [
            "DELETE FROM users WHERE id = 1"
        ])

        // Read-only allowlist does NOT include DELETE
        let engine = ChatEngine(
            database: db,
            model: model,
            allowlist: .readOnly,
            delegate: delegate
        )

        do {
            _ = try await engine.send("Delete user 1")
            Issue.record("Expected operationNotAllowed error")
        } catch let error as SwiftDBAIError {
            guard case .operationNotAllowed(let operation) = error else {
                Issue.record("Expected operationNotAllowed, got: \(error)")
                return
            }
            #expect(operation == "delete")
        }

        // Delegate should NOT have been consulted — the allowlist rejects before delegation
        #expect(delegate.confirmCalls.isEmpty, "Delegate should not be consulted when op is not in allowlist")
    }
}

// MARK: - Tests: Destructive Operations Allowed When Delegate Approves

@Suite("Destructive Operations - Allowed When Delegate Approves")
struct DestructiveOperationsAllowedTests {

    @Test("DELETE succeeds when delegate approves")
    func deleteSucceedsWithApprovingDelegate() async throws {
        let db = try makeTestDatabase()
        let delegate = ApprovingTrackingDelegate()
        let model = TestSequentialModel(responses: [
            "DELETE FROM users WHERE id = 1",
            "Successfully deleted 1 user."
        ])

        let engine = ChatEngine(
            database: db,
            model: model,
            allowlist: .unrestricted,
            delegate: delegate
        )

        let response = try await engine.send("Delete user 1")

        // Delegate was consulted and approved
        #expect(delegate.confirmCalls.count == 1)
        #expect(delegate.confirmCalls[0].statementKind == .delete)
        #expect(delegate.confirmCalls[0].sql.uppercased().contains("DELETE"))
        #expect(delegate.confirmCalls[0].targetTable == "users")

        // SQL was executed
        #expect(delegate.willExecuteCalls.count == 1)
        #expect(delegate.didExecuteCalls.count == 1)
        #expect(delegate.didExecuteCalls[0].success == true)

        // Verify the data was actually deleted
        let count = try await db.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM users WHERE id = 1")
        }
        #expect(count == 0, "User should have been deleted")

        // Response should contain meaningful content
        #expect(response.sql?.uppercased().contains("DELETE") == true)
        #expect(response.queryResult != nil)
    }

    @Test("DELETE with MutationPolicy succeeds when delegate approves")
    func deleteWithPolicySucceedsWhenApproved() async throws {
        let db = try makeTestDatabase()
        let delegate = ApprovingTrackingDelegate()
        let model = TestSequentialModel(responses: [
            "DELETE FROM orders WHERE user_id = 2",
            "Deleted 1 order."
        ])

        let policy = MutationPolicy(
            allowedOperations: [.insert, .update, .delete],
            requiresDestructiveConfirmation: true
        )

        let engine = ChatEngine(
            database: db,
            model: model,
            mutationPolicy: policy,
            delegate: delegate
        )

        let response = try await engine.send("Delete all orders for user 2")

        // Delegate approved
        #expect(delegate.confirmCalls.count == 1)

        // Data was actually deleted
        let count = try await db.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM orders WHERE user_id = 2")
        }
        #expect(count == 0, "Orders should have been deleted")
        #expect(response.sql?.uppercased().contains("DELETE") == true)
    }

    @Test("AutoApproveDelegate allows DELETE without user interaction")
    func autoApproveDelegateAllowsDelete() async throws {
        let db = try makeTestDatabase()
        let delegate = AutoApproveDelegate()
        let model = TestSequentialModel(responses: [
            "DELETE FROM users WHERE id = 3",
            "Deleted 1 user."
        ])

        let engine = ChatEngine(
            database: db,
            model: model,
            allowlist: .unrestricted,
            delegate: delegate
        )

        let response = try await engine.send("Delete user 3")

        // Should succeed without error
        #expect(response.sql?.uppercased().contains("DELETE") == true)

        let count = try await db.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM users WHERE id = 3")
        }
        #expect(count == 0, "User should have been deleted")
    }

    @Test("sendConfirmed bypasses delegate and executes directly")
    func sendConfirmedBypassesDelegate() async throws {
        let db = try makeTestDatabase()
        let delegate = RejectingTrackingDelegate()
        let model = TestSequentialModel(responses: [
            "Deleted 1 user."
        ])

        let engine = ChatEngine(
            database: db,
            model: model,
            allowlist: .unrestricted,
            delegate: delegate
        )

        // sendConfirmed should execute directly without consulting the delegate for confirmation
        let response = try await engine.sendConfirmed(
            "Delete user 1",
            confirmedSQL: "DELETE FROM users WHERE id = 1"
        )

        // Delegate was NOT asked to confirm (sendConfirmed skips confirmation)
        #expect(delegate.confirmCalls.isEmpty)

        // But willExecute/didExecute hooks were still called
        #expect(delegate.willExecuteCalls.count == 1)
        #expect(delegate.didExecuteCalls.count == 1)
        #expect(delegate.didExecuteCalls[0].success == true)

        // Data was deleted
        let count = try await db.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM users WHERE id = 1")
        }
        #expect(count == 0)
        #expect(response.summary.contains("deleted") || response.summary.contains("Deleted") || response.summary.contains("1"))
    }
}

// MARK: - Tests: Delegate Context Correctness

@Suite("Destructive Operations - Delegate Context")
struct DestructiveOperationContextTests {

    @Test("Delegate receives correct context for DELETE on specific table")
    func delegateReceivesCorrectContext() async throws {
        let db = try makeTestDatabase()
        let delegate = RejectingTrackingDelegate()
        let model = TestSequentialModel(responses: [
            "DELETE FROM orders WHERE amount < 50"
        ])

        let engine = ChatEngine(
            database: db,
            model: model,
            allowlist: .unrestricted,
            delegate: delegate
        )

        do {
            _ = try await engine.send("Delete cheap orders")
            Issue.record("Expected confirmationRequired error")
        } catch is SwiftDBAIError {
            // Expected
        }

        #expect(delegate.confirmCalls.count == 1)
        let ctx = delegate.confirmCalls[0]
        #expect(ctx.statementKind == .delete)
        #expect(ctx.classification == .destructive(.delete))
        #expect(ctx.classification.requiresConfirmation == true)
        #expect(ctx.sql.uppercased().contains("DELETE FROM ORDERS"))
        #expect(ctx.targetTable == "orders")
        #expect(!ctx.description.isEmpty)
    }

    @Test("Non-destructive operations do not consult delegate")
    func selectDoesNotConsultDelegate() async throws {
        let db = try makeTestDatabase()
        let delegate = ApprovingTrackingDelegate()
        let model = TestSequentialModel(responses: [
            "SELECT COUNT(*) FROM users",
            "There are 3 users."
        ])

        let engine = ChatEngine(
            database: db,
            model: model,
            allowlist: .unrestricted,
            delegate: delegate
        )

        _ = try await engine.send("How many users?")

        // Delegate should NOT have been asked to confirm (SELECT is not destructive)
        #expect(delegate.confirmCalls.isEmpty)

        // But willExecute/didExecute should still be called (observation hooks)
        #expect(delegate.willExecuteCalls.count == 1)
        #expect(delegate.didExecuteCalls.count == 1)
    }

    @Test("INSERT does not require confirmation even with delegate")
    func insertDoesNotRequireConfirmation() async throws {
        let db = try makeTestDatabase()
        let delegate = RejectingTrackingDelegate()
        let model = TestSequentialModel(responses: [
            "INSERT INTO users (name, email) VALUES ('Dave', 'dave@example.com')",
            "Inserted 1 row."
        ])

        let engine = ChatEngine(
            database: db,
            model: model,
            allowlist: .standard,
            delegate: delegate
        )

        let response = try await engine.send("Add user Dave")

        // No confirmation needed for INSERT
        #expect(delegate.confirmCalls.isEmpty)
        #expect(response.sql?.uppercased().contains("INSERT") == true)

        // Verify the insert happened
        let count = try await db.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM users WHERE name = 'Dave'")
        }
        #expect(count == 1)
    }

    @Test("UPDATE does not require confirmation even with delegate")
    func updateDoesNotRequireConfirmation() async throws {
        let db = try makeTestDatabase()
        let delegate = RejectingTrackingDelegate()
        let model = TestSequentialModel(responses: [
            "UPDATE users SET email = 'alice-new@example.com' WHERE id = 1",
            "Updated 1 row."
        ])

        let engine = ChatEngine(
            database: db,
            model: model,
            allowlist: .standard,
            delegate: delegate
        )

        let response = try await engine.send("Update Alice's email")

        // No confirmation needed for UPDATE
        #expect(delegate.confirmCalls.isEmpty)
        #expect(response.sql?.uppercased().contains("UPDATE") == true)
    }
}

// MARK: - Tests: MutationPolicy Confirmation Flag

@Suite("Destructive Operations - MutationPolicy Confirmation Control")
struct MutationPolicyConfirmationTests {

    @Test("DELETE skips confirmation when requiresDestructiveConfirmation is false")
    func deleteSkipsConfirmationWhenDisabled() async throws {
        let db = try makeTestDatabase()
        let delegate = RejectingTrackingDelegate()
        let model = TestSequentialModel(responses: [
            "DELETE FROM users WHERE id = 1",
            "Deleted 1 user."
        ])

        let policy = MutationPolicy(
            allowedOperations: [.insert, .update, .delete],
            requiresDestructiveConfirmation: false  // Explicitly disabled
        )

        let engine = ChatEngine(
            database: db,
            model: model,
            mutationPolicy: policy,
            delegate: delegate
        )

        // Should succeed without confirmation since the policy disables it
        let response = try await engine.send("Delete user 1")

        // Delegate should NOT have been consulted for confirmation
        #expect(delegate.confirmCalls.isEmpty)

        // But the SQL should have executed
        #expect(response.sql?.uppercased().contains("DELETE") == true)

        let count = try await db.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM users WHERE id = 1")
        }
        #expect(count == 0, "User should have been deleted without confirmation")
    }

    @Test("MutationPolicy.requiresConfirmation only triggers for DELETE")
    func requiresConfirmationOnlyForDelete() {
        let policy = MutationPolicy(
            allowedOperations: [.insert, .update, .delete],
            requiresDestructiveConfirmation: true
        )

        #expect(policy.requiresConfirmation(for: .delete) == true)
        #expect(policy.requiresConfirmation(for: .select) == false)
        #expect(policy.requiresConfirmation(for: .insert) == false)
        #expect(policy.requiresConfirmation(for: .update) == false)
    }

    @Test("MutationPolicy.readOnly never requires confirmation (no delete allowed)")
    func readOnlyNeverRequiresConfirmation() {
        let policy = MutationPolicy.readOnly

        #expect(policy.requiresConfirmation(for: .select) == false)
        #expect(policy.requiresConfirmation(for: .delete) == true) // Would require confirmation IF allowed
        #expect(policy.isOperationAllowed(.delete) == false)       // But it's not allowed at all
    }

    @Test("Table-restricted DELETE is blocked for disallowed tables")
    func tableRestrictedDeleteBlocked() async throws {
        let db = try makeTestDatabase()
        let model = TestSequentialModel(responses: [
            "DELETE FROM users WHERE id = 1"
        ])

        let policy = MutationPolicy(
            allowedOperations: [.insert, .update, .delete],
            allowedTables: ["orders"],  // Only orders, NOT users
            requiresDestructiveConfirmation: true
        )

        let engine = ChatEngine(
            database: db,
            model: model,
            mutationPolicy: policy
        )

        do {
            _ = try await engine.send("Delete user 1")
            Issue.record("Expected tableNotAllowedForMutation error")
        } catch let error as SwiftDBAIError {
            guard case .tableNotAllowedForMutation(let tableName, let operation) = error else {
                Issue.record("Expected tableNotAllowedForMutation, got: \(error)")
                return
            }
            #expect(tableName == "users")
            #expect(operation == "delete")
        }

        // User was not deleted
        let count = try await db.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM users WHERE id = 1")
        }
        #expect(count == 1)
    }
}
