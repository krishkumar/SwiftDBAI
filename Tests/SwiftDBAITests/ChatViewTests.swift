// ChatViewTests.swift
// SwiftDBAITests
//
// Tests for ChatView, ChatViewModel, and MessageBubbleView integration
// with ScrollableDataTableView.

import Testing
import Foundation
@testable import SwiftDBAI

@Suite("SchemaReadiness Tests")
struct SchemaReadinessTests {

    @Test("SchemaReadiness isReady returns true only for ready state")
    func isReadyProperty() {
        #expect(SchemaReadiness.idle.isReady == false)
        #expect(SchemaReadiness.loading.isReady == false)
        #expect(SchemaReadiness.ready(tableCount: 3).isReady == true)
        #expect(SchemaReadiness.failed("error").isReady == false)
    }
}

@Suite("ChatViewModel Tests")
struct ChatViewModelTests {

    @Test("Messages with query results produce DataTable-compatible data")
    func messageWithQueryResultHasTableData() {
        // A ChatMessage with a queryResult should have the data needed
        // for ScrollableDataTableView rendering
        let result = QueryResult(
            columns: ["id", "name", "score"],
            rows: [
                ["id": .integer(1), "name": .text("Alice"), "score": .real(95.5)],
                ["id": .integer(2), "name": .text("Bob"), "score": .real(87.3)],
            ],
            sql: "SELECT id, name, score FROM users",
            executionTime: 0.01
        )

        let message = ChatMessage(
            role: .assistant,
            content: "Found 2 users.",
            queryResult: result,
            sql: "SELECT id, name, score FROM users"
        )

        // Verify queryResult is present and can be converted to DataTable
        #expect(message.queryResult != nil)
        #expect(message.queryResult!.columns.count == 3)
        #expect(message.queryResult!.rows.count == 2)

        // Verify DataTable conversion works (this is what MessageBubbleView does)
        let dataTable = DataTable(message.queryResult!)
        #expect(dataTable.columnCount == 3)
        #expect(dataTable.rowCount == 2)
        #expect(dataTable.columns[0].name == "id")
        #expect(dataTable.columns[1].name == "name")
        #expect(dataTable.columns[2].name == "score")
    }

    @Test("Messages without query results do not trigger table rendering")
    func messageWithoutQueryResult() {
        let message = ChatMessage(
            role: .assistant,
            content: "Hello! How can I help?",
            queryResult: nil,
            sql: nil
        )

        #expect(message.queryResult == nil)
    }

    @Test("Empty query results do not trigger table rendering")
    func emptyQueryResult() {
        let result = QueryResult(
            columns: [],
            rows: [],
            sql: "SELECT * FROM empty_table",
            executionTime: 0.001
        )

        let message = ChatMessage(
            role: .assistant,
            content: "No results found.",
            queryResult: result,
            sql: "SELECT * FROM empty_table"
        )

        // Even though queryResult exists, it has no columns/rows
        // MessageBubbleView checks both conditions before showing the table
        #expect(message.queryResult != nil)
        #expect(message.queryResult!.columns.isEmpty)
        #expect(message.queryResult!.rows.isEmpty)
    }

    @Test("Mutation results do not trigger table rendering")
    func mutationQueryResult() {
        let result = QueryResult(
            columns: [],
            rows: [],
            sql: "INSERT INTO users (name) VALUES ('Charlie')",
            executionTime: 0.005,
            rowsAffected: 1
        )

        let message = ChatMessage(
            role: .assistant,
            content: "Successfully inserted 1 row.",
            queryResult: result,
            sql: "INSERT INTO users (name) VALUES ('Charlie')"
        )

        // Mutation results have empty columns — no table shown
        #expect(message.queryResult!.columns.isEmpty)
    }

    @Test("Error messages never have query results")
    func errorMessageHasNoQueryResult() {
        let message = ChatMessage(
            role: .error,
            content: "SELECT operations are not allowed."
        )

        #expect(message.queryResult == nil)
        #expect(message.role == .error)
    }

    @Test("DataTable preserves column order from QueryResult")
    func dataTableColumnOrder() {
        let result = QueryResult(
            columns: ["date", "revenue", "category"],
            rows: [
                ["date": .text("2024-01-01"), "revenue": .real(1500.0), "category": .text("Electronics")],
            ],
            sql: "SELECT date, revenue, category FROM sales",
            executionTime: 0.02
        )

        let dataTable = DataTable(result)
        #expect(dataTable.columnNames == ["date", "revenue", "category"])
    }

    @Test("Large result sets are renderable as DataTable")
    func largeResultSet() {
        var rows: [[String: QueryResult.Value]] = []
        for i in 0..<500 {
            rows.append([
                "id": .integer(Int64(i)),
                "value": .real(Double(i) * 1.5),
            ])
        }

        let result = QueryResult(
            columns: ["id", "value"],
            rows: rows,
            sql: "SELECT id, value FROM big_table",
            executionTime: 0.15
        )

        let dataTable = DataTable(result)
        #expect(dataTable.rowCount == 500)
        #expect(dataTable.columnCount == 2)
    }
}
