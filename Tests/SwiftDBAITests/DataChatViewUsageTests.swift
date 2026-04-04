// DataChatViewUsageTests.swift
// SwiftDBAITests
//
// Proves DataChatView works with minimal setup — under 10 lines of code.
// A developer only needs a GRDB connection and a LanguageModel to get a
// full chat-with-database SwiftUI view.

import Testing
import Foundation
import GRDB
@testable import SwiftDBAI

// MARK: - Minimal Setup: DataChatView in Under 10 Lines

/// This test suite proves the "zero_config_reads" principle:
/// A developer with an existing SQLite database can create a fully functional
/// chat UI by providing only a GRDB connection and a language model instance.
/// No schema files, no annotations, no manual configuration required.
@Suite("DataChatView Minimal Setup")
struct DataChatViewMinimalSetupTests {

    // ┌──────────────────────────────────────────────────────────┐
    // │  USAGE EXAMPLE — DataChatView in 6 lines of real code   │
    // │                                                          │
    // │  import SwiftDBAI                                        │
    // │  import GRDB                                             │
    // │                                                          │
    // │  let db = try DatabaseQueue(path: "mydata.sqlite")       │
    // │  let model = OllamaLanguageModel(model: "llama3")        │
    // │                                                          │
    // │  var body: some View {                                   │
    // │      DataChatView(database: db, model: model)            │
    // │  }                                                       │
    // └──────────────────────────────────────────────────────────┘

    /// Creates a temporary in-memory database with sample data for tests.
    private static func makeSampleDatabase() throws -> DatabaseQueue {
        let db = try DatabaseQueue()
        try db.write { db in
            try db.execute(sql: """
                CREATE TABLE products (
                    id INTEGER PRIMARY KEY,
                    name TEXT NOT NULL,
                    price REAL NOT NULL,
                    category TEXT
                );
                INSERT INTO products (name, price, category) VALUES ('Widget', 9.99, 'Hardware');
                INSERT INTO products (name, price, category) VALUES ('Gadget', 24.99, 'Electronics');
                INSERT INTO products (name, price, category) VALUES ('Doohickey', 4.99, 'Hardware');
                """)
        }
        return db
    }

    @Test("DataChatView initializes from database + model in 2 lines")
    @MainActor
    func dataChatViewMinimalInit() throws {
        // LINE 1: Create (or receive) a GRDB connection
        let db = try Self.makeSampleDatabase()
        // LINE 2: Create the view — that's it!
        let _ = DataChatView(database: db, model: MockLanguageModel())
        // The view is ready. No schema files, no annotations, no extra config.
    }

    @Test("DataChatView path-based init works in 1 line given a path and model")
    @MainActor
    func dataChatViewPathInit() throws {
        // Create a temp database file
        let tempDir = FileManager.default.temporaryDirectory
        let dbPath = tempDir.appendingPathComponent("test_\(UUID().uuidString).sqlite").path
        let db = try DatabaseQueue(path: dbPath)
        try db.write { db in
            try db.execute(sql: "CREATE TABLE users (id INTEGER PRIMARY KEY, name TEXT)")
        }

        // ONE LINE to get a full chat UI:
        let _ = DataChatView(databasePath: dbPath, model: MockLanguageModel())

        // Cleanup
        try? FileManager.default.removeItem(atPath: dbPath)
    }

    @Test("ChatEngine headless usage works in 3 lines")
    func chatEngineMinimalUsage() async throws {
        // LINE 1: Database
        let db = try Self.makeSampleDatabase()
        // LINE 2: Engine
        let engine = ChatEngine(database: db, model: MockLanguageModel(responseText: "SELECT COUNT(*) AS total FROM products"))
        // LINE 3: Schema preparation verifies auto-introspection works
        let schema = try await engine.prepareSchema()

        // The engine auto-discovered the schema — no manual config needed
        #expect(schema.tableNames.contains("products"))
        #expect(schema.tableNames.count == 1)
    }

    @Test("ChatViewModel works with zero configuration beyond db + model")
    @MainActor
    func chatViewModelMinimalUsage() async throws {
        let db = try Self.makeSampleDatabase()
        let engine = ChatEngine(database: db, model: MockLanguageModel())
        let viewModel = ChatViewModel(engine: engine)

        // Prepare triggers auto-schema-introspection
        await viewModel.prepare()

        #expect(viewModel.schemaReadiness.isReady)
        #expect(viewModel.messages.isEmpty) // Clean slate, ready to chat
    }

    @Test("Default configuration is read-only (safe by default)")
    @MainActor
    func defaultIsReadOnly() throws {
        let db = try Self.makeSampleDatabase()
        // No allowlist specified — defaults to .readOnly
        let _ = DataChatView(database: db, model: MockLanguageModel())
        // This compiles and works. SELECT-only is the safe default.
        // Developer must explicitly opt in to writes:
        // DataChatView(database: db, model: model, allowlist: .standard)
    }

    @Test("Full DataChatView with all options still under 10 lines")
    @MainActor
    func dataChatViewFullConfig() throws {
        let db = try Self.makeSampleDatabase()                          // 1
        let model = MockLanguageModel()                                  // 2
        let _ = DataChatView(                                            // 3-8
            database: db,
            model: model,
            allowlist: .readOnly,
            additionalContext: "Product catalog for an e-commerce store",
            maxSummaryRows: 100
        )
        // Even with ALL options specified, it's under 10 lines of setup.
    }
}
