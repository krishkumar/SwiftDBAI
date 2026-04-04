// ScrollableDataTableViewTests.swift
// SwiftDBAITests
//
// Tests for the ScrollableDataTableView component.

import Foundation
import Testing
@testable import SwiftDBAI

@Suite("ScrollableDataTableView")
@MainActor
struct ScrollableDataTableViewTests {

    // MARK: - Test Helpers

    private func makeDataTable(
        columnNames: [String] = ["id", "name", "score"],
        inferredTypes: [DataTable.InferredType] = [.integer, .text, .real],
        rowCount: Int = 5
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

    private func makeEmptyDataTable() -> DataTable {
        DataTable(columns: [], rows: [], sql: "", executionTime: 0)
    }

    // MARK: - Initialization Tests

    @Test("Initializes with default parameters")
    func initWithDefaults() {
        let table = makeDataTable()
        let view = ScrollableDataTableView(dataTable: table)

        #expect(view.minimumColumnWidth == 80)
        #expect(view.maximumColumnWidth == 250)
        #expect(view.showAlternatingRows == true)
        #expect(view.showFooter == true)
    }

    @Test("Initializes with custom parameters")
    func initWithCustomParams() {
        let table = makeDataTable()
        let view = ScrollableDataTableView(
            dataTable: table,
            minimumColumnWidth: 100,
            maximumColumnWidth: 300,
            showAlternatingRows: false,
            showFooter: false
        )

        #expect(view.minimumColumnWidth == 100)
        #expect(view.maximumColumnWidth == 300)
        #expect(view.showAlternatingRows == false)
        #expect(view.showFooter == false)
    }

    @Test("Handles empty data table")
    func handlesEmptyTable() {
        let table = makeEmptyDataTable()
        let view = ScrollableDataTableView(dataTable: table)
        #expect(view.dataTable.isEmpty)
    }

    @Test("Handles single row table")
    func handlesSingleRow() {
        let table = makeDataTable(rowCount: 1)
        let view = ScrollableDataTableView(dataTable: table)
        #expect(view.dataTable.rowCount == 1)
        #expect(view.dataTable.columnCount == 3)
    }

    @Test("Handles single column table")
    func handlesSingleColumn() {
        let columns = [DataTable.Column(name: "count", index: 0, inferredType: .integer)]
        let rows = [
            DataTable.Row(id: 0, values: [.integer(42)], columnNames: ["count"])
        ]
        let table = DataTable(columns: columns, rows: rows, sql: "SELECT count(*) FROM t", executionTime: 0.001)
        let view = ScrollableDataTableView(dataTable: table)
        #expect(view.dataTable.columnCount == 1)
        #expect(view.dataTable.rowCount == 1)
    }

    @Test("Handles large number of rows")
    func handlesLargeRowCount() {
        let table = makeDataTable(rowCount: 1000)
        let view = ScrollableDataTableView(dataTable: table)
        #expect(view.dataTable.rowCount == 1000)
    }

    @Test("Handles null values in cells")
    func handlesNullValues() {
        let columns = [
            DataTable.Column(name: "name", index: 0, inferredType: .text),
            DataTable.Column(name: "value", index: 1, inferredType: .null),
        ]
        let rows = [
            DataTable.Row(id: 0, values: [.text("test"), .null], columnNames: ["name", "value"])
        ]
        let table = DataTable(columns: columns, rows: rows)
        let view = ScrollableDataTableView(dataTable: table)
        #expect(view.dataTable.rows[0][1] == .null)
    }

    @Test("Handles blob values in cells")
    func handlesBlobValues() {
        let columns = [
            DataTable.Column(name: "data", index: 0, inferredType: .blob),
        ]
        let blobData = Data([0x00, 0xFF, 0xAB])
        let rows = [
            DataTable.Row(id: 0, values: [.blob(blobData)], columnNames: ["data"])
        ]
        let table = DataTable(columns: columns, rows: rows)
        let view = ScrollableDataTableView(dataTable: table)
        #expect(view.dataTable.rows[0][0] == QueryResult.Value.blob(blobData))
    }
}
