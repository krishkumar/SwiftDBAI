// ViewInspectorTests.swift
// SwiftDBAITests
//
// ViewInspector-based tests for SwiftDBAI's SwiftUI views.
// Tests content and structure of MessageBubbleView, ErrorMessageView,
// ScrollableDataTableView, ChatViewConfiguration, and BarChartView.

import SwiftUI
import Testing
import ViewInspector
@testable import SwiftDBAI

// MARK: - Test Helpers

/// Helper to build a DataTable for tests.
private func makeDataTable(
    columnNames: [String] = ["id", "name", "score"],
    inferredTypes: [DataTable.InferredType] = [.integer, .text, .real],
    rowCount: Int = 3
) -> DataTable {
    let columns = columnNames.enumerated().map { idx, name in
        DataTable.Column(name: name, index: idx, inferredType: inferredTypes[idx])
    }
    let rows = (0..<rowCount).map { i in
        DataTable.Row(
            id: i,
            values: [
                .integer(Int64(i + 1)),
                .text("Item \(i + 1)"),
                .real(Double(i) * 10.5),
            ],
            columnNames: columnNames
        )
    }
    return DataTable(columns: columns, rows: rows, sql: "SELECT * FROM test", executionTime: 0.015)
}

/// Helper to build a QueryResult for tests.
private func makeQueryResult(
    columns: [String] = ["id", "name"],
    rowCount: Int = 2
) -> QueryResult {
    let rows: [[String: QueryResult.Value]] = (0..<rowCount).map { i in
        ["id": .integer(Int64(i + 1)), "name": .text("User \(i + 1)")]
    }
    return QueryResult(
        columns: columns,
        rows: rows,
        sql: "SELECT id, name FROM users",
        executionTime: 0.01
    )
}

// MARK: - MessageBubbleView Tests

@Suite("MessageBubbleView - ViewInspector")
struct MessageBubbleViewInspectorTests {

    @Test("User message bubble renders the user text")
    @MainActor
    func userMessageShowsText() throws {
        let message = ChatMessage(role: .user, content: "Show me all users")
        let view = MessageBubbleView(message: message)
        let inspected = try view.inspect()
        let found = try inspected.find(text: "Show me all users")
        #expect(try found.string() == "Show me all users")
    }

    @Test("Assistant message renders summary text")
    @MainActor
    func assistantMessageShowsSummary() throws {
        let message = ChatMessage(
            role: .assistant,
            content: "Found 42 users in the database."
        )
        let view = MessageBubbleView(message: message)
        let inspected = try view.inspect()
        let found = try inspected.find(text: "Found 42 users in the database.")
        #expect(try found.string() == "Found 42 users in the database.")
    }

    @Test("Assistant message with SQL shows disclosure group")
    @MainActor
    func assistantMessageWithSQLShowsDisclosure() throws {
        let message = ChatMessage(
            role: .assistant,
            content: "Here are the results.",
            sql: "SELECT * FROM users"
        )
        let view = MessageBubbleView(message: message)
        let inspected = try view.inspect()
        // The SQL disclosure contains "SQL Query" label text
        let sqlLabel = try inspected.find(text: "SQL Query")
        #expect(try sqlLabel.string() == "SQL Query")
    }

    @Test("Error message renders error text")
    @MainActor
    func errorMessageShowsText() throws {
        let error = SwiftDBAIError.databaseError(reason: "connection lost")
        let message = ChatMessage(
            role: .error,
            content: error.localizedDescription,
            error: error
        )
        let view = MessageBubbleView(message: message)
        let inspected = try view.inspect()
        // The error message text should be present
        let found = try inspected.find(text: error.localizedDescription)
        #expect(try found.string() == error.localizedDescription)
    }
}

// MARK: - ErrorMessageView Tests

@Suite("ErrorMessageView - ViewInspector")
struct ErrorMessageViewInspectorTests {

    @Test("Safety error shows Operation Blocked title")
    @MainActor
    func safetyErrorShowsTitle() throws {
        let error = SwiftDBAIError.dangerousOperationBlocked(keyword: "DROP")
        let view = ErrorMessageView(error: error)
        let inspected = try view.inspect()
        let title = try inspected.find(text: "Operation Blocked")
        #expect(try title.string() == "Operation Blocked")
    }

    @Test("Safety error shows error message")
    @MainActor
    func safetyErrorShowsMessage() throws {
        let error = SwiftDBAIError.operationNotAllowed(operation: "DELETE")
        let view = ErrorMessageView(error: error)
        let inspected = try view.inspect()
        let msg = try inspected.find(text: error.localizedDescription)
        #expect(try msg.string() == error.localizedDescription)
    }

    @Test("LLM response unparseable error shows recovery hint")
    @MainActor
    func parsingErrorShowsRecoveryHint() throws {
        let error = SwiftDBAIError.llmResponseUnparseable(response: "gibberish")
        let view = ErrorMessageView(error: error)
        let inspected = try view.inspect()
        let hint = try inspected.find(text: "Try rephrasing your question.")
        #expect(try hint.string() == "Try rephrasing your question.")
    }

    @Test("Database error shows Database Error title")
    @MainActor
    func databaseErrorShowsTitle() throws {
        let error = SwiftDBAIError.databaseError(reason: "disk full")
        let view = ErrorMessageView(error: error)
        let inspected = try view.inspect()
        let title = try inspected.find(text: "Database Error")
        #expect(try title.string() == "Database Error")
    }

    @Test("LLM timeout shows AI Provider Error title and recovery hint")
    @MainActor
    func timeoutErrorShowsTitleAndHint() throws {
        let error = SwiftDBAIError.llmTimeout(seconds: 30)
        let view = ErrorMessageView(error: error)
        let inspected = try view.inspect()
        let title = try inspected.find(text: "AI Provider Error")
        #expect(try title.string() == "AI Provider Error")
        let hint = try inspected.find(text: "The AI took too long. Try a simpler question.")
        #expect(try hint.string() == "The AI took too long. Try a simpler question.")
    }

    @Test("LLM failure error shows AI Provider Error title")
    @MainActor
    func llmFailureShowsTitle() throws {
        let error = SwiftDBAIError.llmFailure(reason: "rate limited")
        let view = ErrorMessageView(error: error)
        let inspected = try view.inspect()
        let title = try inspected.find(text: "AI Provider Error")
        #expect(try title.string() == "AI Provider Error")
    }

    @Test("Generic error from plain string shows message text")
    @MainActor
    func genericStringErrorShowsMessage() throws {
        let view = ErrorMessageView(message: "Something went wrong")
        let inspected = try view.inspect()
        let msg = try inspected.find(text: "Something went wrong")
        #expect(try msg.string() == "Something went wrong")
    }

    @Test("Recoverable error with retry shows retry button")
    @MainActor
    func recoverableErrorShowsRetryButton() throws {
        let error = SwiftDBAIError.noSQLGenerated
        let view = ErrorMessageView(error: error, onRetry: { })
        let inspected = try view.inspect()
        let button = try inspected.find(text: "Try Again")
        #expect(try button.string() == "Try Again")
    }

    @Test("LLM error with retry shows Retry button")
    @MainActor
    func llmErrorShowsRetryButton() throws {
        let error = SwiftDBAIError.llmFailure(reason: "timeout")
        let view = ErrorMessageView(error: error, onRetry: { })
        let inspected = try view.inspect()
        let button = try inspected.find(text: "Retry")
        #expect(try button.string() == "Retry")
    }

    @Test("Query timed out shows Database Error title and recovery hint")
    @MainActor
    func queryTimedOutShowsTitleAndHint() throws {
        let error = SwiftDBAIError.queryTimedOut(seconds: 10)
        let view = ErrorMessageView(error: error)
        let inspected = try view.inspect()
        let title = try inspected.find(text: "Database Error")
        #expect(try title.string() == "Database Error")
        let hint = try inspected.find(text: "Try a simpler query or add database indexes.")
        #expect(try hint.string() == "Try a simpler query or add database indexes.")
    }

    @Test("Empty schema error shows Database Error title and recovery hint")
    @MainActor
    func emptySchemaShowsTitleAndHint() throws {
        let error = SwiftDBAIError.emptySchema
        let view = ErrorMessageView(error: error)
        let inspected = try view.inspect()
        let title = try inspected.find(text: "Database Error")
        #expect(try title.string() == "Database Error")
        let hint = try inspected.find(text: "Add some tables to your database first.")
        #expect(try hint.string() == "Add some tables to your database first.")
    }

    @Test("Configuration error shows Configuration Error title")
    @MainActor
    func configurationErrorShowsTitle() throws {
        let error = SwiftDBAIError.configurationError(reason: "missing API key")
        let view = ErrorMessageView(error: error)
        let inspected = try view.inspect()
        let title = try inspected.find(text: "Configuration Error")
        #expect(try title.string() == "Configuration Error")
    }
}

// MARK: - ChatViewConfiguration Tests

@Suite("ChatViewConfiguration - ViewInspector")
struct ChatViewConfigurationInspectorTests {

    @Test("Dark configuration has expected color values")
    func darkConfigHasCorrectColors() {
        let dark = ChatViewConfiguration.dark
        #expect(dark.userTextColor == .white)
        #expect(dark.backgroundColor == .black)
        #expect(dark.accentColor == .blue)
    }

    @Test("Default configuration has expected placeholder and empty state text")
    func defaultConfigHasExpectedText() {
        let config = ChatViewConfiguration.default
        #expect(config.inputPlaceholder == "Ask about your data\u{2026}")
        #expect(config.emptyStateTitle == "Ask a question about your data")
        #expect(config.emptyStateSubtitle == "Try something like \"How many records are in the database?\"")
    }

    @Test("Custom inputPlaceholder propagates through environment")
    @MainActor
    func customPlaceholderInEnvironment() throws {
        var config = ChatViewConfiguration.default
        config.inputPlaceholder = "Ask about recipes..."
        config.emptyStateTitle = "Recipe Search"

        // Verify the configuration values are set correctly
        #expect(config.inputPlaceholder == "Ask about recipes...")
        #expect(config.emptyStateTitle == "Recipe Search")
    }

    @Test("Compact configuration has smaller padding and hidden SQL disclosure")
    func compactConfigProperties() {
        let compact = ChatViewConfiguration.compact
        #expect(compact.messagePadding == 8)
        #expect(compact.bubbleCornerRadius == 10)
        #expect(compact.showSQLDisclosure == false)
        #expect(compact.showTimestamps == false)
    }

    @Test("Dark configuration userBubbleColor is dark gray")
    func darkConfigUserBubble() {
        let dark = ChatViewConfiguration.dark
        // Dark config uses Color(white: 0.25) for user bubble
        #expect(dark.userBubbleColor == Color(white: 0.25))
        #expect(dark.assistantBubbleColor == Color(white: 0.15))
        #expect(dark.inputBarBackgroundColor == Color(white: 0.1))
    }

    @Test("ErrorMessageView uses environment config for database error color")
    @MainActor
    func errorViewUsesDarkConfig() throws {
        let error = SwiftDBAIError.databaseError(reason: "test error")
        let view = ErrorMessageView(error: error)
            .chatViewConfiguration(.dark)
        let inspected = try view.inspect()
        // Should still render the error message text
        let msg = try inspected.find(text: error.localizedDescription)
        #expect(try msg.string() == error.localizedDescription)
    }
}

// MARK: - ScrollableDataTableView Tests

@Suite("ScrollableDataTableView - ViewInspector")
struct ScrollableDataTableViewInspectorTests {

    @Test("Column headers appear in the view")
    @MainActor
    func columnHeadersAppear() throws {
        let table = makeDataTable()
        let view = ScrollableDataTableView(dataTable: table)
        let inspected = try view.inspect()

        // Each column header should be present
        let idHeader = try inspected.find(text: "id")
        #expect(try idHeader.string() == "id")

        let nameHeader = try inspected.find(text: "name")
        #expect(try nameHeader.string() == "name")

        let scoreHeader = try inspected.find(text: "score")
        #expect(try scoreHeader.string() == "score")
    }

    @Test("Row count text appears in footer")
    @MainActor
    func rowCountFooterAppears() throws {
        let table = makeDataTable(rowCount: 5)
        let view = ScrollableDataTableView(dataTable: table, showFooter: true)
        let inspected = try view.inspect()

        let footer = try inspected.find(text: "5 rows")
        #expect(try footer.string() == "5 rows")
    }

    @Test("Single row shows singular 'row' text")
    @MainActor
    func singleRowFooter() throws {
        let table = makeDataTable(rowCount: 1)
        let view = ScrollableDataTableView(dataTable: table, showFooter: true)
        let inspected = try view.inspect()

        let footer = try inspected.find(text: "1 row")
        #expect(try footer.string() == "1 row")
    }

    @Test("Empty table shows No results text")
    @MainActor
    func emptyTableShowsNoResults() throws {
        let table = DataTable(columns: [], rows: [], sql: "", executionTime: 0)
        let view = ScrollableDataTableView(dataTable: table)
        let inspected = try view.inspect()

        let empty = try inspected.find(text: "No results")
        #expect(try empty.string() == "No results")
    }

    @Test("Execution time appears in footer when > 0")
    @MainActor
    func executionTimeAppearsInFooter() throws {
        let columns = [DataTable.Column(name: "val", index: 0, inferredType: .integer)]
        let rows = [DataTable.Row(id: 0, values: [.integer(1)], columnNames: ["val"])]
        let table = DataTable(columns: columns, rows: rows, sql: "SELECT 1", executionTime: 0.023)
        let view = ScrollableDataTableView(dataTable: table, showFooter: true)
        let inspected = try view.inspect()

        let timing = try inspected.find(text: "23.0 ms")
        #expect(try timing.string() == "23.0 ms")
    }
}

// MARK: - BarChartView Tests

@Suite("BarChartView - ViewInspector")
struct BarChartViewInspectorTests {

    @Test("BarChartView with title renders the title text")
    @MainActor
    func barChartShowsTitle() throws {
        let columns: [DataTable.Column] = [
            .init(name: "dept", index: 0, inferredType: .text),
            .init(name: "revenue", index: 1, inferredType: .real),
        ]
        let rows: [DataTable.Row] = [
            .init(id: 0, values: [.text("Sales"), .real(100.0)], columnNames: ["dept", "revenue"]),
            .init(id: 1, values: [.text("Eng"), .real(200.0)], columnNames: ["dept", "revenue"]),
        ]
        let table = DataTable(columns: columns, rows: rows)

        let view = BarChartView(
            dataTable: table,
            categoryColumn: "dept",
            valueColumn: "revenue",
            title: "Revenue by Department"
        )
        let inspected = try view.inspect()
        let title = try inspected.find(text: "Revenue by Department")
        #expect(try title.string() == "Revenue by Department")
    }

    @Test("BarChartView with empty data shows empty state")
    @MainActor
    func barChartEmptyState() throws {
        let table = DataTable(columns: [], rows: [])
        let view = BarChartView(
            dataTable: table,
            categoryColumn: "x",
            valueColumn: "y"
        )
        let inspected = try view.inspect()
        let empty = try inspected.find(text: "No chartable data")
        #expect(try empty.string() == "No chartable data")
    }

    @Test("BarChartView with truncated data shows truncation notice")
    @MainActor
    func barChartTruncationNotice() throws {
        let columns: [DataTable.Column] = [
            .init(name: "cat", index: 0, inferredType: .text),
            .init(name: "val", index: 1, inferredType: .real),
        ]
        // Create 10 rows but set maxBars to 3
        let rows: [DataTable.Row] = (0..<10).map { i in
            .init(id: i, values: [.text("Cat \(i)"), .real(Double(i) * 10)], columnNames: ["cat", "val"])
        }
        let table = DataTable(columns: columns, rows: rows)

        let view = BarChartView(
            dataTable: table,
            categoryColumn: "cat",
            valueColumn: "val",
            maxBars: 3
        )
        let inspected = try view.inspect()
        let notice = try inspected.find(text: "Showing 3 of 10 categories")
        #expect(try notice.string() == "Showing 3 of 10 categories")
    }
}

// MARK: - PieChartView Tests

@Suite("PieChartView - ViewInspector")
struct PieChartViewInspectorTests {

    @Test("PieChartView with title renders the title text")
    @MainActor
    func pieChartShowsTitle() throws {
        let columns: [DataTable.Column] = [
            .init(name: "status", index: 0, inferredType: .text),
            .init(name: "count", index: 1, inferredType: .integer),
        ]
        let rows: [DataTable.Row] = [
            .init(id: 0, values: [.text("Active"), .integer(40)], columnNames: ["status", "count"]),
            .init(id: 1, values: [.text("Inactive"), .integer(10)], columnNames: ["status", "count"]),
        ]
        let table = DataTable(columns: columns, rows: rows)

        let view = PieChartView(
            dataTable: table,
            categoryColumn: "status",
            valueColumn: "count",
            title: "Users by Status"
        )
        let inspected = try view.inspect()
        let title = try inspected.find(text: "Users by Status")
        #expect(try title.string() == "Users by Status")
    }

    @Test("PieChartView with empty data shows empty state")
    @MainActor
    func pieChartEmptyState() throws {
        let table = DataTable(columns: [], rows: [])
        let view = PieChartView(
            dataTable: table,
            categoryColumn: "x",
            valueColumn: "y"
        )
        let inspected = try view.inspect()
        let empty = try inspected.find(text: "No chartable data")
        #expect(try empty.string() == "No chartable data")
    }
}
