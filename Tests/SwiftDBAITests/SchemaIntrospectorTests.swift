// SchemaIntrospectorTests.swift
// SwiftDBAI

import Testing
import GRDB
@testable import SwiftDBAI

@Suite("SchemaIntrospector")
struct SchemaIntrospectorTests {

    // MARK: - Helper

    /// Creates an in-memory database with a sample schema for testing.
    private func makeTestDatabase() throws -> DatabaseQueue {
        let db = try DatabaseQueue(configuration: {
            var config = Configuration()
            config.foreignKeysEnabled = true
            return config
        }())

        try db.write { db in
            try db.execute(sql: """
                CREATE TABLE authors (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    name TEXT NOT NULL,
                    email TEXT UNIQUE
                );
                """)

            try db.execute(sql: """
                CREATE TABLE books (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    title TEXT NOT NULL,
                    author_id INTEGER NOT NULL REFERENCES authors(id) ON DELETE CASCADE,
                    published_date TEXT,
                    price REAL DEFAULT 9.99
                );
                """)

            try db.execute(sql: """
                CREATE INDEX idx_books_author ON books(author_id);
                """)

            try db.execute(sql: """
                CREATE INDEX idx_books_title ON books(title);
                """)

            try db.execute(sql: """
                CREATE TABLE reviews (
                    id INTEGER PRIMARY KEY,
                    book_id INTEGER NOT NULL REFERENCES books(id),
                    rating INTEGER NOT NULL,
                    comment TEXT
                );
                """)
        }

        return db
    }

    // MARK: - Tests

    @Test("Discovers all user tables")
    func discoversAllTables() async throws {
        let db = try makeTestDatabase()
        let schema = try await SchemaIntrospector.introspect(database: db)

        #expect(schema.tableNames.count == 3)
        #expect(schema.tableNames.contains("authors"))
        #expect(schema.tableNames.contains("books"))
        #expect(schema.tableNames.contains("reviews"))
    }

    @Test("Excludes sqlite_ internal tables")
    func excludesInternalTables() async throws {
        let db = try makeTestDatabase()
        let schema = try await SchemaIntrospector.introspect(database: db)

        for name in schema.tableNames {
            #expect(!name.hasPrefix("sqlite_"))
        }
    }

    @Test("Introspects column names and types")
    func introspectsColumns() async throws {
        let db = try makeTestDatabase()
        let schema = try await SchemaIntrospector.introspect(database: db)

        let books = try #require(schema.tables["books"])
        #expect(books.columns.count == 5)

        let titleCol = try #require(books.columns.first { $0.name == "title" })
        #expect(titleCol.type == "TEXT")
        #expect(titleCol.isNotNull == true)
        #expect(titleCol.isPrimaryKey == false)

        let priceCol = try #require(books.columns.first { $0.name == "price" })
        #expect(priceCol.type == "REAL")
        #expect(priceCol.defaultValue == "9.99")
    }

    @Test("Detects primary keys")
    func detectsPrimaryKeys() async throws {
        let db = try makeTestDatabase()
        let schema = try await SchemaIntrospector.introspect(database: db)

        let authors = try #require(schema.tables["authors"])
        #expect(authors.primaryKey == ["id"])

        let idCol = try #require(authors.columns.first { $0.name == "id" })
        #expect(idCol.isPrimaryKey == true)
    }

    @Test("Detects foreign keys")
    func detectsForeignKeys() async throws {
        let db = try makeTestDatabase()
        let schema = try await SchemaIntrospector.introspect(database: db)

        let books = try #require(schema.tables["books"])
        #expect(books.foreignKeys.count == 1)

        let fk = books.foreignKeys[0]
        #expect(fk.fromColumn == "author_id")
        #expect(fk.toTable == "authors")
        #expect(fk.toColumn == "id")
        #expect(fk.onDelete == "CASCADE")
    }

    @Test("Detects indexes")
    func detectsIndexes() async throws {
        let db = try makeTestDatabase()
        let schema = try await SchemaIntrospector.introspect(database: db)

        let books = try #require(schema.tables["books"])
        let indexNames = books.indexes.map(\.name)
        #expect(indexNames.contains("idx_books_author"))
        #expect(indexNames.contains("idx_books_title"))
    }

    @Test("Detects NOT NULL constraints")
    func detectsNotNull() async throws {
        let db = try makeTestDatabase()
        let schema = try await SchemaIntrospector.introspect(database: db)

        let reviews = try #require(schema.tables["reviews"])
        let ratingCol = try #require(reviews.columns.first { $0.name == "rating" })
        #expect(ratingCol.isNotNull == true)

        let commentCol = try #require(reviews.columns.first { $0.name == "comment" })
        #expect(commentCol.isNotNull == false)
    }

    @Test("Generates LLM-friendly schema description")
    func generatesSchemaDescription() async throws {
        let db = try makeTestDatabase()
        let schema = try await SchemaIntrospector.introspect(database: db)

        let description = schema.schemaDescription
        #expect(description.contains("TABLE authors"))
        #expect(description.contains("TABLE books"))
        #expect(description.contains("FOREIGN KEY"))
        #expect(description.contains("REFERENCES authors(id)"))
        #expect(description.contains("INDEX idx_books_author"))
    }

    @Test("Handles empty database")
    func handlesEmptyDatabase() async throws {
        let db = try DatabaseQueue()
        let schema = try await SchemaIntrospector.introspect(database: db)

        #expect(schema.tables.isEmpty)
        #expect(schema.tableNames.isEmpty)
        #expect(schema.schemaDescription.isEmpty)
    }

    @Test("Handles composite primary keys")
    func handlesCompositePrimaryKey() async throws {
        let db = try DatabaseQueue()
        try await db.write { db in
            try db.execute(sql: """
                CREATE TABLE book_tags (
                    book_id INTEGER NOT NULL,
                    tag_id INTEGER NOT NULL,
                    PRIMARY KEY (book_id, tag_id)
                );
                """)
        }

        let schema = try await SchemaIntrospector.introspect(database: db)
        let bookTags = try #require(schema.tables["book_tags"])
        #expect(bookTags.primaryKey.count == 2)
        #expect(bookTags.primaryKey.contains("book_id"))
        #expect(bookTags.primaryKey.contains("tag_id"))
    }

    @Test("Handles tables with no explicit types (SQLite dynamic typing)")
    func handlesDynamicTyping() async throws {
        let db = try DatabaseQueue()
        try await db.write { db in
            try db.execute(sql: """
                CREATE TABLE flexible (
                    id INTEGER PRIMARY KEY,
                    data,
                    info BLOB
                );
                """)
        }

        let schema = try await SchemaIntrospector.introspect(database: db)
        let flexible = try #require(schema.tables["flexible"])

        let dataCol = try #require(flexible.columns.first { $0.name == "data" })
        #expect(dataCol.type == "") // No declared type

        let infoCol = try #require(flexible.columns.first { $0.name == "info" })
        #expect(infoCol.type == "BLOB")
    }

    @Test("Synchronous introspection works within database access")
    func synchronousIntrospection() async throws {
        let db = try DatabaseQueue()
        try await db.write { db in
            try db.execute(sql: "CREATE TABLE test (id INTEGER PRIMARY KEY, val TEXT);")
        }

        let schema = try await db.read { db in
            try SchemaIntrospector.introspect(db: db)
        }

        #expect(schema.tableNames == ["test"])
        let table = try #require(schema.tables["test"])
        #expect(table.columns.count == 2)
    }
}
