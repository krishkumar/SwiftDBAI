// ChartDataDetectorTests.swift
// SwiftDBAITests

import Testing
@testable import SwiftDBAI

@Suite("ChartDataDetector")
struct ChartDataDetectorTests {

    let detector = ChartDataDetector()

    // MARK: - Helpers

    private func makeQueryResult(
        columns: [String],
        rows: [[QueryResult.Value]],
        sql: String = "SELECT *"
    ) -> QueryResult {
        let rowDicts = rows.map { values in
            Dictionary(uniqueKeysWithValues: zip(columns, values))
        }
        return QueryResult(
            columns: columns,
            rows: rowDicts,
            sql: sql,
            executionTime: 0.01
        )
    }

    private func makeTable(
        columns: [String],
        rows: [[QueryResult.Value]],
        sql: String = "SELECT *"
    ) -> DataTable {
        DataTable(makeQueryResult(columns: columns, rows: rows, sql: sql))
    }

    // MARK: - Basic Eligibility

    @Test("Returns nil for single-column results")
    func singleColumn() {
        let table = makeTable(
            columns: ["count"],
            rows: [[.integer(42)]]
        )
        #expect(detector.detect(table) == nil)
    }

    @Test("Returns nil for empty results")
    func emptyResults() {
        let table = makeTable(columns: ["name", "value"], rows: [])
        #expect(detector.detect(table) == nil)
    }

    @Test("Returns nil for single row")
    func singleRow() {
        let table = makeTable(
            columns: ["name", "count"],
            rows: [[.text("A"), .integer(10)]]
        )
        #expect(detector.detect(table) == nil)
    }

    @Test("Returns nil for too many rows")
    func tooManyRows() {
        let rows = (0..<101).map { i in
            [QueryResult.Value.text("cat\(i)"), .integer(Int64(i))]
        }
        let table = makeTable(columns: ["name", "count"], rows: rows)
        #expect(detector.detect(table) == nil)
    }

    // MARK: - Bar Chart Detection

    @Test("Recommends bar chart for categorical text + numeric")
    func barChartCategorical() {
        let table = makeTable(
            columns: ["department", "headcount"],
            rows: [
                [.text("Engineering"), .integer(45)],
                [.text("Marketing"), .integer(20)],
                [.text("Sales"), .integer(30)],
                [.text("HR"), .integer(10)],
            ]
        )
        let rec = detector.detect(table)
        #expect(rec != nil)
        #expect(rec?.chartType == .bar)
        #expect(rec?.categoryColumn == "department")
        #expect(rec?.valueColumn == "headcount")
        #expect(rec?.confidence ?? 0 > 0.5)
    }

    // MARK: - Pie Chart Detection

    @Test("Recommends pie chart for small positive proportions")
    func pieChartSmallCategories() {
        let table = makeTable(
            columns: ["status", "count"],
            rows: [
                [.text("Active"), .integer(50)],
                [.text("Inactive"), .integer(30)],
                [.text("Pending"), .integer(20)],
            ]
        )
        let rec = detector.detect(table)
        #expect(rec != nil)
        #expect(rec?.chartType == .pie)
        #expect(rec?.categoryColumn == "status")
        #expect(rec?.valueColumn == "count")
    }

    @Test("Does not recommend pie with negative values")
    func pieRejectsNegative() {
        let table = makeTable(
            columns: ["category", "change"],
            rows: [
                [.text("A"), .integer(50)],
                [.text("B"), .integer(-10)],
                [.text("C"), .integer(20)],
            ]
        )
        let rec = detector.detect(table)
        #expect(rec != nil)
        // Should NOT be pie since there's a negative value
        #expect(rec?.chartType != .pie)
    }

    @Test("Does not recommend pie with too many slices")
    func pieRejectsTooManySlices() {
        let rows = (0..<10).map { i in
            [QueryResult.Value.text("cat\(i)"), .integer(Int64(i + 1))]
        }
        let table = makeTable(columns: ["category", "value"], rows: rows)
        let rec = detector.detect(table)
        #expect(rec != nil)
        #expect(rec?.chartType != .pie)
    }

    // MARK: - Line Chart Detection

    @Test("Recommends line chart for time-series column names")
    func lineChartTimeSeries() {
        let table = makeTable(
            columns: ["year", "revenue"],
            rows: [
                [.text("2020"), .real(1_000_000)],
                [.text("2021"), .real(1_200_000)],
                [.text("2022"), .real(1_500_000)],
                [.text("2023"), .real(1_800_000)],
                [.text("2024"), .real(2_100_000)],
            ]
        )
        let rec = detector.detect(table)
        #expect(rec != nil)
        #expect(rec?.chartType == .line)
        #expect(rec?.categoryColumn == "year")
        #expect(rec?.valueColumn == "revenue")
    }

    @Test("Recommends line chart for date-formatted text values")
    func lineChartDateValues() {
        let table = makeTable(
            columns: ["period", "sales"],
            rows: [
                [.text("2024-01"), .integer(100)],
                [.text("2024-02"), .integer(120)],
                [.text("2024-03"), .integer(90)],
                [.text("2024-04"), .integer(150)],
            ]
        )
        let rec = detector.detect(table)
        #expect(rec != nil)
        #expect(rec?.chartType == .line)
    }

    @Test("Recommends line chart for sequential numeric x-axis")
    func lineChartSequential() {
        let table = makeTable(
            columns: ["step", "value"],
            rows: [
                [.integer(1), .real(2.5)],
                [.integer(2), .real(3.1)],
                [.integer(3), .real(4.0)],
                [.integer(4), .real(3.8)],
            ]
        )
        let rec = detector.detect(table)
        #expect(rec != nil)
        #expect(rec?.chartType == .line)
    }

    // MARK: - All Recommendations

    @Test("Returns multiple recommendations sorted by confidence")
    func allRecommendations() {
        let table = makeTable(
            columns: ["category", "amount"],
            rows: [
                [.text("A"), .integer(30)],
                [.text("B"), .integer(50)],
                [.text("C"), .integer(20)],
            ]
        )
        let recs = detector.allRecommendations(for: table)
        #expect(!recs.isEmpty)
        // Should be sorted by confidence descending
        for i in 1..<recs.count {
            #expect(recs[i - 1].confidence >= recs[i].confidence)
        }
    }

    // MARK: - Two Numeric Columns Fallback

    @Test("Uses first numeric as category when no text column exists")
    func numericOnlyColumns() {
        let table = makeTable(
            columns: ["x", "y"],
            rows: [
                [.integer(1), .integer(10)],
                [.integer(2), .integer(20)],
                [.integer(3), .integer(30)],
            ]
        )
        let rec = detector.detect(table)
        #expect(rec != nil)
        #expect(rec?.categoryColumn == "x")
        #expect(rec?.valueColumn == "y")
    }

    // MARK: - Confidence & Reason

    @Test("Confidence is between 0 and 1")
    func confidenceBounds() {
        let table = makeTable(
            columns: ["name", "score"],
            rows: [
                [.text("A"), .integer(10)],
                [.text("B"), .integer(20)],
            ]
        )
        let rec = detector.detect(table)
        #expect(rec != nil)
        #expect(rec!.confidence >= 0.0)
        #expect(rec!.confidence <= 1.0)
    }

    @Test("Reason is non-empty")
    func reasonPresent() {
        let table = makeTable(
            columns: ["name", "score"],
            rows: [
                [.text("A"), .integer(10)],
                [.text("B"), .integer(20)],
            ]
        )
        let rec = detector.detect(table)
        #expect(rec != nil)
        #expect(!rec!.reason.isEmpty)
    }

    // MARK: - Custom Configuration

    @Test("Respects custom minimumRows")
    func customMinRows() {
        let strict = ChartDataDetector(minimumRows: 5)
        let table = makeTable(
            columns: ["name", "value"],
            rows: [
                [.text("A"), .integer(1)],
                [.text("B"), .integer(2)],
                [.text("C"), .integer(3)],
            ]
        )
        #expect(strict.detect(table) == nil)
    }

    @Test("Respects custom maxPieSlices")
    func customMaxPieSlices() {
        let narrow = ChartDataDetector(maxPieSlices: 2)
        let table = makeTable(
            columns: ["status", "count"],
            rows: [
                [.text("A"), .integer(50)],
                [.text("B"), .integer(30)],
                [.text("C"), .integer(20)],
            ]
        )
        let rec = narrow.detect(table)
        // With maxPieSlices=2, 3 rows should not get pie
        #expect(rec?.chartType != .pie)
    }
}
