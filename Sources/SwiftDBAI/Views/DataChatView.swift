// DataChatView.swift
// SwiftDBAI
//
// Zero-config SwiftUI view: provide a database path and a model, get a chat UI.

import AnyLanguageModel
import GRDB
import SwiftUI

/// A convenience SwiftUI view that wraps the full chat-with-database stack.
///
/// `DataChatView` is the simplest entry point into SwiftDBAI. It requires only
/// a database file path and a language model — no schema files, no annotations,
/// no manual setup. The view creates a GRDB connection, a `ChatEngine`,
/// a `ChatViewModel`, and renders a fully functional `ChatView`.
///
/// Usage with just a path and model:
/// ```swift
/// DataChatView(
///     databasePath: "/path/to/mydata.sqlite",
///     model: OllamaLanguageModel(model: "llama3")
/// )
/// ```
///
/// Usage with additional configuration:
/// ```swift
/// DataChatView(
///     databasePath: documentsURL.appendingPathComponent("app.db").path,
///     model: OpenAILanguageModel(apiKey: key),
///     allowlist: .standard,
///     additionalContext: "This database stores a recipe app's data."
/// )
/// ```
///
/// If you already have a GRDB `DatabasePool` or `DatabaseQueue`, use
/// `ChatView` with a `ChatEngine` directly for full control.
@available(iOS 17.0, macOS 14.0, visionOS 1.0, *)
public struct DataChatView: View {
    @State private var viewModel: ChatViewModel
    @State private var loadError: DataChatError?

    /// Creates a DataChatView from a database file path and language model.
    ///
    /// This is the zero-config convenience initializer. It opens a GRDB
    /// `DatabasePool` at the given path, creates a `ChatEngine` with
    /// read-only defaults, and wires up the full chat UI.
    ///
    /// - Parameters:
    ///   - databasePath: Absolute path to a SQLite database file.
    ///   - model: Any `AnyLanguageModel`-compatible language model instance.
    ///   - allowlist: SQL operations the LLM may generate. Defaults to `.readOnly` (SELECT only).
    ///   - additionalContext: Optional extra context about the database for the LLM system prompt
    ///     (e.g., "This database stores e-commerce orders and products.").
    ///   - maxSummaryRows: Maximum rows to include when summarizing results (default: 50).
    public init(
        databasePath: String,
        model: any LanguageModel,
        allowlist: OperationAllowlist = .readOnly,
        additionalContext: String? = nil,
        maxSummaryRows: Int = 50
    ) {
        do {
            let pool = try DatabasePool(path: databasePath)
            let engine = ChatEngine(
                database: pool,
                model: model,
                allowlist: allowlist,
                additionalContext: additionalContext,
                maxSummaryRows: maxSummaryRows
            )
            self._viewModel = State(initialValue: ChatViewModel(engine: engine))
            self._loadError = State(initialValue: nil)
        } catch {
            // If the database can't be opened, create a placeholder engine
            // and store the error to display in the UI.
            let queue = try! DatabaseQueue()
            let engine = ChatEngine(
                database: queue,
                model: model,
                allowlist: allowlist,
                additionalContext: additionalContext,
                maxSummaryRows: maxSummaryRows
            )
            self._viewModel = State(initialValue: ChatViewModel(engine: engine))
            self._loadError = State(initialValue: DataChatError.databaseOpenFailed(
                path: databasePath,
                underlying: error
            ))
        }
    }

    /// Creates a DataChatView from an existing GRDB database connection and language model.
    ///
    /// Use this initializer when you already have a configured `DatabasePool` or
    /// `DatabaseQueue` and want the convenience of `DataChatView` without
    /// creating a `ChatEngine` yourself.
    ///
    /// - Parameters:
    ///   - database: A GRDB `DatabaseWriter` (`DatabasePool` or `DatabaseQueue`).
    ///   - model: Any `AnyLanguageModel`-compatible language model instance.
    ///   - allowlist: SQL operations the LLM may generate. Defaults to `.readOnly`.
    ///   - additionalContext: Optional extra context about the database for the LLM.
    ///   - maxSummaryRows: Maximum rows to include when summarizing results (default: 50).
    public init(
        database: any DatabaseWriter,
        model: any LanguageModel,
        allowlist: OperationAllowlist = .readOnly,
        additionalContext: String? = nil,
        maxSummaryRows: Int = 50
    ) {
        let engine = ChatEngine(
            database: database,
            model: model,
            allowlist: allowlist,
            additionalContext: additionalContext,
            maxSummaryRows: maxSummaryRows
        )
        self._viewModel = State(initialValue: ChatViewModel(engine: engine))
        self._loadError = State(initialValue: nil)
    }

    public var body: some View {
        if let error = loadError {
            errorView(error)
        } else {
            ChatView(viewModel: viewModel)
                .task {
                    await viewModel.prepare()
                }
                .overlay {
                    if case .loading = viewModel.schemaReadiness {
                        schemaLoadingView
                    }
                    if case .failed(let reason) = viewModel.schemaReadiness {
                        schemaErrorView(reason)
                    }
                }
        }
    }

    // MARK: - Schema Loading View

    @ViewBuilder
    private var schemaLoadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .controlSize(.large)
            Text("Introspecting database schema…")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.ultraThinMaterial)
    }

    // MARK: - Schema Error View

    @ViewBuilder
    private func schemaErrorView(_ reason: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 40))
                .foregroundStyle(.orange)

            Text("Schema Introspection Failed")
                .font(.headline)

            Text(reason)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            Button("Retry") {
                Task {
                    await viewModel.prepare()
                }
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.ultraThinMaterial)
    }

    // MARK: - Database Open Error View

    @ViewBuilder
    private func errorView(_ error: DataChatError) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 40))
                .foregroundStyle(.red)

            Text("Unable to Open Database")
                .font(.headline)

            Text(error.localizedDescription)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Errors

/// Errors specific to `DataChatView` initialization.
public enum DataChatError: Error, LocalizedError, Sendable {
    /// The database file could not be opened at the given path.
    case databaseOpenFailed(path: String, underlying: any Error)

    public var errorDescription: String? {
        switch self {
        case .databaseOpenFailed(let path, let underlying):
            return "Could not open database at \"\(path)\": \(underlying.localizedDescription)"
        }
    }
}
