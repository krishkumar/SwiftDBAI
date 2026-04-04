// ScrollableDataTableView.swift
// SwiftDBAI
//
// A SwiftUI view that renders a DataTable with horizontal and vertical
// scrolling, styled column headers, and row cells.

import SwiftUI

/// A scrollable table view that renders a `DataTable` with column headers
/// and row cells, supporting both horizontal and vertical scrolling.
///
/// Usage:
/// ```swift
/// ScrollableDataTableView(dataTable: myDataTable)
/// ```
///
/// The view automatically sizes columns based on content, highlights
/// alternating rows for readability, and right-aligns numeric columns.
public struct ScrollableDataTableView: View {
    /// The data table to render.
    public let dataTable: DataTable

    /// Minimum width for each column in points.
    public var minimumColumnWidth: CGFloat

    /// Maximum width for each column in points.
    public var maximumColumnWidth: CGFloat

    /// Whether to show alternating row backgrounds.
    public var showAlternatingRows: Bool

    /// Whether to show the row count footer.
    public var showFooter: Bool

    public init(
        dataTable: DataTable,
        minimumColumnWidth: CGFloat = 80,
        maximumColumnWidth: CGFloat = 250,
        showAlternatingRows: Bool = true,
        showFooter: Bool = true
    ) {
        self.dataTable = dataTable
        self.minimumColumnWidth = minimumColumnWidth
        self.maximumColumnWidth = maximumColumnWidth
        self.showAlternatingRows = showAlternatingRows
        self.showFooter = showFooter
    }

    public var body: some View {
        if dataTable.isEmpty {
            emptyView
        } else {
            tableContent
        }
    }

    // MARK: - Empty State

    @ViewBuilder
    private var emptyView: some View {
        VStack(spacing: 8) {
            Image(systemName: "tablecells")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text("No results")
                .font(.headline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 100)
    }

    // MARK: - Table Content

    @ViewBuilder
    private var tableContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView([.horizontal, .vertical]) {
                LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                    Section {
                        ForEach(dataTable.rows) { row in
                            rowView(row)
                        }
                    } header: {
                        headerRow
                    }
                }
            }

            if showFooter {
                footerView
            }
        }
    }

    // MARK: - Header

    @ViewBuilder
    private var headerRow: some View {
        HStack(spacing: 0) {
            ForEach(dataTable.columns) { column in
                Text(column.name)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .frame(
                        width: columnWidth(for: column),
                        alignment: alignment(for: column)
                    )
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)

                if column.index < dataTable.columnCount - 1 {
                    Divider()
                }
            }
        }
        .background(.bar)
        .overlay(alignment: .bottom) {
            Divider()
        }
    }

    // MARK: - Row

    @ViewBuilder
    private func rowView(_ row: DataTable.Row) -> some View {
        HStack(spacing: 0) {
            ForEach(dataTable.columns) { column in
                cellView(value: row[column.index], column: column)

                if column.index < dataTable.columnCount - 1 {
                    Divider()
                }
            }
        }
        .background(rowBackground(for: row))
        .overlay(alignment: .bottom) {
            Divider()
        }
    }

    // MARK: - Cell

    @ViewBuilder
    private func cellView(value: QueryResult.Value, column: DataTable.Column) -> some View {
        Group {
            switch value {
            case .null:
                Text("NULL")
                    .foregroundStyle(.tertiary)
                    .italic()
            case .blob(let data):
                Text("<\(data.count) bytes>")
                    .foregroundStyle(.secondary)
            default:
                Text(value.stringValue)
                    .foregroundStyle(.primary)
            }
        }
        .font(.caption)
        .lineLimit(2)
        .frame(
            width: columnWidth(for: column),
            alignment: alignment(for: column)
        )
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
    }

    // MARK: - Footer

    @ViewBuilder
    private var footerView: some View {
        HStack {
            Text("\(dataTable.rowCount) row\(dataTable.rowCount == 1 ? "" : "s")")
                .font(.caption2)
                .foregroundStyle(.secondary)
            Spacer()
            if dataTable.executionTime > 0 {
                Text(String(format: "%.1f ms", dataTable.executionTime * 1000))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(.bar)
    }

    // MARK: - Layout Helpers

    /// Determines column width based on the column name length and type.
    private func columnWidth(for column: DataTable.Column) -> CGFloat {
        // Estimate based on header text length
        let headerWidth = CGFloat(column.name.count) * 8 + 16

        // Sample some row values to estimate content width
        let sampleRows = dataTable.rows.prefix(20)
        let maxContentWidth = sampleRows.reduce(CGFloat(0)) { maxWidth, row in
            let value = row[column.index]
            let textLength = CGFloat(value.stringValue.count) * 7
            return max(maxWidth, textLength)
        }

        let estimatedWidth = max(headerWidth, maxContentWidth) + 16
        return min(max(estimatedWidth, minimumColumnWidth), maximumColumnWidth)
    }

    /// Returns the alignment for a column based on its inferred type.
    private func alignment(for column: DataTable.Column) -> Alignment {
        switch column.inferredType {
        case .integer, .real:
            return .trailing
        default:
            return .leading
        }
    }

    /// Returns the background color for alternating rows.
    @ViewBuilder
    private func rowBackground(for row: DataTable.Row) -> some View {
        if showAlternatingRows && row.id.isMultiple(of: 2) {
            Color.clear
        } else if showAlternatingRows {
            Color.primary.opacity(0.03)
        } else {
            Color.clear
        }
    }
}

// MARK: - Preview Support

#if DEBUG
@available(iOS 17.0, macOS 14.0, visionOS 1.0, *)
#Preview("Data Table") {
    let columns: [DataTable.Column] = [
        .init(name: "id", index: 0, inferredType: .integer),
        .init(name: "name", index: 1, inferredType: .text),
        .init(name: "score", index: 2, inferredType: .real),
    ]
    let rows: [DataTable.Row] = (0..<25).map { i in
        DataTable.Row(
            id: i,
            values: [
                .integer(Int64(i + 1)),
                .text("Item \(i + 1)"),
                .real(Double.random(in: 1.0...100.0)),
            ],
            columnNames: ["id", "name", "score"]
        )
    }
    let table = DataTable(columns: columns, rows: rows, sql: "SELECT * FROM items", executionTime: 0.023)

    ScrollableDataTableView(dataTable: table)
        .frame(height: 400)
        .padding()
}

@available(iOS 17.0, macOS 14.0, visionOS 1.0, *)
#Preview("Empty Table") {
    let table = DataTable(columns: [], rows: [], sql: "", executionTime: 0)
    ScrollableDataTableView(dataTable: table)
        .frame(height: 200)
        .padding()
}
#endif
