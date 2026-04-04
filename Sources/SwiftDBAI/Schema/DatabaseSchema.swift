// DatabaseSchema.swift
// SwiftDBAI
//
// Auto-introspected SQLite schema model types.

import Foundation

/// Complete schema representation of an SQLite database.
public struct DatabaseSchema: Sendable, Equatable {
    /// All tables in the database, keyed by table name.
    public let tables: [String: TableSchema]

    /// Ordered table names (preserves discovery order).
    public let tableNames: [String]

    /// Returns a compact text description suitable for LLM system prompts.
    public var schemaDescription: String {
        var lines: [String] = []
        for name in tableNames {
            guard let table = tables[name] else { continue }
            lines.append(table.descriptionForLLM)
        }
        return lines.joined(separator: "\n\n")
    }

    /// Returns a description suitable for LLM system prompts.
    /// Alias for `schemaDescription` for API compatibility.
    public func describeForLLM() -> String {
        schemaDescription
    }

    public init(tables: [String: TableSchema], tableNames: [String]) {
        self.tables = tables
        self.tableNames = tableNames
    }
}

/// Schema for a single SQLite table.
public struct TableSchema: Sendable, Equatable {
    public let name: String
    public let columns: [ColumnSchema]
    public let primaryKey: [String]
    public let foreignKeys: [ForeignKeySchema]
    public let indexes: [IndexSchema]

    /// Text description for embedding in LLM prompts.
    public var descriptionForLLM: String {
        var parts: [String] = []
        let colDefs = columns.map { col in
            var def = "  \(col.name) \(col.type)"
            if col.isPrimaryKey { def += " PRIMARY KEY" }
            if col.isNotNull { def += " NOT NULL" }
            if let defaultValue = col.defaultValue { def += " DEFAULT \(defaultValue)" }
            return def
        }
        parts.append("TABLE \(name) (\n\(colDefs.joined(separator: ",\n"))\n)")

        if !foreignKeys.isEmpty {
            let fkDescs = foreignKeys.map {
                "  FOREIGN KEY (\($0.fromColumn)) REFERENCES \($0.toTable)(\($0.toColumn))"
            }
            parts.append("FOREIGN KEYS:\n\(fkDescs.joined(separator: "\n"))")
        }

        if !indexes.isEmpty {
            let idxDescs = indexes.map {
                "  INDEX \($0.name) ON (\($0.columns.joined(separator: ", ")))\($0.isUnique ? " UNIQUE" : "")"
            }
            parts.append("INDEXES:\n\(idxDescs.joined(separator: "\n"))")
        }

        return parts.joined(separator: "\n")
    }

    public init(
        name: String,
        columns: [ColumnSchema],
        primaryKey: [String],
        foreignKeys: [ForeignKeySchema],
        indexes: [IndexSchema]
    ) {
        self.name = name
        self.columns = columns
        self.primaryKey = primaryKey
        self.foreignKeys = foreignKeys
        self.indexes = indexes
    }
}

/// Schema for a single column.
public struct ColumnSchema: Sendable, Equatable {
    /// Column position (0-based).
    public let cid: Int
    /// Column name.
    public let name: String
    /// Declared SQLite type (e.g. "TEXT", "INTEGER", "REAL", "BLOB").
    public let type: String
    /// Whether the column has a NOT NULL constraint.
    public let isNotNull: Bool
    /// Default value expression, if any.
    public let defaultValue: String?
    /// Whether this column is part of the primary key.
    public let isPrimaryKey: Bool

    public init(
        cid: Int,
        name: String,
        type: String,
        isNotNull: Bool,
        defaultValue: String?,
        isPrimaryKey: Bool
    ) {
        self.cid = cid
        self.name = name
        self.type = type
        self.isNotNull = isNotNull
        self.defaultValue = defaultValue
        self.isPrimaryKey = isPrimaryKey
    }
}

/// Schema for a foreign key relationship.
public struct ForeignKeySchema: Sendable, Equatable {
    /// Column in the source table.
    public let fromColumn: String
    /// Referenced table name.
    public let toTable: String
    /// Referenced column name.
    public let toColumn: String
    /// ON UPDATE action (e.g. "CASCADE", "NO ACTION").
    public let onUpdate: String
    /// ON DELETE action.
    public let onDelete: String

    public init(
        fromColumn: String,
        toTable: String,
        toColumn: String,
        onUpdate: String,
        onDelete: String
    ) {
        self.fromColumn = fromColumn
        self.toTable = toTable
        self.toColumn = toColumn
        self.onUpdate = onUpdate
        self.onDelete = onDelete
    }
}

/// Schema for a database index.
public struct IndexSchema: Sendable, Equatable {
    /// Index name.
    public let name: String
    /// Whether the index enforces uniqueness.
    public let isUnique: Bool
    /// Columns included in the index, in order.
    public let columns: [String]

    public init(name: String, isUnique: Bool, columns: [String]) {
        self.name = name
        self.isUnique = isUnique
        self.columns = columns
    }
}
