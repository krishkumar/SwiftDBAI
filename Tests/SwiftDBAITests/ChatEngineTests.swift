// ChatEngineTests.swift
// SwiftDBAI Tests
//
// Tests for ChatEngine with TextSummaryRenderer integration.

import AnyLanguageModel
import Foundation
import GRDB
import Testing

@testable import SwiftDBAI

@Suite("ChatEngine Tests")
struct ChatEngineTests {

    /// Creates an in-memory database with test data.
    private func makeTestDatabase() throws -> DatabaseQueue {
        let db = try DatabaseQueue(path: ":memory:")
        try db.write { db in
            try db.execute(sql: """
                CREATE TABLE users (
                    id INTEGER PRIMARY KEY,
                    name TEXT NOT NULL,
                    email TEXT NOT NULL,
                    created_at TEXT NOT NULL
                )
                """)
            try db.execute(sql: """
                INSERT INTO users (name, email, created_at) VALUES
                ('Alice', 'alice@example.com', '2024-01-01'),
                ('Bob', 'bob@example.com', '2024-01-15'),
                ('Charlie', 'charlie@example.com', '2024-02-01')
                """)
            try db.execute(sql: """
                CREATE TABLE orders (
                    id INTEGER PRIMARY KEY,
                    user_id INTEGER NOT NULL,
                    amount REAL NOT NULL,
                    status TEXT NOT NULL,
                    FOREIGN KEY (user_id) REFERENCES users(id)
                )
                """)
            try db.execute(sql: """
                INSERT INTO orders (user_id, amount, status) VALUES
                (1, 99.99, 'completed'),
                (1, 49.50, 'pending'),
                (2, 150.00, 'completed')
                """)
        }
        return db
    }

    @Test("ChatEngine summarizes SELECT results via TextSummaryRenderer")
    func selectResultSummarized() async throws {
        let db = try makeTestDatabase()

        // The mock model returns SQL for the first call, then a summary for the second
        let model = SequentialMockModel(responses: [
            "SELECT COUNT(*) FROM users",
            "There are 3 users in the database."
        ])

        let engine = ChatEngine(
            database: db,
            model: model
        )

        let response = try await engine.send("How many users are there?")

        // The summary should come from TextSummaryRenderer.
        // For a single aggregate (COUNT), TextSummaryRenderer returns a direct answer
        // without calling the LLM again, so the summary is template-based.
        #expect(response.summary == "The result is 3.")
        #expect(response.sql == "SELECT COUNT(*) FROM users")
        #expect(response.queryResult != nil)
        #expect(response.queryResult?.rowCount == 1)
    }

    @Test("ChatEngine summarizes empty results correctly")
    func emptyResultSummarized() async throws {
        let db = try makeTestDatabase()

        let model = SequentialMockModel(responses: [
            "SELECT * FROM users WHERE name = 'Nobody'",
            "No results found."
        ])

        let engine = ChatEngine(
            database: db,
            model: model
        )

        let response = try await engine.send("Find a user named Nobody")

        #expect(response.summary == "No results found for your query.")
        #expect(response.queryResult?.rows.isEmpty == true)
    }

    @Test("ChatEngine summarizes multi-row results via LLM")
    func multiRowResultSummarized() async throws {
        let db = try makeTestDatabase()

        let model = SequentialMockModel(responses: [
            "SELECT name, email FROM users",
            "Found 3 users: Alice, Bob, and Charlie."
        ])

        let engine = ChatEngine(
            database: db,
            model: model
        )

        let response = try await engine.send("List all users")

        // Multi-row results go through the LLM summarization path
        #expect(response.summary == "Found 3 users: Alice, Bob, and Charlie.")
        #expect(response.queryResult?.rowCount == 3)
    }

    @Test("ChatEngine rejects disallowed operations via SQLQueryParser")
    func rejectsDisallowedOperations() async throws {
        let db = try makeTestDatabase()

        let model = SequentialMockModel(responses: [
            "DELETE FROM users WHERE id = 1"
        ])

        let engine = ChatEngine(
            database: db,
            model: model,
            allowlist: .readOnly
        )

        // DELETE is not in the readOnly allowlist, so SQLQueryParser rejects it
        // ChatEngine now maps this to SwiftDBAIError.operationNotAllowed
        await #expect(throws: SwiftDBAIError.self) {
            try await engine.send("Delete user 1")
        }
    }

    @Test("ChatEngine requires confirmation for DELETE even when allowed")
    func requiresDeleteConfirmation() async throws {
        let db = try makeTestDatabase()

        let model = SequentialMockModel(responses: [
            "DELETE FROM users WHERE id = 3",
            "Deleted 1 row."
        ])

        let engine = ChatEngine(
            database: db,
            model: model,
            allowlist: .unrestricted
        )

        // DELETE requires confirmation even when allowlisted
        // ChatEngine now surfaces SwiftDBAIError.confirmationRequired
        do {
            _ = try await engine.send("Delete user 3")
            Issue.record("Expected confirmationRequired error")
        } catch let error as SwiftDBAIError {
            if case .confirmationRequired(let sql, let operation) = error {
                #expect(sql.uppercased().contains("DELETE"))
                #expect(operation == "delete")

                // Now confirm and execute
                let response = try await engine.sendConfirmed("Delete user 3", confirmedSQL: sql)
                #expect(response.summary == "Successfully deleted 1 row.")
            } else {
                Issue.record("Expected confirmationRequired, got: \(error)")
            }
        }
    }

    @Test("ChatEngine allows mutations when allowlisted")
    func allowsMutationsWhenAllowlisted() async throws {
        let db = try makeTestDatabase()

        let model = SequentialMockModel(responses: [
            "INSERT INTO users (name, email, created_at) VALUES ('Dave', 'dave@example.com', '2024-03-01')",
            "Inserted 1 row."
        ])

        let engine = ChatEngine(
            database: db,
            model: model,
            allowlist: .standard
        )

        let response = try await engine.send("Add a user named Dave")

        #expect(response.summary == "Successfully inserted 1 row.")
    }

    @Test("ChatEngine rejects dangerous operations via SQLQueryParser")
    func rejectsDangerousOperations() async throws {
        let db = try makeTestDatabase()

        let model = SequentialMockModel(responses: [
            "DROP TABLE users"
        ])

        let engine = ChatEngine(
            database: db,
            model: model,
            allowlist: .unrestricted
        )

        // DROP is always rejected by SQLQueryParser regardless of allowlist
        // ChatEngine now maps this to SwiftDBAIError.dangerousOperationBlocked
        await #expect(throws: SwiftDBAIError.self) {
            try await engine.send("Drop the users table")
        }
    }

    @Test("ChatEngine executes UPDATE and returns affected row count")
    func updateMutationReturnsAffectedCount() async throws {
        let db = try makeTestDatabase()

        let model = SequentialMockModel(responses: [
            "UPDATE users SET name = 'Alice Updated' WHERE id = 1",
        ])

        let engine = ChatEngine(
            database: db,
            model: model,
            allowlist: .standard
        )

        let response = try await engine.send("Rename user 1 to Alice Updated")

        #expect(response.summary == "Successfully updated 1 row.")
        #expect(response.sql?.uppercased().contains("UPDATE") == true)
        #expect(response.queryResult?.rowsAffected == 1)
    }

    @Test("ChatEngine UPDATE affecting multiple rows returns correct count")
    func updateMultipleRowsReturnsCorrectCount() async throws {
        let db = try makeTestDatabase()

        let model = SequentialMockModel(responses: [
            "UPDATE orders SET status = 'archived' WHERE status = 'completed'",
        ])

        let engine = ChatEngine(
            database: db,
            model: model,
            allowlist: .standard
        )

        let response = try await engine.send("Archive all completed orders")

        // There are 2 completed orders in the test data
        #expect(response.summary == "Successfully updated 2 rows.")
        #expect(response.queryResult?.rowsAffected == 2)
    }

    @Test("ChatEngine rejects INSERT on readOnly allowlist with clear error")
    func rejectsInsertOnReadOnly() async throws {
        let db = try makeTestDatabase()

        let model = SequentialMockModel(responses: [
            "INSERT INTO users (name, email, created_at) VALUES ('Eve', 'eve@example.com', '2024-03-15')"
        ])

        let engine = ChatEngine(
            database: db,
            model: model,
            allowlist: .readOnly
        )

        do {
            _ = try await engine.send("Add a user named Eve")
            Issue.record("Expected operationNotAllowed error for disallowed INSERT")
        } catch let error as SwiftDBAIError {
            if case .operationNotAllowed(let operation) = error {
                #expect(operation == "insert")
            } else {
                Issue.record("Expected operationNotAllowed, got: \(error)")
            }
        }
    }

    @Test("ChatEngine rejects UPDATE on readOnly allowlist with clear error")
    func rejectsUpdateOnReadOnly() async throws {
        let db = try makeTestDatabase()

        let model = SequentialMockModel(responses: [
            "UPDATE users SET name = 'Eve' WHERE id = 1"
        ])

        let engine = ChatEngine(
            database: db,
            model: model,
            allowlist: .readOnly
        )

        do {
            _ = try await engine.send("Rename user 1 to Eve")
            Issue.record("Expected operationNotAllowed error for disallowed UPDATE")
        } catch let error as SwiftDBAIError {
            if case .operationNotAllowed(let operation) = error {
                #expect(operation == "update")
            } else {
                Issue.record("Expected operationNotAllowed, got: \(error)")
            }
        }
    }

    @Test("ChatEngine with MutationPolicy rejects mutations on restricted tables")
    func mutationPolicyRejectsRestrictedTables() async throws {
        let db = try makeTestDatabase()

        let model = SequentialMockModel(responses: [
            "INSERT INTO users (name, email, created_at) VALUES ('Eve', 'eve@example.com', '2024-03-15')"
        ])

        // Only allow mutations on the "orders" table
        let policy = MutationPolicy(
            allowedOperations: [.insert, .update],
            allowedTables: ["orders"]
        )

        let engine = ChatEngine(
            database: db,
            model: model,
            mutationPolicy: policy
        )

        do {
            _ = try await engine.send("Add a user named Eve")
            Issue.record("Expected tableNotAllowedForMutation error for restricted table")
        } catch let error as SwiftDBAIError {
            if case .tableNotAllowedForMutation(let tableName, let operation) = error {
                #expect(tableName == "users")
                #expect(operation == "insert")
            } else {
                Issue.record("Expected tableNotAllowedForMutation, got: \(error)")
            }
        }
    }

    @Test("ChatEngine with MutationPolicy allows mutations on permitted tables")
    func mutationPolicyAllowsPermittedTables() async throws {
        let db = try makeTestDatabase()

        let model = SequentialMockModel(responses: [
            "INSERT INTO orders (user_id, amount, status) VALUES (1, 75.00, 'pending')",
        ])

        // Only allow mutations on the "orders" table
        let policy = MutationPolicy(
            allowedOperations: [.insert, .update],
            allowedTables: ["orders"]
        )

        let engine = ChatEngine(
            database: db,
            model: model,
            mutationPolicy: policy
        )

        let response = try await engine.send("Add a new order for user 1")

        #expect(response.summary == "Successfully inserted 1 row.")
        #expect(response.queryResult?.rowsAffected == 1)
    }

    @Test("ChatEngine INSERT affecting zero rows returns correct message")
    func insertZeroRowsMessage() async throws {
        let db = try makeTestDatabase()

        // INSERT OR IGNORE with a conflicting primary key won't insert
        let model = SequentialMockModel(responses: [
            "INSERT OR IGNORE INTO users (id, name, email, created_at) VALUES (1, 'Alice', 'alice@example.com', '2024-01-01')",
        ])

        let engine = ChatEngine(
            database: db,
            model: model,
            allowlist: .standard
        )

        let response = try await engine.send("Add user Alice if not exists")

        // With OR IGNORE, the duplicate is silently skipped → 0 rows affected
        #expect(response.summary == "Successfully inserted 0 rows.")
        #expect(response.queryResult?.rowsAffected == 0)
    }

    @Test("ChatEngine error descriptions are human-readable")
    func errorDescriptionsAreReadable() {
        // SwiftDBAIError — the unified error type surfaced by ChatEngine
        let opError = SwiftDBAIError.operationNotAllowed(operation: "delete")
        #expect(opError.errorDescription?.contains("DELETE") == true)
        #expect(opError.errorDescription?.contains("not allowed") == true)

        let confirmError = SwiftDBAIError.confirmationRequired(
            sql: "DELETE FROM users WHERE id = 1",
            operation: "delete"
        )
        #expect(confirmError.errorDescription?.contains("confirmation") == true)
        #expect(confirmError.errorDescription?.contains("DELETE") == true)

        let timeoutError = SwiftDBAIError.queryTimedOut(seconds: 30)
        #expect(timeoutError.errorDescription?.contains("timed out") == true)

        let dbError = SwiftDBAIError.databaseError(reason: "disk full")
        #expect(dbError.errorDescription?.contains("disk full") == true)

        let llmError = SwiftDBAIError.llmFailure(reason: "rate limited")
        #expect(llmError.errorDescription?.contains("rate limited") == true)

        let schemaError = SwiftDBAIError.schemaIntrospectionFailed(reason: "permission denied")
        #expect(schemaError.errorDescription?.contains("permission denied") == true)

        let noSQLError = SwiftDBAIError.noSQLGenerated
        #expect(noSQLError.errorDescription?.contains("rephrase") == true)

        let dangerousError = SwiftDBAIError.dangerousOperationBlocked(keyword: "DROP")
        #expect(dangerousError.errorDescription?.contains("DROP") == true)

        let emptyError = SwiftDBAIError.emptySchema
        #expect(emptyError.errorDescription?.contains("no tables") == true)

        let tableError = SwiftDBAIError.tableNotAllowedForMutation(tableName: "users", operation: "insert")
        #expect(tableError.errorDescription?.contains("users") == true)
        #expect(tableError.errorDescription?.contains("INSERT") == true)

        let multiError = SwiftDBAIError.multipleStatementsNotSupported
        #expect(multiError.errorDescription?.contains("single") == true)
    }

    @Test("SwiftDBAIError classification properties")
    func errorClassificationProperties() {
        // Safety errors
        #expect(SwiftDBAIError.operationNotAllowed(operation: "delete").isSafetyError)
        #expect(SwiftDBAIError.dangerousOperationBlocked(keyword: "DROP").isSafetyError)
        #expect(SwiftDBAIError.confirmationRequired(sql: "", operation: "delete").isSafetyError)
        #expect(!SwiftDBAIError.llmFailure(reason: "timeout").isSafetyError)

        // Recoverable errors
        #expect(SwiftDBAIError.noSQLGenerated.isRecoverable)
        #expect(SwiftDBAIError.tableNotFound(tableName: "x").isRecoverable)
        #expect(!SwiftDBAIError.databaseError(reason: "disk full").isRecoverable)

        // User action required
        #expect(SwiftDBAIError.confirmationRequired(sql: "", operation: "delete").requiresUserAction)
        #expect(!SwiftDBAIError.llmFailure(reason: "error").requiresUserAction)
    }

    @Test("SQLParsingError converts to SwiftDBAIError correctly")
    func sqlParsingErrorConversion() {
        let noSQL = SQLParsingError.noSQLFound.toSwiftDBAIError()
        #expect(noSQL == .noSQLGenerated)

        let noSQLWithResponse = SQLParsingError.noSQLFound.toSwiftDBAIError(rawResponse: "I can't do that")
        if case .llmResponseUnparseable(let response) = noSQLWithResponse {
            #expect(response == "I can't do that")
        } else {
            Issue.record("Expected llmResponseUnparseable")
        }

        let opNotAllowed = SQLParsingError.operationNotAllowed(.delete).toSwiftDBAIError()
        #expect(opNotAllowed == .operationNotAllowed(operation: "delete"))

        let dangerous = SQLParsingError.dangerousOperation("DROP").toSwiftDBAIError()
        #expect(dangerous == .dangerousOperationBlocked(keyword: "DROP"))

        let multi = SQLParsingError.multipleStatements.toSwiftDBAIError()
        #expect(multi == .multipleStatementsNotSupported)

        let tableNotAllowed = SQLParsingError.tableNotAllowed(table: "users", operation: .insert).toSwiftDBAIError()
        #expect(tableNotAllowed == .tableNotAllowedForMutation(tableName: "users", operation: "insert"))
    }

    @Test("ChatEngineError legacy type still has correct descriptions")
    func legacyChatEngineErrorDescriptions() {
        let sqlError = ChatEngineError.sqlParsingFailed(.operationNotAllowed(.delete))
        #expect(sqlError.errorDescription?.contains("DELETE") == true)

        let timeoutError = ChatEngineError.queryTimedOut(seconds: 30)
        #expect(timeoutError.errorDescription?.contains("timed out") == true)

        let validationError = ChatEngineError.validationFailed("too many rows")
        #expect(validationError.errorDescription?.contains("too many rows") == true)
    }

    @Test("ChatEngine maintains conversation history")
    func maintainsHistory() async throws {
        let db = try makeTestDatabase()

        // Both queries produce aggregates, so TextSummaryRenderer won't call
        // the LLM for summarization — only SQL generation consumes responses.
        let model = SequentialMockModel(responses: [
            "SELECT COUNT(*) FROM users",
            "SELECT COUNT(*) FROM orders",
        ])

        let engine = ChatEngine(
            database: db,
            model: model
        )

        _ = try await engine.send("How many users?")
        _ = try await engine.send("How many orders?")

        let messages = engine.messages
        #expect(messages.count == 4)  // 2 user + 2 assistant
        #expect(messages[0].role == .user)
        #expect(messages[1].role == .assistant)
        #expect(messages[2].role == .user)
        #expect(messages[3].role == .assistant)
    }

    @Test("ChatEngine parses SQL from markdown code fences via SQLQueryParser")
    func parsesCodeFences() async throws {
        let db = try makeTestDatabase()

        let model = SequentialMockModel(responses: [
            "```sql\nSELECT COUNT(*) FROM users\n```",
            "There are 3 users."
        ])

        let engine = ChatEngine(
            database: db,
            model: model
        )

        let response = try await engine.send("Count users")

        #expect(response.sql == "SELECT COUNT(*) FROM users")
        #expect(response.queryResult?.rowCount == 1)
    }

    @Test("ChatEngine parses SQL from labeled LLM responses")
    func parsesLabeledSQL() async throws {
        let db = try makeTestDatabase()

        let model = SequentialMockModel(responses: [
            "SQL: SELECT COUNT(*) FROM users",
            "There are 3 users."
        ])

        let engine = ChatEngine(
            database: db,
            model: model
        )

        let response = try await engine.send("Count users")

        #expect(response.sql == "SELECT COUNT(*) FROM users")
        #expect(response.queryResult?.rowCount == 1)
    }

    @Test("ChatEngine prepareSchema eagerly introspects and caches schema")
    func prepareSchemaEagerly() async throws {
        let db = try makeTestDatabase()
        let model = MockLanguageModel()

        let engine = ChatEngine(database: db, model: model)

        // Before prepare, no cached schema
        #expect(engine.tableCount == nil)
        #expect(engine.cachedSchema == nil)

        // Prepare eagerly
        let schema = try await engine.prepareSchema()

        // Schema is now cached
        #expect(schema.tableNames.count == 2)
        #expect(schema.tableNames.contains("users"))
        #expect(schema.tableNames.contains("orders"))
        #expect(engine.tableCount == 2)
        #expect(engine.cachedSchema != nil)
    }

    @Test("ChatEngine prepareSchema is idempotent")
    func prepareSchemaIdempotent() async throws {
        let db = try makeTestDatabase()
        let model = MockLanguageModel()

        let engine = ChatEngine(database: db, model: model)

        let schema1 = try await engine.prepareSchema()
        let schema2 = try await engine.prepareSchema()

        #expect(schema1 == schema2)
        #expect(engine.tableCount == 2)
    }

    @Test("ChatEngine injects conversation history into follow-up prompts")
    func injectsConversationHistory() async throws {
        let db = try makeTestDatabase()

        // Use a prompt-capturing mock so we can verify what the LLM receives.
        // First call: SQL gen for "How many users?" → aggregate, no LLM summary needed.
        // Second call: SQL gen for follow-up "What about orders?" — should contain history.
        let mock = PromptCapturingMockModel(responses: [
            "SELECT COUNT(*) FROM users",
            "SELECT COUNT(*) FROM orders",
        ])

        let engine = ChatEngine(
            database: db,
            model: mock
        )

        // First turn
        _ = try await engine.send("How many users?")

        // Second turn — follow-up
        _ = try await engine.send("What about orders?")

        // The second prompt should contain conversation history from the first turn
        let prompts = mock.capturedPrompts
        #expect(prompts.count >= 2)

        let followUpPrompt = prompts[1]
        // Should include conversation history markers
        #expect(followUpPrompt.contains("CONVERSATION HISTORY"))
        // Should include the prior user message
        #expect(followUpPrompt.contains("How many users?"))
        // Should include the prior assistant SQL
        #expect(followUpPrompt.contains("SELECT COUNT(*) FROM users"))
        // Should include the current question
        #expect(followUpPrompt.contains("What about orders?"))
    }

    @Test("ChatEngine respects context window size for history injection")
    func respectsContextWindowSize() async throws {
        let db = try makeTestDatabase()

        let mock = PromptCapturingMockModel(responses: [
            "SELECT COUNT(*) FROM users",
            "SELECT COUNT(*) FROM orders",
            "SELECT COUNT(*) FROM users WHERE name = 'Alice'",
        ])

        // Context window of 2 messages means only the most recent 2 are included
        let config = ChatEngineConfiguration(
            queryTimeout: nil,
            contextWindowSize: 2
        )
        let engine = ChatEngine(
            database: db,
            model: mock,
            configuration: config
        )

        _ = try await engine.send("How many users?")
        _ = try await engine.send("How many orders?")
        _ = try await engine.send("Find Alice")

        let prompts = mock.capturedPrompts
        #expect(prompts.count >= 3)

        let thirdPrompt = prompts[2]
        // With contextWindowSize=2, only the last 2 messages (user + assistant from
        // second turn) should be in the history — NOT the first turn.
        #expect(thirdPrompt.contains("CONVERSATION HISTORY"))
        #expect(thirdPrompt.contains("How many orders?"))
        // First turn should be trimmed out
        #expect(!thirdPrompt.contains("How many users?"))
    }

    @Test("ChatEngine reset clears history and schema cache")
    func resetClearsState() async throws {
        let db = try makeTestDatabase()

        let model = SequentialMockModel(responses: [
            "SELECT COUNT(*) FROM users",
            "3 users"
        ])

        let engine = ChatEngine(
            database: db,
            model: model
        )

        _ = try await engine.send("Count users")
        #expect(engine.messages.count == 2)

        engine.reset()
        #expect(engine.messages.isEmpty)
    }

    // MARK: - Configuration & Extensibility Tests

    @Test("ChatEngine clearHistory keeps schema but removes messages")
    func clearHistoryKeepsSchema() async throws {
        let db = try makeTestDatabase()

        let model = SequentialMockModel(responses: [
            "SELECT COUNT(*) FROM users",
        ])

        let engine = ChatEngine(database: db, model: model)

        _ = try await engine.send("Count users")
        #expect(engine.messages.count == 2)
        #expect(engine.cachedSchema != nil)

        engine.clearHistory()
        #expect(engine.messages.isEmpty)
        #expect(engine.cachedSchema != nil)
        #expect(engine.tableCount == 2)
    }

    @Test("ChatEngine reset clears both history and schema")
    func resetClearsAll() async throws {
        let db = try makeTestDatabase()

        let model = SequentialMockModel(responses: [
            "SELECT COUNT(*) FROM users",
        ])

        let engine = ChatEngine(database: db, model: model)

        _ = try await engine.send("Count users")
        #expect(engine.cachedSchema != nil)

        engine.reset()
        #expect(engine.messages.isEmpty)
        #expect(engine.cachedSchema == nil)
        #expect(engine.tableCount == nil)
    }

    @Test("ChatEngine exposes currentConfiguration")
    func exposesConfiguration() async throws {
        let db = try makeTestDatabase()
        let model = MockLanguageModel()

        var config = ChatEngineConfiguration(
            queryTimeout: 15,
            contextWindowSize: 10,
            maxSummaryRows: 25,
            additionalContext: "Test context"
        )
        config.addValidator(TableAllowlistValidator(allowedTables: ["users"]))

        let engine = ChatEngine(
            database: db,
            model: model,
            configuration: config
        )

        let readConfig = engine.currentConfiguration
        #expect(readConfig.queryTimeout == 15)
        #expect(readConfig.contextWindowSize == 10)
        #expect(readConfig.maxSummaryRows == 25)
        #expect(readConfig.additionalContext == "Test context")
        #expect(readConfig.validators.count == 1)
    }

    @Test("ChatEngineConfiguration default has expected values")
    func defaultConfiguration() async throws {
        let config = ChatEngineConfiguration.default
        #expect(config.queryTimeout == 30)
        #expect(config.contextWindowSize == 50)
        #expect(config.maxSummaryRows == 50)
        #expect(config.additionalContext == nil)
        #expect(config.validators.isEmpty)
    }

    @Test("ChatEngine custom validator rejects forbidden queries")
    func customValidatorRejects() async throws {
        let db = try makeTestDatabase()

        let model = SequentialMockModel(responses: [
            "SELECT * FROM orders"
        ])

        var config = ChatEngineConfiguration(queryTimeout: nil)
        config.addValidator(TableAllowlistValidator(allowedTables: ["users"]))

        let engine = ChatEngine(
            database: db,
            model: model,
            configuration: config
        )

        await #expect(throws: QueryValidationError.self) {
            try await engine.send("Show all orders")
        }
    }

    @Test("ChatEngine custom validator allows permitted queries")
    func customValidatorAllows() async throws {
        let db = try makeTestDatabase()

        let model = SequentialMockModel(responses: [
            "SELECT COUNT(*) FROM users"
        ])

        var config = ChatEngineConfiguration(queryTimeout: nil)
        config.addValidator(TableAllowlistValidator(allowedTables: ["users"]))

        let engine = ChatEngine(
            database: db,
            model: model,
            configuration: config
        )

        let response = try await engine.send("Count users")
        #expect(response.sql == "SELECT COUNT(*) FROM users")
    }

    @Test("MaxRowLimitValidator rejects SELECT without LIMIT")
    func maxRowLimitRejectsNoLimit() throws {
        let validator = MaxRowLimitValidator(maxRows: 100)

        #expect(throws: QueryValidationError.self) {
            try validator.validate(sql: "SELECT * FROM users", operation: .select)
        }
    }

    @Test("MaxRowLimitValidator allows SELECT with acceptable LIMIT")
    func maxRowLimitAllowsAcceptable() throws {
        let validator = MaxRowLimitValidator(maxRows: 100)
        try validator.validate(sql: "SELECT * FROM users LIMIT 50", operation: .select)
    }

    @Test("MaxRowLimitValidator rejects SELECT with excessive LIMIT")
    func maxRowLimitRejectsExcessive() throws {
        let validator = MaxRowLimitValidator(maxRows: 100)

        #expect(throws: QueryValidationError.self) {
            try validator.validate(sql: "SELECT * FROM users LIMIT 500", operation: .select)
        }
    }

    @Test("MaxRowLimitValidator ignores non-SELECT operations")
    func maxRowLimitIgnoresNonSelect() throws {
        let validator = MaxRowLimitValidator(maxRows: 100)
        try validator.validate(
            sql: "INSERT INTO users (name) VALUES ('Dave')",
            operation: .insert
        )
    }

    @Test("Multiple validators run in order, second rejects")
    func multipleValidatorsRunInOrder() async throws {
        let db = try makeTestDatabase()

        let model = SequentialMockModel(responses: [
            "SELECT * FROM users LIMIT 200"
        ])

        var config = ChatEngineConfiguration(queryTimeout: nil)
        config.addValidator(TableAllowlistValidator(allowedTables: ["users", "orders"]))
        config.addValidator(MaxRowLimitValidator(maxRows: 100))

        let engine = ChatEngine(
            database: db,
            model: model,
            configuration: config
        )

        // Table is allowed, but LIMIT 200 exceeds MaxRowLimitValidator
        await #expect(throws: QueryValidationError.self) {
            try await engine.send("Show all users")
        }
    }

    @Test("ChatEngine nil timeout does not time out")
    func nilTimeoutNoTimeout() async throws {
        let db = try makeTestDatabase()

        let model = SequentialMockModel(responses: [
            "SELECT COUNT(*) FROM users",
        ])

        let config = ChatEngineConfiguration(queryTimeout: nil)

        let engine = ChatEngine(
            database: db,
            model: model,
            configuration: config
        )

        let response = try await engine.send("Count users")
        #expect(response.summary == "The result is 3.")
    }

    @Test("ChatEngine convenience init works with backward-compatible params")
    func convenienceInitBackwardCompat() async throws {
        let db = try makeTestDatabase()

        let model = SequentialMockModel(responses: [
            "SELECT COUNT(*) FROM users",
        ])

        let engine = ChatEngine(
            database: db,
            model: model,
            allowlist: .readOnly,
            additionalContext: "Test context",
            maxSummaryRows: 25
        )

        let config = engine.currentConfiguration
        #expect(config.maxSummaryRows == 25)
        #expect(config.additionalContext == "Test context")

        let response = try await engine.send("Count users")
        #expect(response.summary == "The result is 3.")
    }

    @Test("ChatEngine context window preserves full history for UI")
    func contextWindowPreservesFullHistory() async throws {
        let db = try makeTestDatabase()

        let model = SequentialMockModel(responses: [
            "SELECT COUNT(*) FROM users",
            "SELECT COUNT(*) FROM orders",
            "SELECT COUNT(*) FROM users WHERE name = 'Alice'",
        ])

        let config = ChatEngineConfiguration(queryTimeout: nil, contextWindowSize: 2)

        let engine = ChatEngine(
            database: db,
            model: model,
            configuration: config
        )

        _ = try await engine.send("Count users")
        _ = try await engine.send("Count orders")
        _ = try await engine.send("Find Alice")

        // Full history preserved for UI even though context window is 2
        #expect(engine.messages.count == 6)
    }

    @Test("ChatEngineError queryTimedOut has correct description")
    func queryTimedOutDescription() {
        let error = ChatEngineError.queryTimedOut(seconds: 30)
        #expect(error.errorDescription == "Query timed out after 30 seconds.")
    }

    @Test("ChatEngineError validationFailed has correct description")
    func validationFailedDescription() {
        let error = ChatEngineError.validationFailed("test reason")
        #expect(error.errorDescription == "Query validation failed: test reason")
    }

    @Test("QueryValidationError rejected has correct description")
    func queryValidationErrorDescription() {
        let error = QueryValidationError.rejected("bad query")
        #expect(error.errorDescription == "Query rejected: bad query")
    }
}

// MARK: - Prompt-Capturing Mock Model

/// A mock that captures prompts for inspection while returning predetermined responses.
final class PromptCapturingMockModel: LanguageModel, @unchecked Sendable {
    typealias UnavailableReason = Never

    let responses: [String]
    private let callCounter = CallCounter()
    private let _capturedPrompts: CapturedPrompts

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

    private final class CapturedPrompts: @unchecked Sendable {
        var prompts: [String] = []
        let lock = NSLock()
        func append(_ prompt: String) {
            lock.lock()
            defer { lock.unlock() }
            prompts.append(prompt)
        }
        var all: [String] {
            lock.lock()
            defer { lock.unlock() }
            return prompts
        }
    }

    var capturedPrompts: [String] { _capturedPrompts.all }

    init(responses: [String]) {
        self.responses = responses
        self._capturedPrompts = CapturedPrompts()
    }

    func respond<Content>(
        within session: LanguageModelSession,
        to prompt: Prompt,
        generating type: Content.Type,
        includeSchemaInPrompt: Bool,
        options: GenerationOptions
    ) async throws -> LanguageModelSession.Response<Content> where Content: Generable {
        _capturedPrompts.append(prompt.description)
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
        _capturedPrompts.append(prompt.description)
        let idx = callCounter.next()
        let text = idx < responses.count ? responses[idx] : "fallback response"
        let rawContent = GeneratedContent(kind: .string(text))
        let content = try! Content(rawContent)
        return LanguageModelSession.ResponseStream(content: content, rawContent: rawContent)
    }
}

// MARK: - Sequential Mock Model

/// A mock that returns different responses for successive calls.
struct SequentialMockModel: LanguageModel {
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
