// DatabaseToolTests.swift
// SwiftDBAI

import Testing
import Foundation
import GRDB
@testable import SwiftDBAI

@Suite("DatabaseTool")
struct DatabaseToolTests {

    // MARK: - Helper

    /// Creates an in-memory database with sample data for testing.
    private func makeTestDatabase() throws -> DatabaseQueue {
        let db = try DatabaseQueue(configuration: {
            var config = Configuration()
            config.foreignKeysEnabled = true
            return config
        }())

        try db.write { db in
            try db.execute(sql: """
                CREATE TABLE users (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    name TEXT NOT NULL,
                    email TEXT UNIQUE
                );
                """)

            try db.execute(sql: """
                CREATE TABLE posts (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    user_id INTEGER NOT NULL REFERENCES users(id),
                    title TEXT NOT NULL,
                    body TEXT,
                    created_at TEXT DEFAULT CURRENT_TIMESTAMP
                );
                """)

            try db.execute(sql: """
                CREATE INDEX idx_posts_user ON posts(user_id);
                """)

            // Insert sample data
            try db.execute(sql: "INSERT INTO users (name, email) VALUES ('Alice', 'alice@example.com')")
            try db.execute(sql: "INSERT INTO users (name, email) VALUES ('Bob', 'bob@example.com')")
            try db.execute(sql: "INSERT INTO posts (user_id, title, body) VALUES (1, 'Hello World', 'First post')")
            try db.execute(sql: "INSERT INTO posts (user_id, title, body) VALUES (1, 'Second Post', 'More content')")
            try db.execute(sql: "INSERT INTO posts (user_id, title, body) VALUES (2, 'Bob Post', 'Bob writes')")
        }

        return db
    }

    // MARK: - Creation

    @Test("Creates tool from database connection")
    func testCreationFromDatabase() async throws {
        let db = try makeTestDatabase()
        let tool = try await DatabaseTool(database: db)

        #expect(tool.name == "execute_sql")
        #expect(!tool.description.isEmpty)
    }

    @Test("Creates tool from database path")
    func testCreationFromPath() async throws {
        let tmpDir = FileManager.default.temporaryDirectory
        let dbPath = tmpDir.appendingPathComponent("test_\(UUID().uuidString).sqlite").path
        defer { try? FileManager.default.removeItem(atPath: dbPath) }

        // Create a database at the path
        let dbQueue = try DatabaseQueue(path: dbPath)
        try await dbQueue.write { db in
            try db.execute(sql: "CREATE TABLE test (id INTEGER PRIMARY KEY)")
        }

        let tool = try await DatabaseTool(databasePath: dbPath)
        #expect(tool.name == "execute_sql")
    }

    // MARK: - Schema Context

    @Test("Schema context contains table info")
    func testSchemaContext() async throws {
        let db = try makeTestDatabase()
        let tool = try await DatabaseTool(database: db)

        let context = tool.schemaContext
        #expect(context.contains("users"))
        #expect(context.contains("posts"))
        #expect(context.contains("name"))
        #expect(context.contains("email"))
    }

    @Test("System prompt snippet contains schema")
    func testSystemPromptSnippet() async throws {
        let db = try makeTestDatabase()
        let tool = try await DatabaseTool(database: db)

        let snippet = tool.systemPromptSnippet
        #expect(snippet.contains("users"))
        #expect(snippet.contains("posts"))
        #expect(snippet.contains("execute_sql"))
        #expect(snippet.contains("SELECT"))
    }

    // MARK: - SQL Execution

    @Test("Executes valid SELECT query")
    func testExecuteSelect() async throws {
        let db = try makeTestDatabase()
        let tool = try await DatabaseTool(database: db)

        let result = try tool.execute(sql: "SELECT name, email FROM users ORDER BY name")

        #expect(result.rowCount == 2)
        #expect(result.columns == ["name", "email"])
        #expect(result.rows[0]["name"] == "Alice")
        #expect(result.rows[1]["name"] == "Bob")
    }

    @Test("Executes query with JOIN")
    func testExecuteJoin() async throws {
        let db = try makeTestDatabase()
        let tool = try await DatabaseTool(database: db)

        let result = try tool.execute(sql: """
            SELECT u.name, COUNT(p.id) as post_count
            FROM users u
            JOIN posts p ON p.user_id = u.id
            GROUP BY u.name
            ORDER BY u.name
            """)

        #expect(result.rowCount == 2)
        #expect(result.rows[0]["name"] == "Alice")
        #expect(result.rows[0]["post_count"] == "2")
    }

    @Test("Rejects INSERT with read-only allowlist")
    func testRejectInsert() async throws {
        let db = try makeTestDatabase()
        let tool = try await DatabaseTool(database: db, allowlist: .readOnly)

        #expect(throws: SQLParsingError.self) {
            try tool.execute(sql: "INSERT INTO users (name, email) VALUES ('Eve', 'eve@example.com')")
        }
    }

    @Test("Rejects DELETE with read-only allowlist")
    func testRejectDelete() async throws {
        let db = try makeTestDatabase()
        let tool = try await DatabaseTool(database: db, allowlist: .readOnly)

        #expect(throws: SQLParsingError.self) {
            try tool.execute(sql: "DELETE FROM users WHERE id = 1")
        }
    }

    @Test("Rejects DROP as dangerous operation")
    func testRejectDrop() async throws {
        let db = try makeTestDatabase()
        let tool = try await DatabaseTool(database: db, allowlist: .unrestricted)

        #expect(throws: SQLParsingError.self) {
            try tool.execute(sql: "DROP TABLE users")
        }
    }

    @Test("Executes raw query returning QueryResult")
    func testExecuteRaw() async throws {
        let db = try makeTestDatabase()
        let tool = try await DatabaseTool(database: db)

        let result = try tool.executeRaw(sql: "SELECT COUNT(*) as cnt FROM users")

        #expect(result.rowCount == 1)
        #expect(result.columns == ["cnt"])
        if case .integer(let count) = result.rows[0]["cnt"] {
            #expect(count == 2)
        } else {
            Issue.record("Expected integer value")
        }
    }

    // MARK: - ToolResult Formatting

    @Test("ToolResult JSON serialization")
    func testToolResultJSON() async throws {
        let db = try makeTestDatabase()
        let tool = try await DatabaseTool(database: db)

        let result = try tool.execute(sql: "SELECT name FROM users ORDER BY name LIMIT 1")

        let json = result.jsonString
        #expect(json.contains("\"columns\""))
        #expect(json.contains("\"rows\""))
        #expect(json.contains("\"row_count\""))
        #expect(json.contains("Alice"))

        // Verify it is valid JSON
        let data = json.data(using: .utf8)!
        let parsed = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        #expect(parsed["row_count"] as? Int == 1)
    }

    @Test("ToolResult markdown table formatting")
    func testToolResultMarkdown() async throws {
        let db = try makeTestDatabase()
        let tool = try await DatabaseTool(database: db)

        let result = try tool.execute(sql: "SELECT name, email FROM users ORDER BY name")

        let md = result.markdownTable
        #expect(md.contains("| name | email |"))
        #expect(md.contains("| --- | --- |"))
        #expect(md.contains("| Alice | alice@example.com |"))
        #expect(md.contains("| Bob | bob@example.com |"))
    }

    @Test("ToolResult markdown table with empty result")
    func testToolResultMarkdownEmpty() async throws {
        let db = try makeTestDatabase()
        let tool = try await DatabaseTool(database: db)

        let result = try tool.execute(sql: "SELECT name FROM users WHERE name = 'Nobody'")

        #expect(result.markdownTable == "_No results._")
    }

    @Test("ToolResult text summary")
    func testToolResultTextSummary() async throws {
        let db = try makeTestDatabase()
        let tool = try await DatabaseTool(database: db)

        let result = try tool.execute(sql: "SELECT name FROM users")

        let summary = result.textSummary
        #expect(summary.contains("2 rows"))
        #expect(summary.contains("name"))
    }

    @Test("ToolResult text summary with empty result")
    func testToolResultTextSummaryEmpty() async throws {
        let db = try makeTestDatabase()
        let tool = try await DatabaseTool(database: db)

        let result = try tool.execute(sql: "SELECT name FROM users WHERE 1 = 0")

        #expect(result.textSummary.contains("no results"))
    }

    // MARK: - Parameters Schema

    @Test("Parameters schema has correct structure")
    func testParametersSchema() async throws {
        let db = try makeTestDatabase()
        let tool = try await DatabaseTool(database: db)

        let schema = tool.parametersSchema
        #expect(schema["type"] as? String == "object")

        let properties = schema["properties"] as? [String: Any]
        #expect(properties != nil)

        let sqlProp = properties?["sql"] as? [String: Any]
        #expect(sqlProp?["type"] as? String == "string")

        let required = schema["required"] as? [String]
        #expect(required == ["sql"])
    }

    // MARK: - OpenAI Function Definition

    @Test("OpenAI function definition has correct format")
    func testOpenAIFunctionDefinition() async throws {
        let db = try makeTestDatabase()
        let tool = try await DatabaseTool(database: db)

        let def = tool.openAIFunctionDefinition
        #expect(def["type"] as? String == "function")

        let function = def["function"] as? [String: Any]
        #expect(function?["name"] as? String == "execute_sql")
        #expect(function?["description"] as? String != nil)
        #expect(function?["parameters"] as? [String: Any] != nil)

        // Verify it can be serialized to JSON
        let data = try JSONSerialization.data(withJSONObject: def)
        #expect(data.count > 0)
    }

    // MARK: - ToolResult Codable

    @Test("ToolResult is Codable")
    func testToolResultCodable() throws {
        let result = ToolResult(
            columns: ["name", "age"],
            rows: [["name": "Alice", "age": "30"]],
            rowCount: 1,
            executionTime: 0.005,
            sql: "SELECT name, age FROM users"
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(result)
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(ToolResult.self, from: data)

        #expect(decoded.columns == result.columns)
        #expect(decoded.rows == result.rows)
        #expect(decoded.rowCount == result.rowCount)
        #expect(decoded.sql == result.sql)
    }
}
