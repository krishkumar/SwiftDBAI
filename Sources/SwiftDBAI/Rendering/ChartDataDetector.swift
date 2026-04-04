// ChartDataDetector.swift
// SwiftDBAI
//
// Analyzes query results to determine chart eligibility and
// recommends appropriate chart types based on data shape.

import Foundation

/// Detects whether a `DataTable` is suitable for charting and
/// recommends the best chart type based on data shape heuristics.
///
/// The detector examines column types, row counts, and value distributions
/// to produce a `ChartRecommendation` that the rendering layer can use
/// to auto-select an appropriate Swift Charts visualization.
///
/// Usage:
/// ```swift
/// let detector = ChartDataDetector()
/// if let recommendation = detector.detect(table) {
///     switch recommendation.chartType {
///     case .bar:  // render bar chart
///     case .line: // render line chart
///     case .pie:  // render pie chart
///     }
/// }
/// ```
public struct ChartDataDetector: Sendable {

    // MARK: - Chart Types

    /// The type of chart recommended for the data.
    public enum ChartType: String, Sendable, Equatable, CaseIterable {
        /// Vertical bar chart — best for categorical comparisons.
        case bar
        /// Line chart — best for time series or ordered sequences.
        case line
        /// Pie/donut chart — best for proportional breakdowns with few categories.
        case pie
    }

    /// A recommendation for how to chart a `DataTable`.
    public struct ChartRecommendation: Sendable, Equatable {
        /// The recommended chart type.
        public let chartType: ChartType

        /// The column to use for the category axis (x-axis / labels).
        public let categoryColumn: String

        /// The column to use for the value axis (y-axis / sizes).
        public let valueColumn: String

        /// Confidence score from 0.0 (guess) to 1.0 (strong match).
        public let confidence: Double

        /// Human-readable reason for this recommendation.
        public let reason: String

        public init(
            chartType: ChartType,
            categoryColumn: String,
            valueColumn: String,
            confidence: Double,
            reason: String
        ) {
            self.chartType = chartType
            self.categoryColumn = categoryColumn
            self.valueColumn = valueColumn
            self.confidence = confidence
            self.reason = reason
        }
    }

    // MARK: - Configuration

    /// Minimum rows required to consider chart-eligible.
    public let minimumRows: Int

    /// Maximum rows for a pie chart (too many slices becomes unreadable).
    public let maxPieSlices: Int

    /// Maximum rows for any chart before it becomes cluttered.
    public let maximumRows: Int

    // MARK: - Initialization

    /// Creates a detector with configurable thresholds.
    ///
    /// - Parameters:
    ///   - minimumRows: Minimum rows for chart eligibility (default: 2).
    ///   - maxPieSlices: Maximum categories for pie charts (default: 8).
    ///   - maximumRows: Maximum rows for any chart (default: 100).
    public init(
        minimumRows: Int = 2,
        maxPieSlices: Int = 8,
        maximumRows: Int = 100
    ) {
        self.minimumRows = minimumRows
        self.maxPieSlices = maxPieSlices
        self.maximumRows = maximumRows
    }

    // MARK: - Detection

    /// Analyzes a `DataTable` and returns a chart recommendation, or `nil`
    /// if the data is not suitable for charting.
    ///
    /// - Parameter table: The data table to analyze.
    /// - Returns: A recommendation, or `nil` if no chart type fits.
    public func detect(_ table: DataTable) -> ChartRecommendation? {
        // Must have at least 2 columns (category + value) and enough rows
        guard table.columnCount >= 2,
              table.rowCount >= minimumRows,
              table.rowCount <= maximumRows else {
            return nil
        }

        // Find candidate category and value columns
        guard let (categoryCol, valueCol) = findCategoryValuePair(in: table) else {
            return nil
        }

        let chartType = recommendChartType(
            table: table,
            categoryColumn: categoryCol,
            valueColumn: valueCol
        )

        let confidence = computeConfidence(
            table: table,
            categoryColumn: categoryCol,
            valueColumn: valueCol,
            chartType: chartType
        )

        let reason = describeReason(
            chartType: chartType,
            categoryColumn: categoryCol,
            valueColumn: valueCol,
            table: table
        )

        return ChartRecommendation(
            chartType: chartType,
            categoryColumn: categoryCol.name,
            valueColumn: valueCol.name,
            confidence: confidence,
            reason: reason
        )
    }

    /// Returns all viable chart recommendations, ranked by confidence.
    ///
    /// - Parameter table: The data table to analyze.
    /// - Returns: An array of recommendations sorted by confidence (highest first).
    public func allRecommendations(for table: DataTable) -> [ChartRecommendation] {
        guard table.columnCount >= 2,
              table.rowCount >= minimumRows,
              table.rowCount <= maximumRows else {
            return []
        }

        guard let (categoryCol, valueCol) = findCategoryValuePair(in: table) else {
            return []
        }

        return ChartType.allCases.compactMap { chartType in
            guard isViable(chartType, table: table, categoryColumn: categoryCol) else {
                return nil
            }

            let confidence = computeConfidence(
                table: table,
                categoryColumn: categoryCol,
                valueColumn: valueCol,
                chartType: chartType
            )

            let reason = describeReason(
                chartType: chartType,
                categoryColumn: categoryCol,
                valueColumn: valueCol,
                table: table
            )

            return ChartRecommendation(
                chartType: chartType,
                categoryColumn: categoryCol.name,
                valueColumn: valueCol.name,
                confidence: confidence,
                reason: reason
            )
        }
        .sorted { $0.confidence > $1.confidence }
    }

    // MARK: - Private Helpers

    /// Finds the best (category, value) column pair from the table.
    private func findCategoryValuePair(
        in table: DataTable
    ) -> (category: DataTable.Column, value: DataTable.Column)? {
        let numericColumns = table.columns.filter { isNumeric($0) }
        let categoryColumns = table.columns.filter { isCategory($0) }

        // Prefer: first text/category column + first numeric column
        if let cat = categoryColumns.first, let val = numericColumns.first {
            return (cat, val)
        }

        // Fallback: if all columns are numeric, use first as category, second as value
        if numericColumns.count >= 2 {
            return (numericColumns[0], numericColumns[1])
        }

        return nil
    }

    /// Recommends the single best chart type for the data shape.
    private func recommendChartType(
        table: DataTable,
        categoryColumn: DataTable.Column,
        valueColumn: DataTable.Column
    ) -> ChartType {
        // Line: time series or sequential numeric categories (check first — strongest signal)
        if isTimeSeries(categoryColumn, in: table) || isSequential(categoryColumn, in: table) {
            return .line
        }

        // Pie: small number of categories with all-positive values
        // Only when clearly categorical (text labels) and few rows
        if table.rowCount <= maxPieSlices,
           isCategory(categoryColumn),
           isPieCandidate(table: table, valueColumn: valueColumn),
           looksProportional(table: table, valueColumn: valueColumn) {
            return .pie
        }

        // Default: bar chart for categorical comparisons
        return .bar
    }

    /// Checks if a chart type is viable for the given data.
    private func isViable(
        _ chartType: ChartType,
        table: DataTable,
        categoryColumn: DataTable.Column
    ) -> Bool {
        switch chartType {
        case .pie:
            return table.rowCount <= maxPieSlices
        case .line:
            return table.rowCount >= minimumRows
        case .bar:
            return true
        }
    }

    /// Determines if a column holds numeric data.
    private func isNumeric(_ column: DataTable.Column) -> Bool {
        switch column.inferredType {
        case .integer, .real:
            return true
        default:
            return false
        }
    }

    /// Determines if a column holds categorical (label) data.
    private func isCategory(_ column: DataTable.Column) -> Bool {
        switch column.inferredType {
        case .text, .mixed:
            return true
        default:
            return false
        }
    }

    /// Checks if the value column contains all non-negative values,
    /// making it a candidate for pie charts.
    private func isPieCandidate(
        table: DataTable,
        valueColumn: DataTable.Column
    ) -> Bool {
        let values = table.numericValues(forColumn: valueColumn.name)
        guard !values.isEmpty else { return false }
        // All values must be positive for a meaningful pie chart
        return values.allSatisfy { $0 > 0 }
    }

    /// Heuristic: do values look like they represent parts of a whole?
    ///
    /// Checks for aggregate-like column names (count, total, sum, amount, pct, etc.)
    /// or if values sum to a round number suggesting percentages/proportions.
    private func looksProportional(
        table: DataTable,
        valueColumn: DataTable.Column
    ) -> Bool {
        let proportionalNames: Set<String> = ["count", "total", "sum", "amount", "pct",
                                               "percent", "percentage", "share", "proportion",
                                               "quantity", "qty", "num", "number"]
        // Split on common separators and check for exact word matches
        let lowerName = valueColumn.name.lowercased()
        let words = Set(lowerName.split { $0 == "_" || $0 == "-" || $0 == " " }.map(String.init))
        if !words.isDisjoint(with: proportionalNames) {
            return true
        }

        // Check if values sum to ~100 (percentages)
        let values = table.numericValues(forColumn: valueColumn.name)
        let sum = values.reduce(0, +)
        if abs(sum - 100.0) < 1.0 {
            return true
        }

        return false
    }

    /// Heuristic: does the category column look like time-series data?
    ///
    /// Checks for date-like patterns (YYYY, YYYY-MM, YYYY-MM-DD)
    /// or common time-related column names.
    private func isTimeSeries(_ column: DataTable.Column, in table: DataTable) -> Bool {
        let timeNames = ["date", "time", "timestamp", "year", "month", "day",
                         "week", "quarter", "period", "created_at", "updated_at"]
        let lowerName = column.name.lowercased()
        if timeNames.contains(where: { lowerName.contains($0) }) {
            return true
        }

        // Check if text values look like dates
        if column.inferredType == .text {
            let values = table.stringValues(forColumn: column.name)
            let datePattern = #/^\d{4}(-\d{2}){0,2}$/#
            let matchCount = values.prefix(5).filter { (try? datePattern.wholeMatch(in: $0)) != nil }.count
            if matchCount >= 3 {
                return true
            }
        }

        return false
    }

    /// Heuristic: does the category column contain sequential numeric values?
    private func isSequential(_ column: DataTable.Column, in table: DataTable) -> Bool {
        guard isNumeric(column) else { return false }
        let values = table.numericValues(forColumn: column.name)
        guard values.count >= 3 else { return false }

        // Check if values are monotonically increasing
        for i in 1..<values.count {
            if values[i] <= values[i - 1] {
                return false
            }
        }
        return true
    }

    /// Computes a confidence score for a specific chart type + data combination.
    private func computeConfidence(
        table: DataTable,
        categoryColumn: DataTable.Column,
        valueColumn: DataTable.Column,
        chartType: ChartType
    ) -> Double {
        var score = 0.5 // baseline

        // Bonus: clear category/value split (text + numeric)
        if isCategory(categoryColumn) && isNumeric(valueColumn) {
            score += 0.2
        }

        // Bonus: reasonable row count for the chart type
        switch chartType {
        case .bar:
            if table.rowCount >= 2 && table.rowCount <= 20 {
                score += 0.15
            }
        case .line:
            if isTimeSeries(categoryColumn, in: table) {
                score += 0.2
            } else if isSequential(categoryColumn, in: table) {
                score += 0.1
            }
        case .pie:
            if table.rowCount <= maxPieSlices && isPieCandidate(table: table, valueColumn: valueColumn) {
                score += 0.2
            }
            // Penalty: too many slices
            if table.rowCount > 5 {
                score -= 0.1
            }
        }

        // Bonus: no null values in key columns
        let categoryNulls = table.columnValues(named: categoryColumn.name).filter(\.isNull).count
        let valueNulls = table.columnValues(named: valueColumn.name).filter(\.isNull).count
        if categoryNulls == 0 && valueNulls == 0 {
            score += 0.1
        }

        return min(max(score, 0.0), 1.0)
    }

    /// Generates a human-readable reason for the recommendation.
    private func describeReason(
        chartType: ChartType,
        categoryColumn: DataTable.Column,
        valueColumn: DataTable.Column,
        table: DataTable
    ) -> String {
        switch chartType {
        case .bar:
            return "\(table.rowCount) categories comparing \(valueColumn.name) by \(categoryColumn.name)"
        case .line:
            if isTimeSeries(categoryColumn, in: table) {
                return "\(valueColumn.name) over time (\(categoryColumn.name))"
            }
            return "\(valueColumn.name) trend across \(table.rowCount) points"
        case .pie:
            return "Proportional breakdown of \(valueColumn.name) by \(categoryColumn.name)"
        }
    }
}
