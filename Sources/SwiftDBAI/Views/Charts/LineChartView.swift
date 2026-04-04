// LineChartView.swift
// SwiftDBAI
//
// A SwiftUI line chart that renders DataTable values using Swift Charts.
// Best for time series or sequential data (e.g., revenue over months).

import SwiftUI
import Charts

/// A line chart view that renders a `DataTable` column pair using Swift Charts.
///
/// Displays a connected line with optional area fill, point markers,
/// and smooth interpolation. Best suited for time series or sequential data.
///
/// Usage:
/// ```swift
/// LineChartView(
///     dataTable: table,
///     categoryColumn: "month",
///     valueColumn: "revenue"
/// )
/// ```
@available(iOS 17.0, macOS 14.0, visionOS 1.0, *)
public struct LineChartView: View {

    /// The data to chart.
    public let dataTable: DataTable

    /// Column name for category/time labels (x-axis).
    public let categoryColumn: String

    /// Column name for numeric values (y-axis).
    public let valueColumn: String

    /// Optional chart title.
    public var title: String?

    /// Whether to show an area fill below the line.
    public var showAreaFill: Bool

    /// Whether to show point markers at each data point.
    public var showPoints: Bool

    /// Maximum data points to display.
    public var maxPoints: Int

    public init(
        dataTable: DataTable,
        categoryColumn: String,
        valueColumn: String,
        title: String? = nil,
        showAreaFill: Bool = true,
        showPoints: Bool = true,
        maxPoints: Int = 100
    ) {
        self.dataTable = dataTable
        self.categoryColumn = categoryColumn
        self.valueColumn = valueColumn
        self.title = title
        self.showAreaFill = showAreaFill
        self.showPoints = showPoints
        self.maxPoints = maxPoints
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
            LineMark(
                x: .value(categoryColumn, item.label),
                y: .value(valueColumn, item.value)
            )
            .foregroundStyle(Color.accentColor)
            .lineStyle(StrokeStyle(lineWidth: 2))
            .interpolationMethod(.catmullRom)

            if showAreaFill {
                AreaMark(
                    x: .value(categoryColumn, item.label),
                    y: .value(valueColumn, item.value)
                )
                .foregroundStyle(
                    .linearGradient(
                        colors: [
                            Color.accentColor.opacity(0.2),
                            Color.accentColor.opacity(0.02),
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .interpolationMethod(.catmullRom)
            }

            if showPoints {
                PointMark(
                    x: .value(categoryColumn, item.label),
                    y: .value(valueColumn, item.value)
                )
                .foregroundStyle(Color.accentColor)
                .symbolSize(30)
            }
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
            Text("Showing \(maxPoints) of \(dataTable.rowCount) data points")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Empty State

    @ViewBuilder
    private var emptyChartView: some View {
        VStack(spacing: 8) {
            Image(systemName: "chart.xyaxis.line")
                .font(.title2)
                .foregroundStyle(.secondary)
            Text("No chartable data")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 100)
    }

    // MARK: - Data Extraction

    private var isTruncated: Bool {
        dataTable.rowCount > maxPoints
    }

    private var chartData: [ChartDataPoint] {
        let labels = dataTable.stringValues(forColumn: categoryColumn)
        let values = dataTable.numericValues(forColumn: valueColumn)

        let count = min(labels.count, values.count, maxPoints)
        guard count > 0 else { return [] }

        return (0..<count).map { i in
            ChartDataPoint(label: labels[i], value: values[i])
        }
    }
}

// MARK: - Preview

#if DEBUG
@available(iOS 17.0, macOS 14.0, visionOS 1.0, *)
#Preview("Line Chart") {
    let columns: [DataTable.Column] = [
        .init(name: "month", index: 0, inferredType: .text),
        .init(name: "revenue", index: 1, inferredType: .real),
    ]
    let months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun"]
    let rows: [DataTable.Row] = months.enumerated().map { i, month in
        DataTable.Row(
            id: i,
            values: [.text(month), .real(Double(i + 1) * 15_000 + Double.random(in: -3000...3000))],
            columnNames: ["month", "revenue"]
        )
    }
    let table = DataTable(columns: columns, rows: rows)

    LineChartView(
        dataTable: table,
        categoryColumn: "month",
        valueColumn: "revenue",
        title: "Monthly Revenue"
    )
    .padding()
    .frame(height: 300)
}
#endif
