// ChartResultView.swift
// SwiftDBAI
//
// Auto-selecting chart view that uses ChartDataDetector to pick the
// best chart type for a given DataTable.

import SwiftUI
import Charts

/// A chart view that automatically selects the best chart type for a `DataTable`.
///
/// Uses `ChartDataDetector` to analyze the data shape and renders the
/// appropriate chart (bar, line, or pie). If the data isn't suitable for
/// charting, the view renders nothing.
///
/// Usage:
/// ```swift
/// ChartResultView(dataTable: myTable)
/// ```
@available(iOS 17.0, macOS 14.0, visionOS 1.0, *)
public struct ChartResultView: View {

    /// The data table to chart.
    public let dataTable: DataTable

    /// Optional override: force a specific chart type.
    public var chartType: ChartDataDetector.ChartType?

    /// The detector used to analyze the data.
    private let detector: ChartDataDetector

    public init(
        dataTable: DataTable,
        chartType: ChartDataDetector.ChartType? = nil,
        detector: ChartDataDetector = ChartDataDetector()
    ) {
        self.dataTable = dataTable
        self.chartType = chartType
        self.detector = detector
    }

    public var body: some View {
        if let recommendation = resolvedRecommendation {
            VStack(alignment: .leading, spacing: 4) {
                chartView(for: recommendation)

                Text(recommendation.reason)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    // MARK: - Chart Selection

    @ViewBuilder
    private func chartView(
        for recommendation: ChartDataDetector.ChartRecommendation
    ) -> some View {
        switch recommendation.chartType {
        case .bar:
            BarChartView(
                dataTable: dataTable,
                categoryColumn: recommendation.categoryColumn,
                valueColumn: recommendation.valueColumn
            )
        case .line:
            LineChartView(
                dataTable: dataTable,
                categoryColumn: recommendation.categoryColumn,
                valueColumn: recommendation.valueColumn
            )
        case .pie:
            PieChartView(
                dataTable: dataTable,
                categoryColumn: recommendation.categoryColumn,
                valueColumn: recommendation.valueColumn
            )
        }
    }

    // MARK: - Resolution

    /// Resolves the chart recommendation, using the override type if provided.
    private var resolvedRecommendation: ChartDataDetector.ChartRecommendation? {
        if let override = chartType {
            // Use forced chart type — still need column pair from detector
            let all = detector.allRecommendations(for: dataTable)
            // Try to find recommendation for the forced type
            if let match = all.first(where: { $0.chartType == override }) {
                return match
            }
            // Fallback: use first recommendation and override its type
            if let first = all.first {
                return ChartDataDetector.ChartRecommendation(
                    chartType: override,
                    categoryColumn: first.categoryColumn,
                    valueColumn: first.valueColumn,
                    confidence: first.confidence * 0.8,
                    reason: first.reason
                )
            }
            return nil
        }

        // Auto-detect best chart type
        return detector.detect(dataTable)
    }
}

// MARK: - Preview

#if DEBUG
@available(iOS 17.0, macOS 14.0, visionOS 1.0, *)
#Preview("Auto Chart — Bar") {
    let columns: [DataTable.Column] = [
        .init(name: "city", index: 0, inferredType: .text),
        .init(name: "population", index: 1, inferredType: .integer),
    ]
    let cities = ["NYC", "LA", "Chicago", "Houston", "Phoenix"]
    let pops: [Int64] = [8_336_817, 3_979_576, 2_693_976, 2_320_268, 1_680_992]
    let rows: [DataTable.Row] = cities.enumerated().map { i, city in
        DataTable.Row(
            id: i,
            values: [.text(city), .integer(pops[i])],
            columnNames: ["city", "population"]
        )
    }
    let table = DataTable(columns: columns, rows: rows)

    ChartResultView(dataTable: table)
        .padding()
        .frame(height: 300)
}
#endif
