// MultiTurnContextTests.swift
// SwiftDBAI Tests
//
// Tests verifying multi-turn conversation context — follow-up queries
// correctly reference the prior query's table, columns, and results.

import AnyLanguageModel
import Foundation
import GRDB
import Testing

@testable import SwiftDBAI

@Suite("Multi-Turn Context Tests")
struct MultiTurnContextTests {

    // MARK: - Test Database Setup

    /// Creates an in-memory database with users (including age) and orders.
    private func makeTestDatabase() throws -> DatabaseQueue {
        let db = try DatabaseQueue(path: ":memory:")
        try db.write { db in
            try db.execute(sql: """
                CREATE TABLE users (
                    id INTEGER PRIMARY KEY,
                    name TEXT NOT NULL,
                    age INTEGER NOT NULL,
                    email TEXT NOT NULL,
                    city TEXT NOT NULL
                )
                """)
            try db.execute(sql: """
                INSERT INTO users (name, age, email, city) VALUES
                ('Alice', 25, 'alice@example.com', 'New York'),
                ('Bob', 35, 'bob@example.com', 'San Francisco'),
                ('Charlie', 42, 'charlie@example.com', 'New York'),
                ('Diana', 28, 'diana@example.com', 'Chicago'),
                ('Eve', 55, 'eve@example.com', 'San Francisco')
                """)
            try db.execute(sql: """
                CREATE TABLE orders (
                    id INTEGER PRIMARY KEY,
                    user_id INTEGER NOT NULL,
                    amount REAL NOT NULL,
                    status TEXT NOT NULL,
                    created_at TEXT NOT NULL,
                    FOREIGN KEY (user_id) REFERENCES users(id)
                )
                """)
            try db.execute(sql: """
                INSERT INTO orders (user_id, amount, status, created_at) VALUES
                (1, 99.99, 'completed', '2024-01-15'),
                (1, 49.50, 'pending', '2024-02-20'),
                (2, 150.00, 'completed', '2024-01-10'),
                (3, 200.00, 'completed', '2024-03-01'),
                (4, 75.00, 'cancelled', '2024-02-05')
                """)
        }
        return db
    }

    // MARK: - Multi-Turn Context Tests

    @Test("Follow-up 'filter those by age > 30' references prior 'show all users' context")
    func followUpFilterReferencesUsersTable() async throws {
        let db = try makeTestDatabase()

        // Turn 1: "show all users" → SELECT * FROM users (returns 5 rows, LLM summary needed)
        // Turn 2: "filter those by age > 30" → should reference users table from context
        let mock = PromptCapturingMockModel(responses: [
            "SELECT * FROM users",
            "Here are all 5 users in the database.",
            "SELECT * FROM users WHERE age > 30",
            "Found 3 users over 30: Bob (35), Charlie (42), and Eve (55)."
        ])

        let engine = ChatEngine(database: db, model: mock)

        // First turn: show all users
        let response1 = try await engine.send("show all users")
        #expect(response1.sql == "SELECT * FROM users")
        #expect(response1.queryResult?.rowCount == 5)

        // Second turn: follow-up with implicit reference
        let response2 = try await engine.send("filter those by age > 30")
        #expect(response2.sql == "SELECT * FROM users WHERE age > 30")
        #expect(response2.queryResult?.rowCount == 3)

        // Verify the follow-up prompt includes conversation history
        let prompts = mock.capturedPrompts
        // Find the prompt for the second SQL generation (skip summary prompts)
        let followUpSQLPrompt = prompts.first { prompt in
            prompt.contains("filter those by age > 30") && prompt.contains("CONVERSATION HISTORY")
        }
        #expect(followUpSQLPrompt != nil, "Follow-up prompt should contain CONVERSATION HISTORY")

        // The conversation history should include the prior query and its SQL
        if let prompt = followUpSQLPrompt {
            #expect(prompt.contains("show all users"), "History should contain prior user message")
            #expect(prompt.contains("SELECT * FROM users"), "History should contain prior SQL")
            #expect(prompt.contains("filter those by age > 30"), "Prompt should contain current question")
        }
    }

    @Test("Follow-up correctly inherits table context across multiple turns")
    func multipleFollowUpsInheritContext() async throws {
        let db = try makeTestDatabase()

        // 3-turn conversation narrowing down results
        let mock = PromptCapturingMockModel(responses: [
            "SELECT * FROM users",
            "Here are all 5 users.",
            "SELECT * FROM users WHERE city = 'New York'",
            "Found 2 users in New York: Alice and Charlie.",
            "SELECT * FROM users WHERE city = 'New York' AND age > 30",
            "Charlie (42) is the only New York user over 30."
        ])

        let engine = ChatEngine(database: db, model: mock)

        // Turn 1
        _ = try await engine.send("show all users")

        // Turn 2 — narrows by city
        let response2 = try await engine.send("only those in New York")
        #expect(response2.sql == "SELECT * FROM users WHERE city = 'New York'")
        #expect(response2.queryResult?.rowCount == 2)

        // Turn 3 — further narrows by age
        let response3 = try await engine.send("now filter by age over 30")
        #expect(response3.sql == "SELECT * FROM users WHERE city = 'New York' AND age > 30")
        #expect(response3.queryResult?.rowCount == 1)

        // Verify third turn's prompt includes the full conversation history
        let prompts = mock.capturedPrompts
        let thirdTurnPrompt = prompts.last { prompt in
            prompt.contains("now filter by age over 30") && prompt.contains("CONVERSATION HISTORY")
        }
        #expect(thirdTurnPrompt != nil)

        if let prompt = thirdTurnPrompt {
            // Should include both prior user messages
            #expect(prompt.contains("show all users"))
            #expect(prompt.contains("only those in New York"))
            // Should include prior SQL
            #expect(prompt.contains("SELECT * FROM users"))
            #expect(prompt.contains("SELECT * FROM users WHERE city = 'New York'"))
        }
    }

    @Test("Follow-up switching tables preserves cross-table context")
    func followUpSwitchesTableWithContext() async throws {
        let db = try makeTestDatabase()

        // Turn 1: query users, Turn 2: ask about their orders
        let mock = PromptCapturingMockModel(responses: [
            "SELECT name, age FROM users WHERE age > 30",
            "Found 3 users over 30.",
            "SELECT o.id, u.name, o.amount, o.status FROM orders o JOIN users u ON o.user_id = u.id WHERE u.age > 30",
            "Bob has a $150 completed order, Charlie has a $200 completed order."
        ])

        let engine = ChatEngine(database: db, model: mock)

        // Turn 1: users over 30
        let response1 = try await engine.send("show users over 30")
        #expect(response1.queryResult?.rowCount == 3)

        // Turn 2: their orders — references the previous result context
        let response2 = try await engine.send("show their orders")
        #expect(response2.sql?.contains("JOIN") == true)

        // Verify the follow-up prompt contains the users context
        let prompts = mock.capturedPrompts
        let orderPrompt = prompts.first { prompt in
            prompt.contains("show their orders") && prompt.contains("CONVERSATION HISTORY")
        }
        #expect(orderPrompt != nil)

        if let prompt = orderPrompt {
            #expect(prompt.contains("show users over 30"), "Should contain prior user message")
            #expect(prompt.contains("age > 30"), "Should contain prior SQL context for table reference")
        }
    }

    @Test("Conversation history includes SQL from prior turns for context")
    func historyIncludesSQLFromPriorTurns() async throws {
        let db = try makeTestDatabase()

        // Both queries are aggregates → no LLM summarization needed
        let mock = PromptCapturingMockModel(responses: [
            "SELECT COUNT(*) FROM users",
            "SELECT COUNT(*) FROM users WHERE age > 30",
        ])

        let engine = ChatEngine(database: db, model: mock)

        // Turn 1
        let r1 = try await engine.send("how many users are there?")
        #expect(r1.sql == "SELECT COUNT(*) FROM users")

        // Turn 2 — references "those" implicitly
        let r2 = try await engine.send("how many of those are over 30?")
        #expect(r2.sql == "SELECT COUNT(*) FROM users WHERE age > 30")

        // Verify engine history has all 4 messages (2 user + 2 assistant)
        let messages = engine.messages
        #expect(messages.count == 4)
        #expect(messages[0].role == .user)
        #expect(messages[0].content == "how many users are there?")
        #expect(messages[1].role == .assistant)
        #expect(messages[1].sql == "SELECT COUNT(*) FROM users")
        #expect(messages[2].role == .user)
        #expect(messages[2].content == "how many of those are over 30?")
        #expect(messages[3].role == .assistant)
        #expect(messages[3].sql == "SELECT COUNT(*) FROM users WHERE age > 30")

        // The second prompt should reference the first query SQL
        let prompts = mock.capturedPrompts
        #expect(prompts.count >= 2)
        let secondPrompt = prompts[1]
        #expect(secondPrompt.contains("CONVERSATION HISTORY"))
        #expect(secondPrompt.contains("SELECT COUNT(*) FROM users"))
        #expect(secondPrompt.contains("how many users are there?"))
    }

    @Test("Follow-up after aggregate uses prior table context")
    func followUpAfterAggregateUsesTableContext() async throws {
        let db = try makeTestDatabase()

        // Turn 1: aggregate (no LLM summary needed)
        // Turn 2: follow-up referencing "those"
        let mock = PromptCapturingMockModel(responses: [
            "SELECT AVG(age) FROM users",
            "SELECT name, age FROM users WHERE age > 35",
            "Charlie (42) and Eve (55) are older than average."
        ])

        let engine = ChatEngine(database: db, model: mock)

        // Turn 1: average age → aggregate, template summary
        let r1 = try await engine.send("what is the average age of users?")
        #expect(r1.sql == "SELECT AVG(age) FROM users")

        // Turn 2: "who is above that?" — needs the avg context
        let r2 = try await engine.send("who is above average?")
        #expect(r2.queryResult?.rowCount == 2)

        // Verify context passed
        let prompts = mock.capturedPrompts
        let followUp = prompts.first { prompt in
            prompt.contains("who is above average?") && prompt.contains("CONVERSATION HISTORY")
        }
        #expect(followUp != nil)
        if let prompt = followUp {
            #expect(prompt.contains("AVG(age)"), "Should include prior aggregate SQL for context")
            #expect(prompt.contains("users"), "Should include table reference from prior turn")
        }
    }

    @Test("Context window limits how much history is visible in follow-ups")
    func contextWindowLimitsHistoryInFollowUps() async throws {
        let db = try makeTestDatabase()

        // 3 turns, but context window of 2 messages
        let mock = PromptCapturingMockModel(responses: [
            "SELECT COUNT(*) FROM users",
            "SELECT COUNT(*) FROM orders",
            "SELECT COUNT(*) FROM users WHERE age > 30",
        ])

        let config = ChatEngineConfiguration(
            queryTimeout: nil,
            contextWindowSize: 2
        )

        let engine = ChatEngine(
            database: db,
            model: mock,
            configuration: config
        )

        _ = try await engine.send("how many users?")
        _ = try await engine.send("how many orders?")
        _ = try await engine.send("how many users over 30?")

        // The third prompt should only have the last 2 messages from turn 2
        let prompts = mock.capturedPrompts
        #expect(prompts.count >= 3)

        let thirdPrompt = prompts[2]
        #expect(thirdPrompt.contains("CONVERSATION HISTORY"))
        // Turn 2 context should be present
        #expect(thirdPrompt.contains("how many orders?"))
        #expect(thirdPrompt.contains("SELECT COUNT(*) FROM orders"))
        // Turn 1 context should be trimmed (window=2 means last 2 messages)
        #expect(!thirdPrompt.contains("how many users?\n"), "First turn should be trimmed from context window")
    }

    @Test("clearHistory resets context so follow-ups have no prior history")
    func clearHistoryResetsFollowUpContext() async throws {
        let db = try makeTestDatabase()

        let mock = PromptCapturingMockModel(responses: [
            "SELECT * FROM users",
            "Here are the 5 users.",
            "SELECT COUNT(*) FROM users",
        ])

        let engine = ChatEngine(database: db, model: mock)

        // Turn 1
        _ = try await engine.send("show all users")
        #expect(engine.messages.count == 2)

        // Clear history
        engine.clearHistory()
        #expect(engine.messages.isEmpty)

        // Turn 2 after clear — should NOT have conversation history
        _ = try await engine.send("count all users")

        let prompts = mock.capturedPrompts
        let lastPrompt = prompts.last!
        // After clearing, the prompt should NOT contain conversation history
        #expect(!lastPrompt.contains("CONVERSATION HISTORY"),
                "After clearHistory(), follow-up should not have prior context")
        #expect(!lastPrompt.contains("show all users"),
                "After clearHistory(), prior messages should be gone")
    }

    @Test("Multi-turn with result data in context enables informed follow-ups")
    func resultDataInContextEnablesInformedFollowUps() async throws {
        let db = try makeTestDatabase()

        // Turn 1: list users → multi-row result, LLM summarizes
        // Turn 2: "sort those by age" → references same table
        let mock = PromptCapturingMockModel(responses: [
            "SELECT name, age, city FROM users",
            "Found 5 users: Alice (25, NY), Bob (35, SF), Charlie (42, NY), Diana (28, Chicago), Eve (55, SF).",
            "SELECT name, age, city FROM users ORDER BY age DESC",
            "Users sorted by age: Eve (55), Charlie (42), Bob (35), Diana (28), Alice (25)."
        ])

        let engine = ChatEngine(database: db, model: mock)

        let r1 = try await engine.send("list all users with their age and city")
        #expect(r1.queryResult?.rowCount == 5)
        #expect(r1.queryResult?.columns.contains("age") == true)
        #expect(r1.queryResult?.columns.contains("city") == true)

        let r2 = try await engine.send("sort those by age descending")
        #expect(r2.sql == "SELECT name, age, city FROM users ORDER BY age DESC")

        // Verify the assistant message in history includes the SQL
        let messages = engine.messages
        #expect(messages.count == 4)
        // First assistant message should have the SQL recorded
        #expect(messages[1].sql == "SELECT name, age, city FROM users")
        // Second assistant should have the sorted SQL
        #expect(messages[3].sql == "SELECT name, age, city FROM users ORDER BY age DESC")
    }
}
