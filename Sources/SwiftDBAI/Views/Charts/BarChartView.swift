// BarChartView.swift
// SwiftDBAI
//
// A SwiftUI bar chart that renders DataTable values using Swift Charts.
// Best for categorical comparisons (e.g., sales by region, counts by status).

import SwiftUI
import Charts

/// A bar chart view that renders a `DataTable` column pair using Swift Charts.
///
/// Displays vertical bars with category labels on the x-axis and numeric
/// values on the y-axis. Automatically colors bars using the accent gradient
/// and supports scrolling when many categories are present.
///
/// Usage:
/// ```swift
/// BarChartView(
///     dataTable: table,
///     categoryColumn: "department",
///     valueColumn: "total_sales"
/// )
/// ```
@available(iOS 17.0, macOS 14.0, visionOS 1.0, *)
public struct BarChartView: View {

    /// The data to chart.
    public let dataTable: DataTable

    /// Column name for category labels (x-axis).
    public let categoryColumn: String

    /// Column name for numeric values (y-axis).
    public let valueColumn: String

    /// Optional chart title.
    public var title: String?

    /// Maximum number of bars to display before truncating.
    public var maxBars: Int

    public init(
        dataTable: DataTable,
        categoryColumn: String,
        valueColumn: String,
        title: String? = nil,
        maxBars: Int = 30
    ) {
        self.dataTable = dataTable
        self.categoryColumn = categoryColumn
        self.valueColumn = valueColumn
        self.title = title
        self.maxBars = maxBars
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let title {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            if chartData.isEmpty {
                emptyChartView
            } else {
                chartContent
            }
        }
    }

    // MARK: - Chart Content

    @ViewBuilder
    private var chartContent: some View {
        Chart(chartData, id: \.label) { item in
            BarMark(
                x: .value(categoryColumn, item.label),
                y: .value(valueColumn, item.value)
            )
            .foregroundStyle(
                .linearGradient(
                    colors: [.accentColor, .accentColor.opacity(0.7)],
                    startPoint: .bottom,
                    endPoint: .top
                )
            )
            .cornerRadius(4)
        }
        .chartXAxis {
            AxisMarks(values: .automatic) { _ in
                AxisValueLabel()
                    .font(.caption2)
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading) { _ in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [4, 4]))
                    .foregroundStyle(.secondary.opacity(0.3))
                AxisValueLabel()
                    .font(.caption2)
            }
        }
        .frame(minHeight: 200)

        if isTruncated {
            truncationNotice
        }
    }

    // MARK: - Empty State

    @ViewBuilder
    private var emptyChartView: some View {
        VStack(spacing: 8) {
            Image(systemName: "chart.bar")
                .font(.title2)
                .foregroundStyle(.secondary)
            Text("No chartable data")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 100)
    }

    // MARK: - Truncation Notice

    @ViewBuilder
    private var truncationNotice: some View {
        Text("Showing \(maxBars) of \(dataTable.rowCount) categories")
            .font(.caption2)
            .foregroundStyle(.secondary)
    }

    // MARK: - Data Extraction

    private var isTruncated: Bool {
        dataTable.rowCount > maxBars
    }

    private var chartData: [ChartDataPoint] {
        let labels = dataTable.stringValues(forColumn: categoryColumn)
        let values = dataTable.numericValues(forColumn: valueColumn)

        let count = min(labels.count, values.count, maxBars)
        guard count > 0 else { return [] }

        return (0..<count).map { i in
            ChartDataPoint(label: labels[i], value: values[i])
        }
    }
}

// MARK: - Preview

#if DEBUG
@available(iOS 17.0, macOS 14.0, visionOS 1.0, *)
#Preview("Bar Chart") {
    let columns: [DataTable.Column] = [
        .init(name: "department", index: 0, inferredType: .text),
        .init(name: "revenue", index: 1, inferredType: .real),
    ]
    let departments = ["Engineering", "Sales", "Marketing", "Support", "Design"]
    let rows: [DataTable.Row] = departments.enumerated().map { i, dept in
        DataTable.Row(
            id: i,
            values: [.text(dept), .real(Double.random(in: 50_000...200_000))],
            columnNames: ["department", "revenue"]
        )
    }
    let table = DataTable(columns: columns, rows: rows)

    BarChartView(
        dataTable: table,
        categoryColumn: "department",
        valueColumn: "revenue",
        title: "Revenue by Department"
    )
    .padding()
    .frame(height: 300)
}
#endif
