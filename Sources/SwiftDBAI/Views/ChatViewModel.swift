// ChatViewModel.swift
// SwiftDBAI
//
// Observable view model that bridges ChatEngine with the SwiftUI ChatView.

import Foundation
import Observation

/// The readiness state of the schema introspection.
public enum SchemaReadiness: Sendable, Equatable {
    /// Schema has not been loaded yet.
    case idle
    /// Schema introspection is in progress.
    case loading
    /// Schema is ready with the given number of tables.
    case ready(tableCount: Int)
    /// Schema introspection failed.
    case failed(String)

    public var isReady: Bool {
        if case .ready = self { return true }
        return false
    }
}

/// Observable view model that drives the `ChatView`.
///
/// Wraps `ChatEngine` to provide reactive state updates for the SwiftUI layer.
/// Manages the message list, loading state, error presentation, and schema
/// readiness. Call ``prepare()`` at view-appear time to eagerly introspect the
/// database schema.
///
/// Usage:
/// ```swift
/// let viewModel = ChatViewModel(engine: myChatEngine)
/// ChatView(viewModel: viewModel)
/// ```
@available(iOS 17.0, macOS 14.0, visionOS 1.0, *)
@Observable
@MainActor
public final class ChatViewModel {

    // MARK: - Public State

    /// All messages in the conversation, in chronological order.
    public private(set) var messages: [ChatMessage] = []

    /// Whether the engine is currently processing a request.
    public private(set) var isLoading: Bool = false

    /// The most recent error message, if any. Cleared on next send.
    public private(set) var errorMessage: String?

    /// Current schema readiness state.
    public private(set) var schemaReadiness: SchemaReadiness = .idle

    // MARK: - Dependencies

    private let engine: ChatEngine

    // MARK: - Initialization

    /// Creates a new ChatViewModel.
    ///
    /// - Parameter engine: The `ChatEngine` to use for processing messages.
    public init(engine: ChatEngine) {
        self.engine = engine
    }

    // MARK: - Schema Preparation

    /// Eagerly introspects the database schema so it's ready before the first query.
    ///
    /// This should be called from a `.task` modifier on the view. It transitions
    /// `schemaReadiness` through `.loading` → `.ready` (or `.failed`).
    /// If the schema is already cached, this completes immediately.
    public func prepare() async {
        // Don't re-prepare if already ready
        if schemaReadiness.isReady { return }

        schemaReadiness = .loading

        do {
            let schema = try await engine.prepareSchema()
            schemaReadiness = .ready(tableCount: schema.tableNames.count)
        } catch {
            schemaReadiness = .failed(error.localizedDescription)
        }
    }

    // MARK: - Public API

    /// Sends a user message and appends the response to the conversation.
    ///
    /// - Parameter text: The natural language message from the user.
    public func send(_ text: String) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        errorMessage = nil

        // Add user message immediately
        let userMessage = ChatMessage(role: .user, content: trimmed)
        messages.append(userMessage)

        isLoading = true
        defer { isLoading = false }

        do {
            let response = try await engine.send(trimmed)

            let assistantMessage = ChatMessage(
                role: .assistant,
                content: response.summary,
                queryResult: response.queryResult,
                sql: response.sql
            )
            messages.append(assistantMessage)
        } catch {
            let typedError = (error as? SwiftDBAIError)
            let errorMsg = ChatMessage(
                role: .error,
                content: error.localizedDescription,
                error: typedError
            )
            messages.append(errorMsg)
            errorMessage = error.localizedDescription
        }
    }

    /// Clears the conversation and resets the engine state.
    public func reset() {
        messages.removeAll()
        errorMessage = nil
        engine.reset()
    }
}
