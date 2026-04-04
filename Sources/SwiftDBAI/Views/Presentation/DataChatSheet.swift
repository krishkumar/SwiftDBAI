// DataChatSheet.swift
// SwiftDBAI
//
// SwiftUI wrapper that adds NavigationStack chrome around DataChatView.
// Designed for use with .sheet() and .fullScreenCover().

import AnyLanguageModel
import GRDB
import SwiftUI

/// A presentation-ready wrapper around ``DataChatView`` that adds a
/// `NavigationStack`, title, and **Done** button.
///
/// Use `DataChatSheet` with SwiftUI's `.sheet()` or `.fullScreenCover()`
/// modifiers so consumers get a fully navigable chat experience out of the box.
///
/// ```swift
/// .sheet(isPresented: $showChat) {
///     DataChatSheet(
///         databasePath: "/path/to/mydata.sqlite",
///         model: OllamaLanguageModel(model: "llama3")
///     )
/// }
/// ```
@available(iOS 17.0, macOS 14.0, visionOS 1.0, *)
public struct DataChatSheet: View {
    let databasePath: String?
    let database: (any DatabaseWriter)?
    let model: any LanguageModel
    var allowlist: OperationAllowlist
    var additionalContext: String?
    var title: String
    @Environment(\.dismiss) private var dismiss

    /// Creates a DataChatSheet from a database file path and language model.
    ///
    /// - Parameters:
    ///   - databasePath: Absolute path to a SQLite database file.
    ///   - model: Any `AnyLanguageModel`-compatible language model instance.
    ///   - allowlist: SQL operations the LLM may generate. Defaults to `.readOnly`.
    ///   - additionalContext: Optional extra context about the database for the LLM.
    ///   - title: Navigation bar title. Defaults to `"AI Chat"`.
    public init(
        databasePath: String,
        model: any LanguageModel,
        allowlist: OperationAllowlist = .readOnly,
        additionalContext: String? = nil,
        title: String = "AI Chat"
    ) {
        self.databasePath = databasePath
        self.database = nil
        self.model = model
        self.allowlist = allowlist
        self.additionalContext = additionalContext
        self.title = title
    }

    /// Creates a DataChatSheet from an existing GRDB database connection.
    ///
    /// - Parameters:
    ///   - database: A GRDB `DatabaseWriter` (`DatabasePool` or `DatabaseQueue`).
    ///   - model: Any `AnyLanguageModel`-compatible language model instance.
    ///   - allowlist: SQL operations the LLM may generate. Defaults to `.readOnly`.
    ///   - additionalContext: Optional extra context about the database for the LLM.
    ///   - title: Navigation bar title. Defaults to `"AI Chat"`.
    public init(
        database: any DatabaseWriter,
        model: any LanguageModel,
        allowlist: OperationAllowlist = .readOnly,
        additionalContext: String? = nil,
        title: String = "AI Chat"
    ) {
        self.databasePath = nil
        self.database = database
        self.model = model
        self.allowlist = allowlist
        self.additionalContext = additionalContext
        self.title = title
    }

    public var body: some View {
        NavigationStack {
            dataChatView
                .navigationTitle(title)
                #if !os(macOS)
                .navigationBarTitleDisplayMode(.inline)
                #endif
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Done") { dismiss() }
                    }
                }
        }
    }

    @ViewBuilder
    private var dataChatView: some View {
        if let database {
            DataChatView(
                database: database,
                model: model,
                allowlist: allowlist,
                additionalContext: additionalContext
            )
        } else if let databasePath {
            DataChatView(
                databasePath: databasePath,
                model: model,
                allowlist: allowlist,
                additionalContext: additionalContext
            )
        }
    }
}
