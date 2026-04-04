// PresentationTests.swift
// SwiftDBAITests
//
// Tests for presentation modalities: DataChatSheet, DataChatViewController,
// and view modifier helpers.

import SwiftUI
import Testing
import ViewInspector
import GRDB
@testable import SwiftDBAI

// MARK: - Helpers

private func makeSampleDatabase() throws -> DatabaseQueue {
    let db = try DatabaseQueue()
    try db.write { db in
        try db.execute(sql: """
            CREATE TABLE items (
                id INTEGER PRIMARY KEY,
                name TEXT NOT NULL
            );
            INSERT INTO items (name) VALUES ('Alpha');
            """)
    }
    return db
}

// MARK: - DataChatSheet Tests

@Suite("DataChatSheet Tests")
struct DataChatSheetTests {

    @Test("DataChatSheet renders NavigationStack with title")
    @MainActor
    func sheetRendersNavigationStackWithTitle() throws {
        let db = try makeSampleDatabase()
        let sheet = DataChatSheet(
            database: db,
            model: MockLanguageModel(),
            title: "Test Chat"
        )

        let view = try sheet.inspect()
        // NavigationStack should be the root
        let navStack = try view.navigationStack()
        #expect(navStack != nil)
    }

    @Test("DataChatSheet has Done button")
    @MainActor
    func sheetHasDoneButton() throws {
        let db = try makeSampleDatabase()
        let sheet = DataChatSheet(
            database: db,
            model: MockLanguageModel()
        )

        let view = try sheet.inspect()
        // Find the Done button in the toolbar
        let button = try view.find(button: "Done")
        #expect(button != nil)
    }

    @Test("DataChatSheet renders DataChatView inside")
    @MainActor
    func sheetContainsDataChatView() throws {
        let db = try makeSampleDatabase()
        let sheet = DataChatSheet(
            database: db,
            model: MockLanguageModel()
        )

        let view = try sheet.inspect()
        // DataChatView should be present within the NavigationStack
        let dataChatView = try view.find(DataChatView.self)
        #expect(dataChatView != nil)
    }

    @Test("DataChatSheet path-based init works")
    @MainActor
    func sheetPathInit() throws {
        let tempDir = FileManager.default.temporaryDirectory
        let dbPath = tempDir.appendingPathComponent("sheet_test_\(UUID().uuidString).sqlite").path
        let db = try DatabaseQueue(path: dbPath)
        try db.write { db in
            try db.execute(sql: "CREATE TABLE t (id INTEGER PRIMARY KEY)")
        }

        let sheet = DataChatSheet(
            databasePath: dbPath,
            model: MockLanguageModel(),
            title: "Path Chat"
        )

        let view = try sheet.inspect()
        let navStack = try view.navigationStack()
        #expect(navStack != nil)

        try? FileManager.default.removeItem(atPath: dbPath)
    }

    @Test("DataChatSheet uses custom title")
    @MainActor
    func sheetCustomTitle() throws {
        let db = try makeSampleDatabase()
        let sheet = DataChatSheet(
            database: db,
            model: MockLanguageModel(),
            title: "My Custom Title"
        )

        // Verify the title property is set correctly
        #expect(sheet.title == "My Custom Title")
    }

    @Test("DataChatSheet defaults to AI Chat title")
    @MainActor
    func sheetDefaultTitle() throws {
        let db = try makeSampleDatabase()
        let sheet = DataChatSheet(
            database: db,
            model: MockLanguageModel()
        )

        #expect(sheet.title == "AI Chat")
    }

    @Test("DataChatSheet defaults to read-only allowlist")
    @MainActor
    func sheetDefaultAllowlist() throws {
        let db = try makeSampleDatabase()
        let sheet = DataChatSheet(
            database: db,
            model: MockLanguageModel()
        )

        #expect(sheet.allowlist == .readOnly)
    }
}

// MARK: - DataChatViewController Tests

#if canImport(UIKit) && !os(watchOS)
@Suite("DataChatViewController Tests")
struct DataChatViewControllerTests {

    @Test("DataChatViewController can be instantiated with database path")
    @MainActor
    func viewControllerPathInit() throws {
        let tempDir = FileManager.default.temporaryDirectory
        let dbPath = tempDir.appendingPathComponent("vc_test_\(UUID().uuidString).sqlite").path
        let db = try DatabaseQueue(path: dbPath)
        try db.write { db in
            try db.execute(sql: "CREATE TABLE t (id INTEGER PRIMARY KEY)")
        }

        let vc = DataChatViewController(
            databasePath: dbPath,
            model: MockLanguageModel()
        )

        #expect(vc.modalPresentationStyle == .formSheet)

        try? FileManager.default.removeItem(atPath: dbPath)
    }

    @Test("DataChatViewController can be instantiated with database connection")
    @MainActor
    func viewControllerDatabaseInit() throws {
        let db = try makeSampleDatabase()

        let vc = DataChatViewController(
            database: db,
            model: MockLanguageModel(),
            title: "VC Chat"
        )

        #expect(vc.modalPresentationStyle == .formSheet)
    }
}
#endif

// MARK: - View Modifier Tests

@Suite("DataChatSheet Modifier Tests")
struct DataChatSheetModifierTests {

    @Test("dataChatSheet modifier creates sheet correctly")
    @MainActor
    func sheetModifierCreatesSheet() throws {
        let db = try makeSampleDatabase()

        struct TestHost: View {
            @State var showChat = false
            let db: DatabaseQueue

            var body: some View {
                Text("Hello")
                    .dataChatSheet(
                        isPresented: $showChat,
                        database: db,
                        model: MockLanguageModel(),
                        title: "Modifier Chat"
                    )
            }
        }

        let host = TestHost(db: db)
        // Verify it compiles and can be inspected
        let view = try host.inspect()
        let text = try view.find(text: "Hello")
        #expect(text != nil)
    }

    @Test("dataChatSheet path modifier creates sheet correctly")
    @MainActor
    func sheetPathModifierCreatesSheet() throws {
        let tempDir = FileManager.default.temporaryDirectory
        let dbPath = tempDir.appendingPathComponent("mod_test_\(UUID().uuidString).sqlite").path
        let db = try DatabaseQueue(path: dbPath)
        try db.write { db in
            try db.execute(sql: "CREATE TABLE t (id INTEGER PRIMARY KEY)")
        }

        struct TestHost: View {
            @State var showChat = false
            let dbPath: String

            var body: some View {
                Text("World")
                    .dataChatSheet(
                        isPresented: $showChat,
                        databasePath: dbPath,
                        model: MockLanguageModel()
                    )
            }
        }

        let host = TestHost(dbPath: dbPath)
        let view = try host.inspect()
        let text = try view.find(text: "World")
        #expect(text != nil)

        try? FileManager.default.removeItem(atPath: dbPath)
    }
}
