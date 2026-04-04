// DataTableTests.swift
// SwiftDBAITests

import Foundation
import Testing
@testable import SwiftDBAI

@Suite("DataTable")
struct DataTableTests {

    // MARK: - Helpers

    private func makeQueryResult(
        columns: [String],
        rows: [[String: QueryResult.Value]],
        sql: String = "SELECT * FROM test",
        executionTime: TimeInterval = 0.01
    ) -> QueryResult {
        QueryResult(
            columns: columns,
            rows: rows,
            sql: sql,
            executionTime: executionTime
        )
    }

    // MARK: - Basic Construction

    @Test("Converts QueryResult columns and rows correctly")
    func basicConversion() {
        let result = makeQueryResult(
            columns: ["id", "name", "score"],
            rows: [
                ["id": .integer(1), "name": .text("Alice"), "score": .real(95.5)],
                ["id": .integer(2), "name": .text("Bob"), "score": .real(87.0)],
            ]
        )

        let table = DataTable(result)

        #expect(table.columnCount == 3)
        #expect(table.rowCount == 2)
        #expect(table.columnNames == ["id", "name", "score"])
        #expect(table.sql == "SELECT * FROM test")
        #expect(table.executionTime == 0.01)
    }

    @Test("Empty result produces empty table")
    func emptyResult() {
        let result = makeQueryResult(columns: ["id", "name"], rows: [])

        let table = DataTable(result)

        #expect(table.isEmpty)
        #expect(table.rowCount == 0)
        #expect(table.columnCount == 2)
        #expect(table.columnNames == ["id", "name"])
    }

    // MARK: - Subscript Access

    @Test("Subscript by row and column index")
    func subscriptByIndex() {
        let result = makeQueryResult(
            columns: ["a", "b"],
            rows: [
                ["a": .integer(10), "b": .text("hello")],
                ["a": .integer(20), "b": .text("world")],
            ]
        )

        let table = DataTable(result)

        #expect(table[row: 0, column: 0] == .integer(10))
        #expect(table[row: 0, column: 1] == .text("hello"))
        #expect(table[row: 1, column: 0] == .integer(20))
        #expect(table[row: 1, column: 1] == .text("world"))
    }

    @Test("Subscript by row index and column name")
    func subscriptByName() {
        let result = makeQueryResult(
            columns: ["x", "y"],
            rows: [["x": .real(1.5), "y": .real(2.5)]]
        )

        let table = DataTable(result)

        #expect(table[row: 0, column: "x"] == .real(1.5))
        #expect(table[row: 0, column: "y"] == .real(2.5))
        #expect(table[row: 0, column: "z"] == .null) // non-existent column
    }

    // MARK: - Column Data Extraction

    @Test("Extract column values by index")
    func columnValuesByIndex() {
        let result = makeQueryResult(
            columns: ["val"],
            rows: [
                ["val": .integer(1)],
                ["val": .integer(2)],
                ["val": .integer(3)],
            ]
        )

        let table = DataTable(result)
        let values = table.columnValues(at: 0)

        #expect(values == [.integer(1), .integer(2), .integer(3)])
    }

    @Test("Extract column values by name")
    func columnValuesByName() {
        let result = makeQueryResult(
            columns: ["name"],
            rows: [
                ["name": .text("A")],
                ["name": .text("B")],
            ]
        )

        let table = DataTable(result)

        #expect(table.columnValues(named: "name") == [.text("A"), .text("B")])
        #expect(table.columnValues(named: "missing").isEmpty)
    }

    @Test("numericValues extracts doubles from numeric column")
    func numericValues() {
        let result = makeQueryResult(
            columns: ["score"],
            rows: [
                ["score": .integer(10)],
                ["score": .real(20.5)],
                ["score": .null],
                ["score": .text("not a number")],
            ]
        )

        let table = DataTable(result)
        let nums = table.numericValues(forColumn: "score")

        #expect(nums.count == 2)
        #expect(nums[0] == 10.0)
        #expect(nums[1] == 20.5)
    }

    @Test("stringValues extracts non-null strings")
    func stringValues() {
        let result = makeQueryResult(
            columns: ["label"],
            rows: [
                ["label": .text("foo")],
                ["label": .null],
                ["label": .text("bar")],
            ]
        )

        let table = DataTable(result)
        let strs = table.stringValues(forColumn: "label")

        #expect(strs == ["foo", "bar"])
    }

    // MARK: - Type Inference

    @Test("Infers integer type for all-integer column")
    func inferInteger() {
        let result = makeQueryResult(
            columns: ["id"],
            rows: [["id": .integer(1)], ["id": .integer(2)]]
        )
        let table = DataTable(result)
        #expect(table.columns[0].inferredType == .integer)
    }

    @Test("Infers real type for all-real column")
    func inferReal() {
        let result = makeQueryResult(
            columns: ["price"],
            rows: [["price": .real(1.99)], ["price": .real(2.50)]]
        )
        let table = DataTable(result)
        #expect(table.columns[0].inferredType == .real)
    }

    @Test("Infers text type for all-text column")
    func inferText() {
        let result = makeQueryResult(
            columns: ["name"],
            rows: [["name": .text("A")], ["name": .text("B")]]
        )
        let table = DataTable(result)
        #expect(table.columns[0].inferredType == .text)
    }

    @Test("Promotes integer + real to real")
    func inferNumericPromotion() {
        let result = makeQueryResult(
            columns: ["val"],
            rows: [["val": .integer(1)], ["val": .real(2.5)]]
        )
        let table = DataTable(result)
        #expect(table.columns[0].inferredType == .real)
    }

    @Test("Mixed types result in .mixed")
    func inferMixed() {
        let result = makeQueryResult(
            columns: ["data"],
            rows: [["data": .integer(1)], ["data": .text("hello")]]
        )
        let table = DataTable(result)
        #expect(table.columns[0].inferredType == .mixed)
    }

    @Test("All-null column infers .null")
    func inferNull() {
        let result = makeQueryResult(
            columns: ["empty"],
            rows: [["empty": .null], ["empty": .null]]
        )
        let table = DataTable(result)
        #expect(table.columns[0].inferredType == .null)
    }

    @Test("Null values are ignored during type inference")
    func inferIgnoresNulls() {
        let result = makeQueryResult(
            columns: ["val"],
            rows: [["val": .integer(1)], ["val": .null], ["val": .integer(3)]]
        )
        let table = DataTable(result)
        #expect(table.columns[0].inferredType == .integer)
    }

    // MARK: - Missing Values

    @Test("Missing dictionary keys become .null")
    func missingKeysBecomNull() {
        let result = makeQueryResult(
            columns: ["a", "b"],
            rows: [["a": .integer(1)]] // "b" is missing
        )

        let table = DataTable(result)

        #expect(table[row: 0, column: 0] == .integer(1))
        #expect(table[row: 0, column: 1] == .null)
    }

    // MARK: - Row Identity

    @Test("Rows have sequential IDs")
    func rowIdentity() {
        let result = makeQueryResult(
            columns: ["x"],
            rows: [["x": .integer(1)], ["x": .integer(2)], ["x": .integer(3)]]
        )

        let table = DataTable(result)

        #expect(table.rows[0].id == 0)
        #expect(table.rows[1].id == 1)
        #expect(table.rows[2].id == 2)
    }

    // MARK: - Column Identity

    @Test("Columns are Identifiable by name")
    func columnIdentity() {
        let result = makeQueryResult(
            columns: ["alpha", "beta"],
            rows: [["alpha": .integer(1), "beta": .integer(2)]]
        )

        let table = DataTable(result)

        #expect(table.columns[0].id == "alpha")
        #expect(table.columns[1].id == "beta")
        #expect(table.columns[0].index == 0)
        #expect(table.columns[1].index == 1)
    }
}
