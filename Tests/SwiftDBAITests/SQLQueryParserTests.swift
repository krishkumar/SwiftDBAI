// SQLQueryParserTests.swift
// SwiftDBAITests

import Testing
@testable import SwiftDBAI

@Suite("SQLQueryParser")
struct SQLQueryParserTests {

    let readOnlyParser = SQLQueryParser(allowlist: .readOnly)
    let standardParser = SQLQueryParser(allowlist: .standard)
    let unrestrictedParser = SQLQueryParser(allowlist: .unrestricted)

    // MARK: - Extraction from code blocks

    @Test("Extracts SQL from markdown sql code block")
    func extractFromSQLCodeBlock() throws {
        let text = """
        Here's the query to find the top users:

        ```sql
        SELECT name, COUNT(*) as count FROM users GROUP BY name ORDER BY count DESC
        ```

        This will give you the results.
        """
        let result = try readOnlyParser.parse(text)
        #expect(result.sql == "SELECT name, COUNT(*) as count FROM users GROUP BY name ORDER BY count DESC")
        #expect(result.operation == .select)
        #expect(result.requiresConfirmation == false)
    }

    @Test("Extracts SQL from generic code block")
    func extractFromGenericCodeBlock() throws {
        let text = """
        Here you go:

        ```
        SELECT * FROM products WHERE price > 100
        ```
        """
        let result = try readOnlyParser.parse(text)
        #expect(result.sql == "SELECT * FROM products WHERE price > 100")
    }

    @Test("Extracts SQL from labeled text")
    func extractFromLabel() throws {
        let text = """
        I can help with that.
        SQL: SELECT id, name FROM categories WHERE active = 1
        That should work.
        """
        let result = try readOnlyParser.parse(text)
        #expect(result.sql == "SELECT id, name FROM categories WHERE active = 1")
    }

    @Test("Extracts direct SQL from plain text")
    func extractDirectSQL() throws {
        let text = "SELECT COUNT(*) FROM orders WHERE status = 'shipped'"
        let result = try readOnlyParser.parse(text)
        #expect(result.sql == "SELECT COUNT(*) FROM orders WHERE status = 'shipped'")
    }

    @Test("Handles SQL with trailing semicolons")
    func trailingSemicolon() throws {
        let text = "```sql\nSELECT * FROM users;\n```"
        let result = try readOnlyParser.parse(text)
        #expect(result.sql == "SELECT * FROM users")
    }

    @Test("Handles multiline SQL in code block")
    func multilineSQL() throws {
        let text = """
        ```sql
        SELECT u.name, COUNT(o.id) as order_count
        FROM users u
        JOIN orders o ON u.id = o.user_id
        GROUP BY u.name
        ORDER BY order_count DESC
        LIMIT 10
        ```
        """
        let result = try readOnlyParser.parse(text)
        #expect(result.sql.contains("SELECT u.name"))
        #expect(result.sql.contains("LIMIT 10"))
    }

    @Test("Handles WITH (CTE) queries as SELECT")
    func cteQuery() throws {
        let text = """
        ```sql
        WITH top_users AS (
          SELECT user_id, COUNT(*) as cnt FROM orders GROUP BY user_id
        )
        SELECT * FROM top_users WHERE cnt > 5
        ```
        """
        let result = try readOnlyParser.parse(text)
        #expect(result.operation == .select)
    }

    // MARK: - No SQL found

    @Test("Throws noSQLFound for text without SQL")
    func noSQLFound() throws {
        let text = "I'm sorry, I can't help with that request."
        #expect(throws: SQLParsingError.noSQLFound) {
            try readOnlyParser.parse(text)
        }
    }

    @Test("Throws noSQLFound for empty input")
    func emptyInput() throws {
        #expect(throws: SQLParsingError.noSQLFound) {
            try readOnlyParser.parse("")
        }
    }

    // MARK: - Operation detection

    @Test("Detects INSERT operation")
    func detectInsert() throws {
        let text = "```sql\nINSERT INTO users (name) VALUES ('Alice')\n```"
        let result = try standardParser.parse(text)
        #expect(result.operation == .insert)
    }

    @Test("Detects UPDATE operation")
    func detectUpdate() throws {
        let text = "```sql\nUPDATE users SET name = 'Bob' WHERE id = 1\n```"
        let result = try standardParser.parse(text)
        #expect(result.operation == .update)
    }

    @Test("Detects DELETE operation and requires confirmation")
    func detectDeleteRequiresConfirmation() throws {
        let text = "```sql\nDELETE FROM users WHERE id = 99\n```"
        let result = try unrestrictedParser.parse(text)
        #expect(result.operation == .delete)
        #expect(result.requiresConfirmation == true)
    }

    // MARK: - Allowlist enforcement

    @Test("Rejects INSERT on read-only allowlist")
    func rejectInsertOnReadOnly() throws {
        let text = "```sql\nINSERT INTO users (name) VALUES ('Mallory')\n```"
        #expect(throws: SQLParsingError.operationNotAllowed(.insert)) {
            try readOnlyParser.parse(text)
        }
    }

    @Test("Rejects UPDATE on read-only allowlist")
    func rejectUpdateOnReadOnly() {
        let text = "```sql\nUPDATE users SET name = 'Eve' WHERE id = 1\n```"
        #expect(throws: SQLParsingError.operationNotAllowed(.update)) {
            try readOnlyParser.parse(text)
        }
    }

    @Test("Rejects DELETE on standard allowlist")
    func rejectDeleteOnStandard() {
        let text = "```sql\nDELETE FROM users WHERE id = 1\n```"
        #expect(throws: SQLParsingError.operationNotAllowed(.delete)) {
            try standardParser.parse(text)
        }
    }

    // MARK: - Dangerous operations

    @Test("Rejects DROP TABLE")
    func rejectDrop() {
        let text = "```sql\nDROP TABLE users\n```"
        #expect(throws: SQLParsingError.dangerousOperation("DROP")) {
            try unrestrictedParser.parse(text)
        }
    }

    @Test("Rejects ALTER TABLE")
    func rejectAlter() {
        let text = "```sql\nALTER TABLE users ADD COLUMN age INTEGER\n```"
        #expect(throws: SQLParsingError.dangerousOperation("ALTER")) {
            try unrestrictedParser.parse(text)
        }
    }

    @Test("Rejects PRAGMA")
    func rejectPragma() {
        let text = "```sql\nPRAGMA table_info(users)\n```"
        #expect(throws: SQLParsingError.dangerousOperation("PRAGMA")) {
            try unrestrictedParser.parse(text)
        }
    }

    @Test("Does not match dangerous keywords inside identifiers")
    func noFalsePositiveOnSubstring() throws {
        // "DROPDOWN" contains "DROP" as substring but is not the keyword
        let text = "SELECT dropdown_value FROM settings"
        let result = try readOnlyParser.parse(text)
        #expect(result.sql.contains("dropdown_value"))
    }

    // MARK: - Multiple statements

    @Test("Rejects multiple statements separated by semicolons")
    func rejectMultipleStatements() {
        let text = "```sql\nSELECT * FROM users; SELECT * FROM orders\n```"
        #expect(throws: SQLParsingError.multipleStatements) {
            try readOnlyParser.parse(text)
        }
    }

    @Test("Allows semicolons inside string literals")
    func allowSemicolonInString() throws {
        let text = "SELECT * FROM users WHERE bio = 'hello; world'"
        let result = try readOnlyParser.parse(text)
        #expect(result.sql.contains("hello; world"))
    }

    // MARK: - ParsedSQL equality

    @Test("ParsedSQL equality works")
    func parsedSQLEquality() {
        let a = ParsedSQL(sql: "SELECT 1", operation: .select)
        let b = ParsedSQL(sql: "SELECT 1", operation: .select)
        #expect(a == b)
    }

    // MARK: - Error descriptions

    @Test("Error descriptions are meaningful")
    func errorDescriptions() {
        #expect(SQLParsingError.noSQLFound.description.contains("No SQL"))
        #expect(SQLParsingError.operationNotAllowed(.insert).description.contains("INSERT"))
        #expect(SQLParsingError.dangerousOperation("DROP").description.contains("DROP"))
        #expect(SQLParsingError.multipleStatements.description.contains("single"))
    }

    // MARK: - MutationPolicy integration

    @Test("MutationPolicy allows INSERT on permitted table")
    func mutationPolicyAllowsInsertOnPermittedTable() throws {
        let policy = MutationPolicy(
            allowedOperations: [.insert, .update],
            allowedTables: ["orders", "order_items"]
        )
        let parser = SQLQueryParser(mutationPolicy: policy)
        let text = "```sql\nINSERT INTO orders (product, qty) VALUES ('Widget', 3)\n```"
        let result = try parser.parse(text)
        #expect(result.operation == .insert)
        #expect(result.requiresConfirmation == false)
    }

    @Test("MutationPolicy rejects INSERT on non-permitted table")
    func mutationPolicyRejectsInsertOnForbiddenTable() {
        let policy = MutationPolicy(
            allowedOperations: [.insert, .update],
            allowedTables: ["orders"]
        )
        let parser = SQLQueryParser(mutationPolicy: policy)
        let text = "```sql\nINSERT INTO users (name) VALUES ('Alice')\n```"
        #expect(throws: SQLParsingError.tableNotAllowed(table: "users", operation: .insert)) {
            try parser.parse(text)
        }
    }

    @Test("MutationPolicy rejects UPDATE on non-permitted table")
    func mutationPolicyRejectsUpdateOnForbiddenTable() {
        let policy = MutationPolicy(
            allowedOperations: [.insert, .update],
            allowedTables: ["orders"]
        )
        let parser = SQLQueryParser(mutationPolicy: policy)
        let text = "```sql\nUPDATE users SET name = 'Bob' WHERE id = 1\n```"
        #expect(throws: SQLParsingError.tableNotAllowed(table: "users", operation: .update)) {
            try parser.parse(text)
        }
    }

    @Test("MutationPolicy rejects DELETE on non-permitted table")
    func mutationPolicyRejectsDeleteOnForbiddenTable() {
        let policy = MutationPolicy(
            allowedOperations: [.insert, .update, .delete],
            allowedTables: ["temp_data"]
        )
        let parser = SQLQueryParser(mutationPolicy: policy)
        let text = "```sql\nDELETE FROM users WHERE id = 99\n```"
        #expect(throws: SQLParsingError.tableNotAllowed(table: "users", operation: .delete)) {
            try parser.parse(text)
        }
    }

    @Test("MutationPolicy allows mutation on any table when allowedTables is nil")
    func mutationPolicyAllowsAllTablesWhenNil() throws {
        let policy = MutationPolicy(allowedOperations: [.insert, .update])
        let parser = SQLQueryParser(mutationPolicy: policy)
        let text = "```sql\nINSERT INTO any_table (col) VALUES ('val')\n```"
        let result = try parser.parse(text)
        #expect(result.operation == .insert)
    }

    @Test("MutationPolicy SELECT is never restricted by table allowlist")
    func mutationPolicySelectIgnoresTableRestrictions() throws {
        let policy = MutationPolicy(
            allowedOperations: [.insert],
            allowedTables: ["orders"]
        )
        let parser = SQLQueryParser(mutationPolicy: policy)
        // SELECT from a table NOT in allowedTables — should still work
        let text = "```sql\nSELECT * FROM users\n```"
        let result = try parser.parse(text)
        #expect(result.operation == .select)
        #expect(result.requiresConfirmation == false)
    }

    @Test("MutationPolicy DELETE requires confirmation by default")
    func mutationPolicyDeleteRequiresConfirmation() throws {
        let policy = MutationPolicy(allowedOperations: [.delete])
        let parser = SQLQueryParser(mutationPolicy: policy)
        let text = "```sql\nDELETE FROM users WHERE id = 1\n```"
        let result = try parser.parse(text)
        #expect(result.operation == .delete)
        #expect(result.requiresConfirmation == true)
    }

    @Test("MutationPolicy DELETE skips confirmation when configured")
    func mutationPolicyDeleteNoConfirmation() throws {
        let policy = MutationPolicy(
            allowedOperations: [.delete],
            requiresDestructiveConfirmation: false
        )
        let parser = SQLQueryParser(mutationPolicy: policy)
        let text = "```sql\nDELETE FROM users WHERE id = 1\n```"
        let result = try parser.parse(text)
        #expect(result.operation == .delete)
        #expect(result.requiresConfirmation == false)
    }

    @Test("MutationPolicy readOnly preset rejects all mutations")
    func mutationPolicyReadOnlyRejectsAll() {
        let parser = SQLQueryParser(mutationPolicy: .readOnly)
        #expect(throws: SQLParsingError.operationNotAllowed(.insert)) {
            try parser.parse("INSERT INTO t (a) VALUES (1)")
        }
        #expect(throws: SQLParsingError.operationNotAllowed(.update)) {
            try parser.parse("UPDATE t SET a = 1")
        }
        #expect(throws: SQLParsingError.operationNotAllowed(.delete)) {
            try parser.parse("DELETE FROM t WHERE id = 1")
        }
    }

    @Test("MutationPolicy table matching is case-insensitive")
    func mutationPolicyTableCaseInsensitive() throws {
        let policy = MutationPolicy(
            allowedOperations: [.insert],
            allowedTables: ["Orders"]
        )
        let parser = SQLQueryParser(mutationPolicy: policy)
        let text = "INSERT INTO orders (product) VALUES ('Widget')"
        let result = try parser.parse(text)
        #expect(result.operation == .insert)
    }

    @Test("MutationPolicy handles quoted table names")
    func mutationPolicyQuotedTableNames() throws {
        let policy = MutationPolicy(
            allowedOperations: [.insert, .update],
            allowedTables: ["order_items"]
        )
        let parser = SQLQueryParser(mutationPolicy: policy)

        // Backtick-quoted
        let backtick = "INSERT INTO `order_items` (qty) VALUES (5)"
        let r1 = try parser.parse(backtick)
        #expect(r1.operation == .insert)

        // Double-quote-quoted
        let doubleQuote = "UPDATE \"order_items\" SET qty = 10 WHERE id = 1"
        let r2 = try parser.parse(doubleQuote)
        #expect(r2.operation == .update)
    }

    @Test("Error description for tableNotAllowed is meaningful")
    func tableNotAllowedDescription() {
        let error = SQLParsingError.tableNotAllowed(table: "secret", operation: .delete)
        #expect(error.description.contains("secret"))
        #expect(error.description.contains("DELETE"))
    }

    @Test("Error description for confirmationRequired is meaningful")
    func confirmationRequiredDescription() {
        let error = SQLParsingError.confirmationRequired(sql: "DELETE FROM x", operation: .delete)
        #expect(error.description.contains("DELETE"))
        #expect(error.description.contains("confirmation"))
    }

    // MARK: - Robust extraction edge cases

    @Test("Extracts plain SQL without any wrapping")
    func plainSQL() throws {
        let text = "SELECT * FROM users"
        let result = try readOnlyParser.parse(text)
        #expect(result.sql == "SELECT * FROM users")
    }

    @Test("Extracts SQL from markdown sql code block")
    func markdownSQLBlock() throws {
        let text = "```sql\nSELECT * FROM users\n```"
        let result = try readOnlyParser.parse(text)
        #expect(result.sql == "SELECT * FROM users")
    }

    @Test("Extracts SQL from generic code block")
    func genericCodeBlock() throws {
        let text = "```\nSELECT * FROM users\n```"
        let result = try readOnlyParser.parse(text)
        #expect(result.sql == "SELECT * FROM users")
    }

    @Test("Strips trailing semicolons")
    func trailingSemicolonEdge() throws {
        let text = "SELECT * FROM users;"
        let result = try readOnlyParser.parse(text)
        #expect(result.sql == "SELECT * FROM users")
    }

    @Test("Extracts SQL with preamble text")
    func preambleText() throws {
        let text = "Here's the query:\nSELECT * FROM users"
        let result = try readOnlyParser.parse(text)
        #expect(result.sql == "SELECT * FROM users")
    }

    @Test("Handles trailing backticks only (no opening fence)")
    func trailingBackticksOnly() throws {
        let text = "SELECT * FROM users\n```"
        let result = try readOnlyParser.parse(text)
        #expect(result.sql == "SELECT * FROM users")
    }

    @Test("Extracts SQL from single-line code block")
    func singleLineCodeBlock() throws {
        let text = "```sql SELECT * FROM users ```"
        let result = try readOnlyParser.parse(text)
        #expect(result.sql == "SELECT * FROM users")
    }

    @Test("Handles no newline before closing fence")
    func noNewlineBeforeClosingFence() throws {
        let text = "```sql\nSELECT * FROM users```"
        let result = try readOnlyParser.parse(text)
        #expect(result.sql == "SELECT * FROM users")
    }

    @Test("Extracts SQL inline with text prefix")
    func inlineWithText() throws {
        let text = "The SQL query is: SELECT * FROM users"
        let result = try readOnlyParser.parse(text)
        #expect(result.sql == "SELECT * FROM users")
    }

    @Test("Handles extra whitespace around SQL")
    func extraWhitespace() throws {
        let text = "\n\nSELECT * FROM users\n\n"
        let result = try readOnlyParser.parse(text)
        #expect(result.sql == "SELECT * FROM users")
    }

    @Test("Extracts SQL from chatty LLM response with preamble and postamble")
    func chattyLLMResponse() throws {
        let text = "Sure! Here's the SQL:\n\n```sql\nSELECT * FROM users\n```\n\nThis will return all users."
        let result = try readOnlyParser.parse(text)
        #expect(result.sql == "SELECT * FROM users")
    }

    @Test("Preserves SQL comments")
    func sqlWithComments() throws {
        let text = "SELECT * FROM users -- get all users"
        let result = try readOnlyParser.parse(text)
        #expect(result.sql.contains("-- get all users"))
    }

    @Test("Preserves backtick-quoted identifiers in SQL")
    func backtickQuotedIdentifiers() throws {
        let text = "SELECT `column name` FROM users"
        let result = try readOnlyParser.parse(text)
        #expect(result.sql.contains("`column name`"))
    }

    @Test("Strips think tags from Qwen-style models")
    func thinkTags() throws {
        let text = "<think>I need to query the users table</think>\nSELECT * FROM users"
        let result = try readOnlyParser.parse(text)
        #expect(result.sql == "SELECT * FROM users")
        #expect(!result.sql.contains("think"))
    }

    @Test("Handles 4 or 5 backtick fences")
    func extraBacktickFences() throws {
        let text4 = "````sql\nSELECT * FROM users\n````"
        let result4 = try readOnlyParser.parse(text4)
        #expect(result4.sql == "SELECT * FROM users")

        let text5 = "`````\nSELECT * FROM users\n`````"
        let result5 = try readOnlyParser.parse(text5)
        #expect(result5.sql == "SELECT * FROM users")
    }

    @Test("Handles mixed case SQL keywords")
    func mixedCaseSQL() throws {
        let text = "select * from USERS"
        let result = try readOnlyParser.parse(text)
        #expect(result.sql == "select * from USERS")
    }

    @Test("Handles WITH clause (CTE) queries")
    func withClause() throws {
        let text = "WITH cte AS (SELECT id FROM orders) SELECT * FROM cte"
        let result = try readOnlyParser.parse(text)
        #expect(result.sql.hasPrefix("WITH"))
        #expect(result.operation == .select)
    }

    @Test("Handles WITH clause in code block")
    func withClauseInCodeBlock() throws {
        let text = "```sql\nWITH top AS (\n  SELECT user_id, COUNT(*) as cnt FROM orders GROUP BY user_id\n)\nSELECT * FROM top WHERE cnt > 5\n```"
        let result = try readOnlyParser.parse(text)
        #expect(result.sql.hasPrefix("WITH"))
        #expect(result.operation == .select)
    }

    @Test("Multi-line SQL with JOINs and subqueries in code block")
    func multiLineJoinsAndSubqueries() throws {
        let text = """
        ```sql
        SELECT u.name, o.total
        FROM users u
        INNER JOIN orders o ON u.id = o.user_id
        WHERE o.total > (SELECT AVG(total) FROM orders)
        ORDER BY o.total DESC
        ```
        """
        let result = try readOnlyParser.parse(text)
        #expect(result.sql.contains("INNER JOIN"))
        #expect(result.sql.contains("SELECT AVG(total)"))
        #expect(result.sql.contains("ORDER BY"))
    }

    @Test("Handles response with both explanation text and SQL")
    func explanationAndSQL() throws {
        let text = """
        To find all active users, we need to query the users table
        and filter by the active column. Here's the query:

        SELECT * FROM users WHERE active = 1

        This should give you the results you're looking for.
        """
        let result = try readOnlyParser.parse(text)
        #expect(result.sql == "SELECT * FROM users WHERE active = 1")
    }

    @Test("Throws noSQLFound for empty response")
    func emptyResponse() throws {
        #expect(throws: SQLParsingError.noSQLFound) {
            try readOnlyParser.parse("")
        }
        #expect(throws: SQLParsingError.noSQLFound) {
            try readOnlyParser.parse("   \n\n  ")
        }
    }

    @Test("Throws noSQLFound for response with no SQL at all")
    func noSQLAtAll() throws {
        #expect(throws: SQLParsingError.noSQLFound) {
            try readOnlyParser.parse("I cannot help with that question. Please try asking about your data.")
        }
    }

    @Test("Handles response with multiple SQL statements in code block (rejects them)")
    func multipleStatementsInCodeBlock() throws {
        // When multiple statements are in a code block, the parser sees both and rejects
        let text = "```sql\nSELECT * FROM users; SELECT * FROM orders\n```"
        #expect(throws: SQLParsingError.multipleStatements) {
            try readOnlyParser.parse(text)
        }
    }

    @Test("Extracts first SQL statement from plain text with multiple statements")
    func multipleStatementsPlainText() throws {
        // In plain text, the direct extraction stops at the semicolon and extracts the first statement
        let text = "SELECT * FROM users; SELECT * FROM orders"
        let result = try readOnlyParser.parse(text)
        #expect(result.sql == "SELECT * FROM users")
    }

    @Test("Preserves backtick identifiers inside code blocks")
    func backtickIdentifiersInCodeBlock() throws {
        let text = "```sql\nSELECT `first name`, `last name` FROM `user data`\n```"
        let result = try readOnlyParser.parse(text)
        #expect(result.sql.contains("`first name`"))
        #expect(result.sql.contains("`last name`"))
        #expect(result.sql.contains("`user data`"))
    }

    @Test("Strips think tags with multiline reasoning content")
    func multilineThinkTags() throws {
        let text = """
        <think>
        The user wants to find all users.
        I should use SELECT * FROM users.
        Let me think about which columns to include...
        </think>
        SELECT * FROM users
        """
        let result = try readOnlyParser.parse(text)
        #expect(result.sql == "SELECT * FROM users")
    }

    @Test("Handles mixed backtick styles in response")
    func mixedBacktickStyles() throws {
        // Code fences + backtick-quoted identifiers inside
        let text = "```sql\nSELECT `user name` FROM users WHERE `is active` = 1\n```"
        let result = try readOnlyParser.parse(text)
        #expect(result.sql.contains("`user name`"))
        #expect(result.sql.contains("`is active`"))
    }
}
