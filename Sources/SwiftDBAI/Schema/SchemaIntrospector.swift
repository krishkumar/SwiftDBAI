// SchemaIntrospector.swift
// SwiftDBAI
//
// Auto-introspects SQLite database schema using GRDB.

import GRDB

/// Introspects an SQLite database schema by querying sqlite_master and PRAGMA statements.
///
/// Usage:
/// ```swift
/// let dbPool = try DatabasePool(path: "path/to/db.sqlite")
/// let schema = try await SchemaIntrospector.introspect(database: dbPool)
/// print(schema.schemaDescription)
/// ```
public struct SchemaIntrospector: Sendable {

    // MARK: - Public API

    /// Introspects the full schema of the given database.
    ///
    /// Discovers all user tables (excluding sqlite_ internal tables),
    /// their columns, primary keys, foreign keys, and indexes.
    ///
    /// - Parameter database: A GRDB `DatabaseReader` (DatabasePool or DatabaseQueue).
    /// - Returns: A complete `DatabaseSchema` representation.
    public static func introspect(database: any DatabaseReader) async throws -> DatabaseSchema {
        try await database.read { db in
            try introspect(db: db)
        }
    }

    /// Synchronous introspection within an existing database access context.
    ///
    /// - Parameter db: A GRDB `Database` instance from within a read/write block.
    /// - Returns: A complete `DatabaseSchema` representation.
    public static func introspect(db: Database) throws -> DatabaseSchema {
        let tableNames = try fetchTableNames(db: db)
        var tables: [String: TableSchema] = [:]

        for tableName in tableNames {
            let columns = try fetchColumns(db: db, table: tableName)
            let primaryKey = try fetchPrimaryKey(db: db, table: tableName)
            let foreignKeys = try fetchForeignKeys(db: db, table: tableName)
            let indexes = try fetchIndexes(db: db, table: tableName)

            // Mark columns that are part of the primary key
            let pkSet = Set(primaryKey)
            let annotatedColumns = columns.map { col in
                ColumnSchema(
                    cid: col.cid,
                    name: col.name,
                    type: col.type,
                    isNotNull: col.isNotNull,
                    defaultValue: col.defaultValue,
                    isPrimaryKey: pkSet.contains(col.name)
                )
            }

            tables[tableName] = TableSchema(
                name: tableName,
                columns: annotatedColumns,
                primaryKey: primaryKey,
                foreignKeys: foreignKeys,
                indexes: indexes
            )
        }

        return DatabaseSchema(tables: tables, tableNames: tableNames)
    }

    // MARK: - Private Helpers

    /// Fetches all user table names from sqlite_master.
    private static func fetchTableNames(db: Database) throws -> [String] {
        let sql = """
            SELECT name FROM sqlite_master
            WHERE type = 'table'
            AND name NOT LIKE 'sqlite_%'
            ORDER BY name
            """
        return try String.fetchAll(db, sql: sql)
    }

    /// Fetches column metadata for a table using PRAGMA table_info.
    private static func fetchColumns(db: Database, table: String) throws -> [ColumnSchema] {
        let sql = "PRAGMA table_info(\(table.quotedDatabaseIdentifier))"
        let rows = try Row.fetchAll(db, sql: sql)
        return rows.map { row in
            ColumnSchema(
                cid: row["cid"],
                name: row["name"],
                type: (row["type"] as String?) ?? "",
                isNotNull: row["notnull"] == 1,
                defaultValue: row["dflt_value"],
                isPrimaryKey: row["pk"] != 0
            )
        }
    }

    /// Fetches primary key columns for a table.
    private static func fetchPrimaryKey(db: Database, table: String) throws -> [String] {
        let sql = "PRAGMA table_info(\(table.quotedDatabaseIdentifier))"
        let rows = try Row.fetchAll(db, sql: sql)
        return rows
            .filter { ($0["pk"] as Int) > 0 }
            .sorted { ($0["pk"] as Int) < ($1["pk"] as Int) }
            .map { $0["name"] }
    }

    /// Fetches foreign key relationships for a table.
    private static func fetchForeignKeys(db: Database, table: String) throws -> [ForeignKeySchema] {
        let sql = "PRAGMA foreign_key_list(\(table.quotedDatabaseIdentifier))"
        let rows = try Row.fetchAll(db, sql: sql)
        return rows.map { row in
            ForeignKeySchema(
                fromColumn: row["from"],
                toTable: row["table"],
                toColumn: row["to"],
                onUpdate: row["on_update"] ?? "NO ACTION",
                onDelete: row["on_delete"] ?? "NO ACTION"
            )
        }
    }

    /// Fetches indexes and their columns for a table.
    private static func fetchIndexes(db: Database, table: String) throws -> [IndexSchema] {
        let indexListSQL = "PRAGMA index_list(\(table.quotedDatabaseIdentifier))"
        let indexRows = try Row.fetchAll(db, sql: indexListSQL)

        var indexes: [IndexSchema] = []
        for indexRow in indexRows {
            let indexName: String = indexRow["name"]
            let isUnique: Bool = indexRow["unique"] == 1

            // Skip auto-generated indexes for primary keys
            if indexName.hasPrefix("sqlite_autoindex_") { continue }

            let infoSQL = "PRAGMA index_info(\(indexName.quotedDatabaseIdentifier))"
            let infoRows = try Row.fetchAll(db, sql: infoSQL)
            let columns: [String] = infoRows
                .sorted { ($0["seqno"] as Int) < ($1["seqno"] as Int) }
                .map { $0["name"] }

            indexes.append(IndexSchema(
                name: indexName,
                isUnique: isUnique,
                columns: columns
            ))
        }
        return indexes
    }
}
