// DataTable.swift
// SwiftDBAI
//
// Structured table representation for rendering query results
// in SwiftUI table views and charts.

import Foundation

/// A structured, row-column table built from a `QueryResult`.
///
/// `DataTable` provides indexed access to rows and columns, typed column
/// metadata, and convenience methods for extracting data suitable for
/// SwiftUI `Table` views and Swift Charts.
///
/// Usage:
/// ```swift
/// let table = DataTable(queryResult)
/// print(table.columnCount) // 3
/// print(table[row: 0, column: 1]) // .text("Alice")
/// ```
public struct DataTable: Sendable, Equatable {

    // MARK: - Column Metadata

    /// Metadata for a single column in the data table.
    public struct Column: Sendable, Equatable, Identifiable {
        /// Stable identifier for the column (same as `name`).
        public var id: String { name }

        /// Column name from the query result set.
        public let name: String

        /// Index of this column in the table (0-based).
        public let index: Int

        /// Inferred data type based on the values in this column.
        public let inferredType: InferredType

        public init(name: String, index: Int, inferredType: InferredType) {
            self.name = name
            self.index = index
            self.inferredType = inferredType
        }
    }

    /// The inferred data type for a column, determined by inspecting its values.
    public enum InferredType: Sendable, Equatable {
        /// All non-null values are integers.
        case integer
        /// All non-null values are numeric (mix of integer and real).
        case real
        /// All non-null values are text.
        case text
        /// Values contain blob data.
        case blob
        /// Column contains only null values or is empty.
        case null
        /// Values are a mix of incompatible types.
        case mixed
    }

    // MARK: - Row Type

    /// A single row in the data table, providing indexed and named access.
    public struct Row: Sendable, Equatable, Identifiable {
        /// Row index (0-based), used as stable identity.
        public let id: Int

        /// Values in column order.
        public let values: [QueryResult.Value]

        /// Column names for named access.
        private let columnNames: [String]

        public init(id: Int, values: [QueryResult.Value], columnNames: [String]) {
            self.id = id
            self.values = values
            self.columnNames = columnNames
        }

        /// Access a value by column index.
        public subscript(columnIndex: Int) -> QueryResult.Value {
            values[columnIndex]
        }

        /// Access a value by column name. Returns `.null` if the column doesn't exist.
        public subscript(columnName: String) -> QueryResult.Value {
            guard let idx = columnNames.firstIndex(of: columnName) else {
                return .null
            }
            return values[idx]
        }
    }

    // MARK: - Properties

    /// Column metadata in order.
    public let columns: [Column]

    /// All rows in order.
    public let rows: [Row]

    /// The SQL that produced this table.
    public let sql: String

    /// Execution time of the underlying query.
    public let executionTime: TimeInterval

    /// Number of columns.
    public var columnCount: Int { columns.count }

    /// Number of rows.
    public var rowCount: Int { rows.count }

    /// Whether the table has no rows.
    public var isEmpty: Bool { rows.isEmpty }

    /// Column names in order.
    public var columnNames: [String] { columns.map(\.name) }

    // MARK: - Initialization

    /// Creates a `DataTable` from a `QueryResult`.
    ///
    /// Converts the dictionary-based row representation into an indexed
    /// array representation and infers column types from the data.
    ///
    /// - Parameter queryResult: The raw query result to convert.
    public init(_ queryResult: QueryResult) {
        let colNames = queryResult.columns

        // Build indexed rows
        let indexedRows: [Row] = queryResult.rows.enumerated().map { idx, rowDict in
            let values = colNames.map { col in
                rowDict[col] ?? .null
            }
            return Row(id: idx, values: values, columnNames: colNames)
        }

        // Infer column types
        let inferredColumns: [Column] = colNames.enumerated().map { colIdx, name in
            let type = Self.inferType(
                from: indexedRows.map { $0.values[colIdx] }
            )
            return Column(name: name, index: colIdx, inferredType: type)
        }

        self.columns = inferredColumns
        self.rows = indexedRows
        self.sql = queryResult.sql
        self.executionTime = queryResult.executionTime
    }

    /// Creates a `DataTable` directly from components (useful for testing).
    public init(
        columns: [Column],
        rows: [Row],
        sql: String = "",
        executionTime: TimeInterval = 0
    ) {
        self.columns = columns
        self.rows = rows
        self.sql = sql
        self.executionTime = executionTime
    }

    // MARK: - Subscript Access

    /// Access a cell by row and column index.
    public subscript(row rowIndex: Int, column columnIndex: Int) -> QueryResult.Value {
        rows[rowIndex].values[columnIndex]
    }

    /// Access a cell by row index and column name.
    public subscript(row rowIndex: Int, column columnName: String) -> QueryResult.Value {
        rows[rowIndex][columnName]
    }

    // MARK: - Column Data Extraction

    /// Returns all values for a column by index, in row order.
    public func columnValues(at index: Int) -> [QueryResult.Value] {
        rows.map { $0.values[index] }
    }

    /// Returns all values for a column by name, in row order.
    public func columnValues(named name: String) -> [QueryResult.Value] {
        guard let col = columns.first(where: { $0.name == name }) else {
            return []
        }
        return columnValues(at: col.index)
    }

    /// Returns all non-null `Double` values for a column (useful for charting).
    public func numericValues(forColumn name: String) -> [Double] {
        columnValues(named: name).compactMap(\.doubleValue)
    }

    /// Returns all non-null `String` values for a column (useful for labels).
    public func stringValues(forColumn name: String) -> [String] {
        columnValues(named: name).compactMap { value in
            if case .null = value { return nil }
            return value.stringValue
        }
    }

    // MARK: - Type Inference

    /// Infers the predominant type from an array of values.
    static func inferType(from values: [QueryResult.Value]) -> InferredType {
        var hasInteger = false
        var hasReal = false
        var hasText = false
        var hasBlob = false
        var hasNonNull = false

        for value in values {
            switch value {
            case .integer:
                hasInteger = true
                hasNonNull = true
            case .real:
                hasReal = true
                hasNonNull = true
            case .text:
                hasText = true
                hasNonNull = true
            case .blob:
                hasBlob = true
                hasNonNull = true
            case .null:
                break
            }
        }

        guard hasNonNull else { return .null }

        // Count how many distinct types are present
        let typeCount = [hasInteger, hasReal, hasText, hasBlob].filter { $0 }.count

        if typeCount == 1 {
            if hasInteger { return .integer }
            if hasReal { return .real }
            if hasText { return .text }
            if hasBlob { return .blob }
        }

        // Integer + real → treat as real (numeric promotion)
        if typeCount == 2, hasInteger, hasReal {
            return .real
        }

        return .mixed
    }
}
