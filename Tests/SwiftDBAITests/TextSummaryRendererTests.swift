// TextSummaryRendererTests.swift
// SwiftDBAI

import AnyLanguageModel
import Testing
import Foundation
@testable import SwiftDBAI

@Suite("TextSummaryRenderer")
struct TextSummaryRendererTests {

    // MARK: - QueryResult.Value Tests

    @Test("Value description renders correctly")
    func valueDescriptions() {
        #expect(QueryResult.Value.text("hello").description == "hello")
        #expect(QueryResult.Value.integer(42).description == "42")
        #expect(QueryResult.Value.real(3.14).description == "3.14")
        #expect(QueryResult.Value.null.description == "NULL")
        #expect(QueryResult.Value.blob(Data([0x01, 0x02])).description == "<2 bytes>")
    }

    @Test("Value doubleValue extracts numeric values")
    func valueDoubleValues() {
        #expect(QueryResult.Value.integer(42).doubleValue == 42.0)
        #expect(QueryResult.Value.real(3.14).doubleValue == 3.14)
        #expect(QueryResult.Value.text("100").doubleValue == 100.0)
        #expect(QueryResult.Value.text("not a number").doubleValue == nil)
        #expect(QueryResult.Value.null.doubleValue == nil)
        #expect(QueryResult.Value.blob(Data()).doubleValue == nil)
    }

    @Test("Value isNull works correctly")
    func valueIsNull() {
        #expect(QueryResult.Value.null.isNull == true)
        #expect(QueryResult.Value.text("").isNull == false)
        #expect(QueryResult.Value.integer(0).isNull == false)
    }

    // MARK: - QueryResult Tests

    @Test("Empty result has correct properties")
    func emptyResult() {
        let result = QueryResult(
            columns: ["id", "name"],
            rows: [],
            sql: "SELECT id, name FROM users",
            executionTime: 0.01
        )
        #expect(result.rowCount == 0)
        #expect(result.isAggregate == false)
        #expect(result.tabularDescription == "(empty result set)")
    }

    @Test("Single aggregate result is detected")
    func aggregateDetection() {
        let result = QueryResult(
            columns: ["COUNT(*)"],
            rows: [["COUNT(*)": .integer(42)]],
            sql: "SELECT COUNT(*) FROM users",
            executionTime: 0.01
        )
        #expect(result.isAggregate == true)
    }

    @Test("Multi-row result is not aggregate")
    func nonAggregateDetection() {
        let result = QueryResult(
            columns: ["name"],
            rows: [
                ["name": .text("Alice")],
                ["name": .text("Bob")],
            ],
            sql: "SELECT name FROM users",
            executionTime: 0.01
        )
        #expect(result.isAggregate == false)
    }

    @Test("Tabular description formats correctly")
    func tabularDescription() {
        let result = QueryResult(
            columns: ["id", "name"],
            rows: [
                ["id": .integer(1), "name": .text("Alice")],
                ["id": .integer(2), "name": .text("Bob")],
            ],
            sql: "SELECT id, name FROM users",
            executionTime: 0.01
        )
        let desc = result.tabularDescription
        #expect(desc.contains("id | name"))
        #expect(desc.contains("1 | Alice"))
        #expect(desc.contains("2 | Bob"))
    }

    @Test("values(forColumn:) extracts column values")
    func valuesForColumn() {
        let result = QueryResult(
            columns: ["name"],
            rows: [
                ["name": .text("Alice")],
                ["name": .text("Bob")],
            ],
            sql: "SELECT name FROM users",
            executionTime: 0.01
        )
        let values = result.values(forColumn: "name")
        #expect(values.count == 2)
        #expect(values[0] == .text("Alice"))
    }

    // MARK: - Local Summary Tests (no LLM required)

    @Test("Local summary for empty result")
    func localSummaryEmpty() {
        let result = makeResult(columns: ["id"], rows: [])
        let renderer = makeMockRenderer()
        let summary = renderer.localSummary(result: result, userQuestion: "Any users?")
        #expect(summary == "No results found for your query.")
    }

    @Test("Local summary for single aggregate")
    func localSummarySingleAggregate() {
        let result = makeResult(
            columns: ["COUNT(*)"],
            rows: [["COUNT(*)": .integer(42)]]
        )
        let renderer = makeMockRenderer()
        let summary = renderer.localSummary(result: result, userQuestion: "How many?")
        #expect(summary.contains("42"))
    }

    @Test("Local summary for multiple aggregates")
    func localSummaryMultipleAggregates() {
        let result = makeResult(
            columns: ["COUNT(*)", "AVG(price)"],
            rows: [["COUNT(*)": .integer(10), "AVG(price)": .real(25.5)]]
        )
        let renderer = makeMockRenderer()
        let summary = renderer.localSummary(result: result, userQuestion: "Stats?")
        #expect(summary.contains("count"))
        #expect(summary.contains("average price"))
    }

    @Test("Local summary for single record")
    func localSummarySingleRecord() {
        let result = makeResult(
            columns: ["name", "email"],
            rows: [["name": .text("Alice"), "email": .text("alice@example.com")]]
        )
        let renderer = makeMockRenderer()
        let summary = renderer.localSummary(result: result, userQuestion: "Who?")
        #expect(summary.contains("1 result"))
        #expect(summary.contains("Alice"))
    }

    @Test("Local summary for multiple records with name column")
    func localSummaryMultipleWithNames() {
        let result = makeResult(
            columns: ["name", "age"],
            rows: [
                ["name": .text("Alice"), "age": .integer(30)],
                ["name": .text("Bob"), "age": .integer(25)],
                ["name": .text("Charlie"), "age": .integer(35)],
                ["name": .text("Diana"), "age": .integer(28)],
            ]
        )
        let renderer = makeMockRenderer()
        let summary = renderer.localSummary(result: result, userQuestion: "List users")
        #expect(summary.contains("4 results"))
        #expect(summary.contains("Alice"))
        #expect(summary.contains("1 more"))
    }

    @Test("Local summary for mutation result")
    func localSummaryMutation() {
        let result = QueryResult(
            columns: [],
            rows: [],
            sql: "INSERT INTO users (name) VALUES ('Test')",
            executionTime: 0.01,
            rowsAffected: 1
        )
        let renderer = makeMockRenderer()
        let summary = renderer.localSummary(result: result, userQuestion: "Add user")
        #expect(summary == "Successfully inserted 1 row.")
    }

    @Test("Local summary for delete mutation")
    func localSummaryDelete() {
        let result = QueryResult(
            columns: [],
            rows: [],
            sql: "DELETE FROM users WHERE id = 5",
            executionTime: 0.01,
            rowsAffected: 3
        )
        let renderer = makeMockRenderer()
        let summary = renderer.localSummary(result: result, userQuestion: "Delete old users")
        #expect(summary == "Successfully deleted 3 rows.")
    }

    @Test("Local summary for update mutation")
    func localSummaryUpdate() {
        let result = QueryResult(
            columns: [],
            rows: [],
            sql: "UPDATE users SET active = 0 WHERE id = 1",
            executionTime: 0.01,
            rowsAffected: 1
        )
        let renderer = makeMockRenderer()
        let summary = renderer.localSummary(result: result, userQuestion: "Deactivate user")
        #expect(summary == "Successfully updated 1 row.")
    }

    // MARK: - LLM-based Summary Tests (using MockLanguageModel)

    @Test("Summarize with LLM returns mock response for multi-row results")
    func summarizeWithLLM() async throws {
        let result = makeResult(
            columns: ["name", "age"],
            rows: [
                ["name": .text("Alice"), "age": .integer(30)],
                ["name": .text("Bob"), "age": .integer(25)],
            ]
        )
        let mockModel = MockLanguageModel(responseText: "There are 2 users: Alice (30) and Bob (25).")
        let renderer = TextSummaryRenderer(model: mockModel)
        let summary = try await renderer.summarize(result: result, userQuestion: "List all users")
        #expect(summary == "There are 2 users: Alice (30) and Bob (25).")
    }

    @Test("Summarize returns empty result message without calling LLM")
    func summarizeEmptyResult() async throws {
        let result = makeResult(columns: ["id"], rows: [])
        let renderer = makeMockRenderer()
        let summary = try await renderer.summarize(result: result, userQuestion: "Find users")
        #expect(summary == "No results found for your query.")
    }

    @Test("Summarize returns direct aggregate without calling LLM")
    func summarizeAggregate() async throws {
        let result = makeResult(
            columns: ["COUNT(*)"],
            rows: [["COUNT(*)": .integer(42)]]
        )
        let renderer = makeMockRenderer()
        let summary = try await renderer.summarize(result: result, userQuestion: "How many?")
        #expect(summary.contains("42"))
    }

    @Test("Summarize mutation returns template without calling LLM")
    func summarizeMutation() async throws {
        let result = QueryResult(
            columns: [],
            rows: [],
            sql: "UPDATE users SET name = 'Test' WHERE id = 1",
            executionTime: 0.01,
            rowsAffected: 1
        )
        let renderer = makeMockRenderer()
        let summary = try await renderer.summarize(result: result, userQuestion: "Update user")
        #expect(summary == "Successfully updated 1 row.")
    }

    @Test("Summarize passes context to LLM prompt")
    func summarizeWithContext() async throws {
        let result = makeResult(
            columns: ["total"],
            rows: [
                ["total": .real(100.0)],
                ["total": .real(200.0)],
            ]
        )
        let mockModel = MockLanguageModel(responseText: "The totals are 100 and 200.")
        let renderer = TextSummaryRenderer(model: mockModel)
        let summary = try await renderer.summarize(
            result: result,
            userQuestion: "Show totals",
            context: "Amounts are in USD"
        )
        #expect(summary == "The totals are 100 and 200.")
    }

    // MARK: - Helpers

    private func makeResult(
        columns: [String],
        rows: [[String: QueryResult.Value]],
        sql: String = "SELECT * FROM test"
    ) -> QueryResult {
        QueryResult(columns: columns, rows: rows, sql: sql, executionTime: 0.01)
    }

    /// Creates a renderer with a mock model (for localSummary tests that don't hit the LLM).
    private func makeMockRenderer() -> TextSummaryRenderer {
        TextSummaryRenderer(model: MockLanguageModel())
    }
}
