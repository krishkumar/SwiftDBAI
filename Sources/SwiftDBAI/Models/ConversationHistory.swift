// ConversationHistory.swift
// SwiftDBAI
//
// Ordered chat message history with configurable context window.

import Foundation

/// Stores an ordered sequence of ``ChatMessage`` instances with a configurable
/// context window limit.
///
/// When the number of messages exceeds ``maxMessages``, the oldest messages are
/// trimmed to keep the history within budget. This prevents unbounded token
/// growth when building LLM prompts from conversation history.
///
/// Usage:
/// ```swift
/// var history = ConversationHistory(maxMessages: 20)
/// history.append(ChatMessage(role: .user, content: "How many users?"))
/// history.append(ChatMessage(role: .assistant, content: "42", sql: "SELECT COUNT(*) FROM users"))
/// print(history.promptText) // formatted for LLM context
/// ```
public struct ConversationHistory: Sendable {

    /// The maximum number of messages to retain. `nil` means unlimited.
    public let maxMessages: Int?

    /// All messages in chronological order.
    public private(set) var messages: [ChatMessage] = []

    /// Creates a new conversation history.
    ///
    /// - Parameter maxMessages: Maximum number of messages to keep in the
    ///   context window. Pass `nil` for unlimited history. Defaults to 50.
    public init(maxMessages: Int? = 50) {
        precondition(maxMessages == nil || maxMessages! > 0,
                     "maxMessages must be positive or nil")
        self.maxMessages = maxMessages
    }

    /// The number of messages currently stored.
    public var count: Int { messages.count }

    /// Whether the history is empty.
    public var isEmpty: Bool { messages.isEmpty }

    // MARK: - Mutating Operations

    /// Appends a message and trims the history if it exceeds the context window.
    public mutating func append(_ message: ChatMessage) {
        messages.append(message)
        trimIfNeeded()
    }

    /// Appends multiple messages and trims once afterward.
    public mutating func append(contentsOf newMessages: [ChatMessage]) {
        messages.append(contentsOf: newMessages)
        trimIfNeeded()
    }

    /// Removes all messages from the history.
    public mutating func clear() {
        messages.removeAll()
    }

    // MARK: - Context Window

    /// Returns the most recent messages formatted for inclusion in an LLM prompt.
    ///
    /// Each message is formatted as `[role] content`, with SQL and query results
    /// included inline for assistant messages.
    ///
    /// - Parameter limit: Optional override to further restrict the number of
    ///   messages returned. When `nil`, uses the full retained history.
    /// - Returns: An array of prompt-formatted strings, one per message.
    public func promptMessages(limit: Int? = nil) -> [String] {
        let slice: ArraySlice<ChatMessage>
        if let limit {
            slice = messages.suffix(limit)
        } else {
            slice = messages[...]
        }
        return slice.map { message in
            Self.formatForPrompt(message)
        }
    }

    /// Returns the combined prompt text for all retained messages, separated by
    /// double newlines.
    public var promptText: String {
        promptMessages().joined(separator: "\n\n")
    }

    // MARK: - Queries

    /// Returns only user messages.
    public var userMessages: [ChatMessage] {
        messages.filter { $0.role == .user }
    }

    /// Returns only assistant messages.
    public var assistantMessages: [ChatMessage] {
        messages.filter { $0.role == .assistant }
    }

    /// Returns the last message, if any.
    public var lastMessage: ChatMessage? {
        messages.last
    }

    /// Returns the most recent user query text, if any.
    public var lastUserQuery: String? {
        messages.last(where: { $0.role == .user })?.content
    }

    /// Returns the most recent assistant message, if any.
    public var lastAssistantMessage: ChatMessage? {
        messages.last(where: { $0.role == .assistant })
    }

    // MARK: - Private

    /// Formats a ``ChatMessage`` into a string suitable for LLM prompt context.
    private static func formatForPrompt(_ message: ChatMessage) -> String {
        var parts: [String] = ["[\(message.role.rawValue)] \(message.content)"]

        if let sql = message.sql {
            parts.append("SQL: \(sql)")
        }

        if let result = message.queryResult {
            parts.append("Result:\n\(result.tabularDescription)")
        }

        return parts.joined(separator: "\n")
    }

    /// Trims the oldest messages to stay within the context window.
    private mutating func trimIfNeeded() {
        guard let max = maxMessages, messages.count > max else { return }
        let overflow = messages.count - max
        messages.removeFirst(overflow)
    }
}
