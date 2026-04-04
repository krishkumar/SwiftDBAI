// PromptBuilderTests.swift
// SwiftDBAI

import Testing
@testable import SwiftDBAI

@Suite("PromptBuilder")
struct PromptBuilderTests {

    // MARK: - Helpers

    /// Creates a sample schema for testing.
    private func makeSampleSchema() -> DatabaseSchema {
        let usersTable = TableSchema(
            name: "users",
            columns: [
                ColumnSchema(cid: 0, name: "id", type: "INTEGER", isNotNull: true, defaultValue: nil, isPrimaryKey: true),
                ColumnSchema(cid: 1, name: "name", type: "TEXT", isNotNull: true, defaultValue: nil, isPrimaryKey: false),
                ColumnSchema(cid: 2, name: "email", type: "TEXT", isNotNull: false, defaultValue: nil, isPrimaryKey: false),
                ColumnSchema(cid: 3, name: "created_at", type: "TEXT", isNotNull: false, defaultValue: "CURRENT_TIMESTAMP", isPrimaryKey: false),
            ],
            primaryKey: ["id"],
            foreignKeys: [],
            indexes: [
                IndexSchema(name: "idx_users_email", isUnique: true, columns: ["email"])
            ]
        )

        let ordersTable = TableSchema(
            name: "orders",
            columns: [
                ColumnSchema(cid: 0, name: "id", type: "INTEGER", isNotNull: true, defaultValue: nil, isPrimaryKey: true),
                ColumnSchema(cid: 1, name: "user_id", type: "INTEGER", isNotNull: true, defaultValue: nil, isPrimaryKey: false),
                ColumnSchema(cid: 2, name: "total", type: "REAL", isNotNull: true, defaultValue: nil, isPrimaryKey: false),
                ColumnSchema(cid: 3, name: "status", type: "TEXT", isNotNull: true, defaultValue: "'pending'", isPrimaryKey: false),
            ],
            primaryKey: ["id"],
            foreignKeys: [
                ForeignKeySchema(fromColumn: "user_id", toTable: "users", toColumn: "id", onUpdate: "NO ACTION", onDelete: "CASCADE")
            ],
            indexes: []
        )

        return DatabaseSchema(
            tables: ["users": usersTable, "orders": ordersTable],
            tableNames: ["users", "orders"]
        )
    }

    private func makeEmptySchema() -> DatabaseSchema {
        DatabaseSchema(tables: [:], tableNames: [])
    }

    // MARK: - System Instructions Tests

    @Test("System instructions contain role section")
    func systemInstructionsContainRole() {
        let builder = PromptBuilder(schema: makeSampleSchema())
        let instructions = builder.buildSystemInstructions()

        #expect(instructions.contains("ROLE"))
        #expect(instructions.contains("SQL assistant"))
        #expect(instructions.contains("SQLite database"))
    }

    @Test("System instructions contain schema")
    func systemInstructionsContainSchema() {
        let builder = PromptBuilder(schema: makeSampleSchema())
        let instructions = builder.buildSystemInstructions()

        #expect(instructions.contains("DATABASE SCHEMA"))
        #expect(instructions.contains("TABLE users"))
        #expect(instructions.contains("TABLE orders"))
        #expect(instructions.contains("name TEXT"))
        #expect(instructions.contains("email TEXT"))
    }

    @Test("System instructions contain foreign keys from schema")
    func systemInstructionsContainForeignKeys() {
        let builder = PromptBuilder(schema: makeSampleSchema())
        let instructions = builder.buildSystemInstructions()

        #expect(instructions.contains("FOREIGN KEY"))
        #expect(instructions.contains("REFERENCES users(id)"))
    }

    @Test("System instructions contain SQL generation rules")
    func systemInstructionsContainRules() {
        let builder = PromptBuilder(schema: makeSampleSchema())
        let instructions = builder.buildSystemInstructions()

        #expect(instructions.contains("SQL GENERATION RULES"))
        #expect(instructions.contains("Use ONLY the tables and columns"))
        #expect(instructions.contains("Never generate DDL"))
    }

    @Test("System instructions contain output format section")
    func systemInstructionsContainOutputFormat() {
        let builder = PromptBuilder(schema: makeSampleSchema())
        let instructions = builder.buildSystemInstructions()

        #expect(instructions.contains("OUTPUT FORMAT"))
    }

    @Test("Default allowlist is read-only")
    func defaultAllowlistIsReadOnly() {
        let builder = PromptBuilder(schema: makeSampleSchema())
        let instructions = builder.buildSystemInstructions()

        #expect(instructions.contains("ONLY generate SELECT queries"))
        #expect(instructions.contains("No data modifications"))
    }

    @Test("Standard allowlist shows correct operations")
    func standardAllowlistInstructions() {
        let builder = PromptBuilder(schema: makeSampleSchema(), allowlist: .standard)
        let instructions = builder.buildSystemInstructions()

        #expect(instructions.contains("INSERT"))
        #expect(instructions.contains("SELECT"))
        #expect(instructions.contains("UPDATE"))
    }

    @Test("Unrestricted allowlist warns about DELETE")
    func unrestrictedAllowlistWarnsAboutDelete() {
        let builder = PromptBuilder(schema: makeSampleSchema(), allowlist: .unrestricted)
        let instructions = builder.buildSystemInstructions()

        #expect(instructions.contains("DELETE"))
        #expect(instructions.contains("destructive"))
        #expect(instructions.contains("confirmation"))
    }

    @Test("Additional context is appended")
    func additionalContextAppended() {
        let builder = PromptBuilder(
            schema: makeSampleSchema(),
            additionalContext: "All dates are stored in ISO 8601 format."
        )
        let instructions = builder.buildSystemInstructions()

        #expect(instructions.contains("ADDITIONAL CONTEXT"))
        #expect(instructions.contains("ISO 8601"))
    }

    @Test("No additional context section when nil")
    func noAdditionalContextWhenNil() {
        let builder = PromptBuilder(schema: makeSampleSchema())
        let instructions = builder.buildSystemInstructions()

        #expect(!instructions.contains("ADDITIONAL CONTEXT"))
    }

    @Test("No additional context section when empty string")
    func noAdditionalContextWhenEmpty() {
        let builder = PromptBuilder(schema: makeSampleSchema(), additionalContext: "")
        let instructions = builder.buildSystemInstructions()

        #expect(!instructions.contains("ADDITIONAL CONTEXT"))
    }

    @Test("Empty schema produces valid instructions")
    func emptySchemaProducesValidInstructions() {
        let builder = PromptBuilder(schema: makeEmptySchema())
        let instructions = builder.buildSystemInstructions()

        #expect(instructions.contains("ROLE"))
        #expect(instructions.contains("SQL GENERATION RULES"))
        // Schema section should still be present, just empty
        #expect(instructions.contains("DATABASE SCHEMA"))
    }

    // MARK: - User Prompt Tests

    @Test("User prompt passes through question directly")
    func userPromptPassesThrough() {
        let builder = PromptBuilder(schema: makeSampleSchema())
        let prompt = builder.buildUserPrompt("How many users signed up this week?")

        #expect(prompt == "How many users signed up this week?")
    }

    // MARK: - Follow-up Prompt Tests

    @Test("Follow-up prompt includes previous context")
    func followUpPromptIncludesPreviousContext() {
        let builder = PromptBuilder(schema: makeSampleSchema())
        let prompt = builder.buildFollowUpPrompt(
            "Now sort them by name",
            previousSQL: "SELECT * FROM users WHERE created_at > date('now', '-7 days')",
            previousResultSummary: "Found 42 users who signed up this week"
        )

        #expect(prompt.contains("Previous query:"))
        #expect(prompt.contains("SELECT * FROM users"))
        #expect(prompt.contains("Previous result:"))
        #expect(prompt.contains("42 users"))
        #expect(prompt.contains("Follow-up question:"))
        #expect(prompt.contains("sort them by name"))
    }

    // MARK: - Schema Description Quality

    @Test("Schema includes column types and constraints")
    func schemaIncludesColumnDetails() {
        let builder = PromptBuilder(schema: makeSampleSchema())
        let instructions = builder.buildSystemInstructions()

        // Should include type info
        #expect(instructions.contains("INTEGER"))
        #expect(instructions.contains("TEXT"))
        #expect(instructions.contains("REAL"))

        // Should include constraints
        #expect(instructions.contains("NOT NULL"))
        #expect(instructions.contains("PRIMARY KEY"))
    }

    @Test("Schema includes index information")
    func schemaIncludesIndexes() {
        let builder = PromptBuilder(schema: makeSampleSchema())
        let instructions = builder.buildSystemInstructions()

        #expect(instructions.contains("INDEX"))
        #expect(instructions.contains("idx_users_email"))
    }

    // MARK: - Sendable Conformance

    @Test("PromptBuilder is Sendable")
    func promptBuilderIsSendable() async {
        let builder = PromptBuilder(schema: makeSampleSchema())

        // Verify it can be sent across concurrency boundaries
        let instructions = await Task.detached {
            builder.buildSystemInstructions()
        }.value

        #expect(instructions.contains("ROLE"))
    }

    // MARK: - Custom Allowlist

    @Test("Custom allowlist with select and delete only")
    func customAllowlist() {
        let allowlist = OperationAllowlist([.select, .delete])
        let builder = PromptBuilder(schema: makeSampleSchema(), allowlist: allowlist)
        let instructions = builder.buildSystemInstructions()

        #expect(instructions.contains("DELETE"))
        #expect(instructions.contains("SELECT"))
        #expect(instructions.contains("destructive"))
    }
}
