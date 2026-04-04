// ErrorMessageView.swift
// SwiftDBAI
//
// Reusable SwiftUI component that renders error messages with contextual
// icons, descriptions, and optional retry actions based on the error type.

import SwiftUI

/// A reusable SwiftUI component that renders a ``SwiftDBAIError`` with an
/// appropriate icon, human-readable message, and optional retry action.
///
/// The view automatically selects a visual treatment based on the error
/// category:
///
/// | Category          | Icon                          | Color   | Retry? |
/// |-------------------|-------------------------------|---------|--------|
/// | Safety / blocked  | `shield.trianglebadge.excl…`  | Orange  | No     |
/// | Confirmation      | `hand.raised.fill`            | Yellow  | Yes*   |
/// | LLM failure       | `brain`                       | Purple  | Yes    |
/// | Schema / DB       | `cylinder.split.1x2`          | Red     | No     |
/// | Recoverable SQL   | `arrow.clockwise`             | Blue    | Yes    |
/// | Generic           | `exclamationmark.triangle`    | Red     | No     |
///
/// *Confirmation retry triggers the confirm callback, not a standard retry.
///
/// Usage:
/// ```swift
/// ErrorMessageView(
///     error: .llmTimeout(seconds: 30),
///     onRetry: { /* resend the message */ }
/// )
/// ```
@available(iOS 17.0, macOS 14.0, visionOS 1.0, *)
public struct ErrorMessageView: View {
    /// The error to display. When `nil`, the view falls back to the raw message.
    private let error: SwiftDBAIError?

    /// The raw error message string (used as fallback when error is nil).
    private let message: String

    /// Called when the user taps the retry button. `nil` hides the button.
    private let onRetry: (@Sendable () async -> Void)?

    /// Called when the user confirms a destructive operation.
    private let onConfirm: (@Sendable () async -> Void)?

    @State private var isRetrying = false

    // MARK: - Initializers

    /// Creates an ErrorMessageView from a typed ``SwiftDBAIError``.
    ///
    /// - Parameters:
    ///   - error: The ``SwiftDBAIError`` to display.
    ///   - onRetry: An optional async closure invoked when the user taps retry.
    ///   - onConfirm: An optional async closure invoked when the user confirms
    ///     a destructive operation (only relevant for `.confirmationRequired`).
    public init(
        error: SwiftDBAIError,
        onRetry: (@Sendable () async -> Void)? = nil,
        onConfirm: (@Sendable () async -> Void)? = nil
    ) {
        self.error = error
        self.message = error.localizedDescription
        self.onRetry = onRetry
        self.onConfirm = onConfirm
    }

    /// Creates an ErrorMessageView from a ``ChatMessage``.
    ///
    /// Extracts the typed error if available, otherwise falls back to the
    /// message content string.
    ///
    /// - Parameters:
    ///   - message: The chat message with role `.error`.
    ///   - onRetry: An optional async closure invoked when the user taps retry.
    ///   - onConfirm: An optional async closure invoked when the user confirms
    ///     a destructive operation.
    public init(
        chatMessage: ChatMessage,
        onRetry: (@Sendable () async -> Void)? = nil,
        onConfirm: (@Sendable () async -> Void)? = nil
    ) {
        self.error = chatMessage.error
        self.message = chatMessage.content
        self.onRetry = onRetry
        self.onConfirm = onConfirm
    }

    /// Creates an ErrorMessageView from a plain string (untyped fallback).
    ///
    /// - Parameters:
    ///   - message: The error message string.
    ///   - onRetry: An optional async closure invoked when the user taps retry.
    public init(
        message: String,
        onRetry: (@Sendable () async -> Void)? = nil
    ) {
        self.error = nil
        self.message = message
        self.onRetry = onRetry
        self.onConfirm = nil
    }

    // MARK: - Body

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Icon + message row
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: iconName)
                    .foregroundStyle(iconColor)
                    .font(.callout)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 4) {
                    if let title = errorTitle {
                        Text(title)
                            .font(.callout.weight(.semibold))
                            .foregroundStyle(iconColor)
                    }

                    Text(message)
                        .font(.body)
                        .foregroundStyle(.primary)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)

                    if let hint = recoveryHint {
                        Text(hint)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            // Action buttons
            if showRetryButton || showConfirmButton {
                HStack(spacing: 12) {
                    if showConfirmButton {
                        confirmButton
                    }
                    if showRetryButton {
                        retryButton
                    }
                }
                .padding(.leading, 26) // Align with text (icon width + spacing)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityDescription)
    }

    // MARK: - Action Buttons

    @ViewBuilder
    private var retryButton: some View {
        Button {
            guard !isRetrying else { return }
            isRetrying = true
            Task {
                await onRetry?()
                isRetrying = false
            }
        } label: {
            HStack(spacing: 4) {
                if isRetrying {
                    ProgressView()
                        .controlSize(.mini)
                } else {
                    Image(systemName: "arrow.clockwise")
                        .font(.caption)
                }
                Text(retryButtonLabel)
                    .font(.caption.weight(.medium))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(iconColor.opacity(0.12))
            .foregroundStyle(iconColor)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(isRetrying)
    }

    @ViewBuilder
    private var confirmButton: some View {
        Button {
            Task {
                await onConfirm?()
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "checkmark.circle")
                    .font(.caption)
                Text("Confirm")
                    .font(.caption.weight(.medium))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.orange.opacity(0.12))
            .foregroundStyle(.orange)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Error Classification

    private var errorCategory: ErrorCategory {
        guard let error else { return .generic }

        if error.requiresUserAction {
            return .confirmation
        }
        if error.isSafetyError {
            return .safety
        }
        if error.isRecoverable {
            return .recoverable
        }

        switch error {
        case .llmFailure, .llmResponseUnparseable, .llmTimeout:
            return .llm
        case .schemaIntrospectionFailed, .emptySchema, .databaseError, .queryTimedOut:
            return .database
        case .configurationError:
            return .configuration
        default:
            return .generic
        }
    }

    private enum ErrorCategory {
        case safety
        case confirmation
        case llm
        case database
        case recoverable
        case configuration
        case generic
    }

    // MARK: - Visual Properties

    private var iconName: String {
        switch errorCategory {
        case .safety:
            return "shield.trianglebadge.exclamationmark.fill"
        case .confirmation:
            return "hand.raised.fill"
        case .llm:
            return "brain"
        case .database:
            return "cylinder.split.1x2"
        case .recoverable:
            return "arrow.clockwise"
        case .configuration:
            return "gearshape.triangle.fill"
        case .generic:
            return "exclamationmark.triangle.fill"
        }
    }

    private var iconColor: Color {
        switch errorCategory {
        case .safety:
            return .orange
        case .confirmation:
            return .yellow
        case .llm:
            return .purple
        case .database:
            return .red
        case .recoverable:
            return .blue
        case .configuration:
            return .gray
        case .generic:
            return .red
        }
    }

    private var errorTitle: String? {
        switch errorCategory {
        case .safety:
            return "Operation Blocked"
        case .confirmation:
            return "Confirmation Required"
        case .llm:
            return "AI Provider Error"
        case .database:
            return "Database Error"
        case .recoverable:
            return "Query Issue"
        case .configuration:
            return "Configuration Error"
        case .generic:
            return nil
        }
    }

    private var recoveryHint: String? {
        guard let error else { return nil }

        switch error {
        case .noSQLGenerated, .llmResponseUnparseable:
            return "Try rephrasing your question."
        case .tableNotFound:
            return "Check that you're referring to an existing table."
        case .columnNotFound:
            return "Verify the column name matches your schema."
        case .invalidSQL:
            return "The AI generated an invalid query. Try asking differently."
        case .llmTimeout:
            return "The AI took too long. Try a simpler question."
        case .llmFailure:
            return "The AI service may be temporarily unavailable."
        case .emptySchema:
            return "Add some tables to your database first."
        case .queryTimedOut:
            return "Try a simpler query or add database indexes."
        default:
            return nil
        }
    }

    // MARK: - Button Visibility

    private var showRetryButton: Bool {
        guard onRetry != nil else { return false }
        return errorCategory == .recoverable || errorCategory == .llm
    }

    private var showConfirmButton: Bool {
        guard onConfirm != nil else { return false }
        return errorCategory == .confirmation
    }

    private var retryButtonLabel: String {
        switch errorCategory {
        case .llm:
            return "Retry"
        case .recoverable:
            return "Try Again"
        default:
            return "Retry"
        }
    }

    // MARK: - Accessibility

    private var accessibilityDescription: String {
        let prefix = errorTitle.map { "\($0): " } ?? "Error: "
        return prefix + message
    }
}
