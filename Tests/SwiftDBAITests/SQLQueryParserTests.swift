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
}
