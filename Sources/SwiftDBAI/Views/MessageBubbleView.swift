// MessageBubbleView.swift
// SwiftDBAI
//
// Renders a single ChatMessage as a styled bubble with optional
// data table and SQL disclosure for query results.

import SwiftUI
import Charts

/// Renders a single `ChatMessage` in the chat conversation.
///
/// - **User messages** display right-aligned with an accent-colored background
///   and white text, using a continuous rounded rectangle shape.
/// - **Assistant messages** display left-aligned with a secondary background.
///   The natural language text summary is the primary content, rendered with
///   full `.body` font and `.primary` foreground for readability.
///   If the message contains a `queryResult` with tabular data, a
///   `ScrollableDataTableView` is automatically embedded below the summary.
///   An optional SQL disclosure group shows the generated query.
/// - **Error messages** display left-aligned with a red-tinted background
///   and an exclamation mark icon.
@available(iOS 17.0, macOS 14.0, visionOS 1.0, *)
struct MessageBubbleView: View {
    @Environment(\.chatViewConfiguration) private var config

    let message: ChatMessage

    /// Whether to show the SQL query in a disclosure group.
    var showSQL: Bool = true

    /// Maximum height for the data table before it scrolls.
    var maxTableHeight: CGFloat = 300

    /// Called when the user taps "Retry" on a recoverable error.
    var onRetry: (@Sendable () async -> Void)?

    /// Called when the user confirms a destructive operation.
    var onConfirm: (@Sendable () async -> Void)?

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            if message.role == .user { Spacer(minLength: 48) }

            if message.role != .user, let icon = config.assistantAvatarIcon {
                assistantAvatar(icon: icon)
            }

            bubbleContent
                .padding(.horizontal, config.messagePadding)
                .padding(.vertical, config.messagePadding * 10 / 14)
                .background(bubbleBackground)
                .clipShape(bubbleShape)

            if message.role != .user { Spacer(minLength: 48) }
        }
    }

    @ViewBuilder
    private func assistantAvatar(icon: String) -> some View {
        Image(systemName: icon)
            .font(.system(size: 16))
            .foregroundStyle(.white)
            .frame(width: 32, height: 32)
            .background(config.assistantAvatarColor)
            .clipShape(Circle())
            .padding(.top, 2)
    }

    // MARK: - Bubble Content

    @ViewBuilder
    private var bubbleContent: some View {
        switch message.role {
        case .user:
            userContent
        case .assistant:
            assistantContent
        case .error:
            errorContent
        }
    }

    // MARK: - User Content

    @ViewBuilder
    private var userContent: some View {
        Text(message.content)
            .font(config.messageFont)
            .foregroundStyle(config.userTextColor)
            .textSelection(.enabled)
    }

    // MARK: - Assistant Content (Text Summary + Data Table + SQL)

    @ViewBuilder
    private var assistantContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Natural language text summary — primary content
            Text(message.content)
                .font(config.summaryFont)
                .foregroundStyle(config.assistantTextColor)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)

            // Data table — automatically shown when queryResult has tabular data
            if let queryResult = message.queryResult,
               !queryResult.columns.isEmpty,
               !queryResult.rows.isEmpty {
                dataTableSection(for: queryResult)
            }

            // SQL disclosure — collapsed by default for transparency
            if config.showSQLDisclosure, let sql = message.sql {
                sqlDisclosure(sql: sql)
            }
        }
    }

    // MARK: - Error Content

    @ViewBuilder
    private var errorContent: some View {
        ErrorMessageView(
            chatMessage: message,
            onRetry: onRetry,
            onConfirm: onConfirm
        )
    }

    /// Maximum height for the chart section.
    var maxChartHeight: CGFloat = 250

    /// Whether to show auto-detected charts. Defaults to `true`.
    var showCharts: Bool = true

    // MARK: - Chart Detection

    /// The shared detector used for chart eligibility checks.
    private static let chartDetector = ChartDataDetector()

    // MARK: - Data Table Section

    @ViewBuilder
    private func dataTableSection(for queryResult: QueryResult) -> some View {
        let dataTable = DataTable(queryResult)

        VStack(alignment: .leading, spacing: 8) {
            // Chart — automatically shown when ChartDataDetector finds eligible data
            if showCharts {
                chartSection(for: dataTable)
            }

            Divider()

            ScrollableDataTableView(
                dataTable: dataTable,
                showAlternatingRows: true,
                showFooter: true
            )
            .frame(maxHeight: maxTableHeight)
        }
    }

    // MARK: - Chart Section

    @ViewBuilder
    private func chartSection(for dataTable: DataTable) -> some View {
        let detector = Self.chartDetector
        if detector.detect(dataTable) != nil {
            VStack(alignment: .leading, spacing: 4) {
                ChartResultView(dataTable: dataTable, detector: detector)
                    .frame(maxHeight: maxChartHeight)
            }
        }
    }

    // MARK: - SQL Disclosure

    @ViewBuilder
    private func sqlDisclosure(sql: String) -> some View {
        DisclosureGroup {
            Text(sql)
                .font(config.sqlFont)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.primary.opacity(0.04))
                .clipShape(RoundedRectangle(cornerRadius: 6))
        } label: {
            Label("SQL Query", systemImage: "chevron.left.forwardslash.chevron.right")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Styling Helpers

    private var bubbleShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: config.bubbleCornerRadius, style: .continuous)
    }

    @ViewBuilder
    private var bubbleBackground: some View {
        switch message.role {
        case .user:
            config.userBubbleColor
        case .assistant:
            config.assistantBubbleColor
        case .error:
            config.errorColor.opacity(0.1)
        }
    }
}
