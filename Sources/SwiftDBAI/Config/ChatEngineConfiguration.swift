// ChatEngineConfiguration.swift
// SwiftDBAI
//
// Configurable settings for ChatEngine behavior — timeouts, context window,
// summary limits, and custom query validation.

import Foundation

/// Configuration for ``ChatEngine`` behavior.
///
/// Use this to tune timeouts, conversation context windows, and attach
/// custom query validators.
///
/// ```swift
/// var config = ChatEngineConfiguration()
/// config.queryTimeout = 10        // 10-second SQL timeout
/// config.contextWindowSize = 20   // Keep last 20 messages for LLM context
/// config.maxSummaryRows = 100     // Summarize up to 100 rows
///
/// let engine = ChatEngine(
///     database: db,
///     model: model,
///     configuration: config
/// )
/// ```
public struct ChatEngineConfiguration: Sendable {

    // MARK: - Query Execution

    /// Maximum time (in seconds) to wait for a SQL query to execute.
    ///
    /// If the query exceeds this duration, a ``ChatEngineError/queryTimedOut``
    /// error is thrown. Set to `nil` to disable the timeout (not recommended
    /// for user-facing apps). Defaults to 30 seconds.
    public var queryTimeout: TimeInterval?

    // MARK: - Conversation Context

    /// Maximum number of conversation messages to include when building
    /// LLM context for follow-up queries.
    ///
    /// Only the most recent `contextWindowSize` messages are sent to the LLM.
    /// Older messages are still retained in ``ChatEngine/messages`` for UI
    /// display but do not consume LLM tokens.
    ///
    /// Set to `nil` for unlimited context (all history is always sent).
    /// Defaults to 50 messages.
    public var contextWindowSize: Int?

    // MARK: - Rendering

    /// Maximum number of rows to include when generating text summaries.
    /// Defaults to 50.
    public var maxSummaryRows: Int

    // MARK: - LLM Context

    /// Optional extra instructions appended to the LLM system prompt.
    ///
    /// Use this to provide business-specific terminology, query hints,
    /// or domain constraints. For example:
    /// ```swift
    /// config.additionalContext = "The 'status' column uses: 'active', 'inactive', 'suspended'."
    /// ```
    public var additionalContext: String?

    // MARK: - Validation

    /// Custom query validators that run after the built-in allowlist check.
    ///
    /// Use ``addValidator(_:)`` to add validators. They are executed in order;
    /// the first validator to throw stops execution.
    public private(set) var validators: [any QueryValidator] = []

    // MARK: - Initialization

    /// Creates a configuration with the given settings.
    ///
    /// - Parameters:
    ///   - queryTimeout: SQL execution timeout in seconds. Defaults to 30.
    ///   - contextWindowSize: Max messages for LLM context. Defaults to 50.
    ///   - maxSummaryRows: Max rows for text summaries. Defaults to 50.
    ///   - additionalContext: Extra LLM system prompt instructions.
    public init(
        queryTimeout: TimeInterval? = 30,
        contextWindowSize: Int? = 50,
        maxSummaryRows: Int = 50,
        additionalContext: String? = nil
    ) {
        self.queryTimeout = queryTimeout
        self.contextWindowSize = contextWindowSize
        self.maxSummaryRows = maxSummaryRows
        self.additionalContext = additionalContext
    }

    /// The default configuration: 30s timeout, 50-message context window,
    /// 50-row summaries, no additional context, no custom validators.
    public static let `default` = ChatEngineConfiguration()

    // MARK: - Mutating Helpers

    /// Appends a custom query validator.
    ///
    /// Validators run after the built-in allowlist and dangerous-keyword checks.
    /// They receive the parsed SQL and can throw to reject a query.
    ///
    /// ```swift
    /// config.addValidator(TableAllowlistValidator(allowedTables: ["users", "orders"]))
    /// ```
    public mutating func addValidator(_ validator: any QueryValidator) {
        validators.append(validator)
    }
}
