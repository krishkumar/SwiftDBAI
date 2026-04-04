// PieChartView.swift
// SwiftDBAI
//
// A SwiftUI pie/donut chart that renders DataTable values using Swift Charts.
// Best for proportional breakdowns with few categories (e.g., market share).

import SwiftUI
import Charts

/// A pie chart view that renders a `DataTable` column pair using Swift Charts.
///
/// Displays proportional slices with category labels. Each slice is
/// automatically colored from a curated palette and sized relative to
/// its proportion of the total. Best suited for data with few categories
/// (≤ 8) where all values are positive.
///
/// Usage:
/// ```swift
/// PieChartView(
///     dataTable: table,
///     categoryColumn: "status",
///     valueColumn: "count"
/// )
/// ```
@available(iOS 17.0, macOS 14.0, visionOS 1.0, *)
public struct PieChartView: View {

    /// The data to chart.
    public let dataTable: DataTable

    /// Column name for category labels (slice labels).
    public let categoryColumn: String

    /// Column name for numeric values (slice sizes).
    public let valueColumn: String

    /// Optional chart title.
    public var title: String?

    /// Inner radius ratio for donut style (0 = full pie, >0 = donut).
    public var innerRadiusRatio: CGFloat

    /// Maximum number of slices before grouping remaining into "Other".
    public var maxSlices: Int

    public init(
        dataTable: DataTable,
        categoryColumn: String,
        valueColumn: String,
        title: String? = nil,
        innerRadiusRatio: CGFloat = 0.4,
        maxSlices: Int = 8
    ) {
        self.dataTable = dataTable
        self.categoryColumn = categoryColumn
        self.valueColumn = valueColumn
        self.title = title
        self.innerRadiusRatio = innerRadiusRatio
        self.maxSlices = maxSlices
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
                HStack(alignment: .center, spacing: 16) {
                    chartContent
                    legendView
                }
            }
        }
    }

    // MARK: - Chart Content

    @ViewBuilder
    private var chartContent: some View {
        Chart(chartData, id: \.label) { item in
            SectorMark(
                angle: .value(valueColumn, item.value),
                innerRadius: .ratio(innerRadiusRatio),
                angularInset: 1.5
            )
            .foregroundStyle(by: .value(categoryColumn, item.label))
            .cornerRadius(3)
        }
        .chartForegroundStyleScale(
            domain: chartData.map(\.label),
            range: sliceColors
        )
        .chartLegend(.hidden)
        .frame(minWidth: 150, minHeight: 150)
        .aspectRatio(1, contentMode: .fit)
    }

    // MARK: - Legend

    @ViewBuilder
    private var legendView: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(chartData.enumerated()), id: \.element.label) { index, item in
                HStack(spacing: 8) {
                    Circle()
                        .fill(sliceColors[index % sliceColors.count])
                        .frame(width: 8, height: 8)

                    Text(item.label)
                        .font(.caption)
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    Spacer()

                    Text(percentageText(for: item.value))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
        }
    }

    // MARK: - Empty State

    @ViewBuilder
    private var emptyChartView: some View {
        VStack(spacing: 8) {
            Image(systemName: "chart.pie")
                .font(.title2)
                .foregroundStyle(.secondary)
            Text("No chartable data")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 100)
    }

    // MARK: - Colors

    /// Curated color palette for pie slices.
    private var sliceColors: [Color] {
        [
            .blue,
            .green,
            .orange,
            .purple,
            .pink,
            .cyan,
            .yellow,
            .indigo,
            .mint,
            .teal,
        ]
    }

    // MARK: - Helpers

    private var total: Double {
        chartData.reduce(0) { $0 + $1.value }
    }

    private func percentageText(for value: Double) -> String {
        guard total > 0 else { return "0%" }
        let pct = (value / total) * 100
        if pct >= 10 {
            return String(format: "%.0f%%", pct)
        }
        return String(format: "%.1f%%", pct)
    }

    // MARK: - Data Extraction

    private var chartData: [ChartDataPoint] {
        let labels = dataTable.stringValues(forColumn: categoryColumn)
        let values = dataTable.numericValues(forColumn: valueColumn)

        let count = min(labels.count, values.count)
        guard count > 0 else { return [] }

        // Build all points, sorted by value descending
        var points = (0..<count).map { i in
            ChartDataPoint(label: labels[i], value: values[i])
        }
        .filter { $0.value > 0 }
        .sorted { $0.value > $1.value }

        // Group excess slices into "Other"
        if points.count > maxSlices {
            let kept = Array(points.prefix(maxSlices - 1))
            let otherValue = points.dropFirst(maxSlices - 1).reduce(0) { $0 + $1.value }
            points = kept + [ChartDataPoint(label: "Other", value: otherValue)]
        }

        return points
    }
}

// MARK: - Preview

#if DEBUG
@available(iOS 17.0, macOS 14.0, visionOS 1.0, *)
#Preview("Pie Chart") {
    let columns: [DataTable.Column] = [
        .init(name: "status", index: 0, inferredType: .text),
        .init(name: "count", index: 1, inferredType: .integer),
    ]
    let statuses = ["Active", "Inactive", "Pending", "Archived"]
    let counts: [Int64] = [45, 20, 15, 10]
    let rows: [DataTable.Row] = statuses.enumerated().map { i, status in
        DataTable.Row(
            id: i,
            values: [.text(status), .integer(counts[i])],
            columnNames: ["status", "count"]
        )
    }
    let table = DataTable(columns: columns, rows: rows)

    PieChartView(
        dataTable: table,
        categoryColumn: "status",
        valueColumn: "count",
        title: "Users by Status"
    )
    .padding()
    .frame(height: 250)
}
#endif
