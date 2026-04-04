// ChatViewConfiguration.swift
// SwiftDBAI
//
// A configuration struct that controls the visual appearance of ChatView
// and its child views. Propagated via SwiftUI environment.

import SwiftUI

/// Controls the visual appearance of the chat interface.
///
/// Use the built-in presets (`.default`, `.compact`, `.dark`) or create
/// a custom configuration by mutating the default:
///
/// ```swift
/// var config = ChatViewConfiguration.default
/// config.userBubbleColor = .purple
/// config.inputPlaceholder = "Ask about your recipes..."
///
/// DataChatView(databasePath: path, model: myLLM)
///     .chatViewConfiguration(config)
/// ```
@available(iOS 17.0, macOS 14.0, visionOS 1.0, *)
public struct ChatViewConfiguration: Sendable {

    // MARK: - Colors

    /// Background color for user message bubbles.
    public var userBubbleColor: Color

    /// Text color for user messages.
    public var userTextColor: Color

    /// Background color for assistant message bubbles.
    public var assistantBubbleColor: Color

    /// Text color for assistant messages.
    public var assistantTextColor: Color

    /// Background color for the overall chat view.
    public var backgroundColor: Color

    /// Background color for the input bar area.
    public var inputBarBackgroundColor: Color

    /// Accent color used for interactive elements (send button, etc.).
    public var accentColor: Color

    /// Color used for error-related UI elements.
    public var errorColor: Color

    // MARK: - Typography

    /// Font for chat message text.
    public var messageFont: Font

    /// Font for the natural language summary text.
    public var summaryFont: Font

    /// Font for SQL query display.
    public var sqlFont: Font

    /// Font for the text input field.
    public var inputFont: Font

    // MARK: - Layout

    /// Padding inside message bubbles.
    public var messagePadding: CGFloat

    /// Corner radius for message bubbles.
    public var bubbleCornerRadius: CGFloat

    /// Whether to show timestamps on messages.
    public var showTimestamps: Bool

    /// Whether to show the SQL disclosure group.
    public var showSQLDisclosure: Bool

    /// Placeholder text in the input field.
    public var inputPlaceholder: String

    /// Title text shown when the chat has no messages.
    public var emptyStateTitle: String

    /// Subtitle text shown when the chat has no messages.
    public var emptyStateSubtitle: String

    /// SF Symbol name for the empty state icon.
    public var emptyStateIcon: String

    /// Optional color scheme override. When set, forces the chat view to use
    /// this color scheme regardless of the system setting.
    public var colorSchemeOverride: ColorScheme?

    // MARK: - Avatar

    /// SF Symbol name for the assistant avatar. When set, shows a circular
    /// avatar next to assistant messages (e.g. "person.crop.circle.fill",
    /// "brain.head.profile", "sparkles").
    public var assistantAvatarIcon: String?

    /// Background color for the assistant avatar circle.
    public var assistantAvatarColor: Color

    // MARK: - Memberwise Initializer

    /// Creates a fully custom configuration.
    public init(
        userBubbleColor: Color = .accentColor,
        userTextColor: Color = .white,
        assistantBubbleColor: Color = defaultAssistantBackgroundColor,
        assistantTextColor: Color = .primary,
        backgroundColor: Color = .clear,
        inputBarBackgroundColor: Color = .clear,
        accentColor: Color = .accentColor,
        errorColor: Color = .red,
        messageFont: Font = .body,
        summaryFont: Font = .body,
        sqlFont: Font = .system(.caption, design: .monospaced),
        inputFont: Font = .body,
        messagePadding: CGFloat = 14,
        bubbleCornerRadius: CGFloat = 16,
        showTimestamps: Bool = false,
        showSQLDisclosure: Bool = true,
        inputPlaceholder: String = "Ask about your data\u{2026}",
        emptyStateTitle: String = "Ask a question about your data",
        emptyStateSubtitle: String = "Try something like \"How many records are in the database?\"",
        emptyStateIcon: String = "bubble.left.and.text.bubble.right",
        colorSchemeOverride: ColorScheme? = nil,
        assistantAvatarIcon: String? = nil,
        assistantAvatarColor: Color = .accentColor
    ) {
        self.userBubbleColor = userBubbleColor
        self.userTextColor = userTextColor
        self.assistantBubbleColor = assistantBubbleColor
        self.assistantTextColor = assistantTextColor
        self.backgroundColor = backgroundColor
        self.inputBarBackgroundColor = inputBarBackgroundColor
        self.accentColor = accentColor
        self.errorColor = errorColor
        self.messageFont = messageFont
        self.summaryFont = summaryFont
        self.sqlFont = sqlFont
        self.inputFont = inputFont
        self.messagePadding = messagePadding
        self.bubbleCornerRadius = bubbleCornerRadius
        self.showTimestamps = showTimestamps
        self.showSQLDisclosure = showSQLDisclosure
        self.inputPlaceholder = inputPlaceholder
        self.emptyStateTitle = emptyStateTitle
        self.emptyStateSubtitle = emptyStateSubtitle
        self.emptyStateIcon = emptyStateIcon
        self.colorSchemeOverride = colorSchemeOverride
        self.assistantAvatarIcon = assistantAvatarIcon
        self.assistantAvatarColor = assistantAvatarColor
    }

    // MARK: - Platform-Adaptive Defaults

    /// The default assistant bubble background, matching the platform convention.
    public static var defaultAssistantBackgroundColor: Color {
        #if os(macOS)
        Color(nsColor: .controlBackgroundColor)
        #else
        Color(uiColor: .secondarySystemGroupedBackground)
        #endif
    }

    // MARK: - Presets

    /// The default configuration, matching the original hardcoded ChatView styling.
    public static let `default` = ChatViewConfiguration()

    /// A compact configuration with smaller fonts, tighter padding, and minimal chrome.
    public static let compact = ChatViewConfiguration(
        messageFont: .footnote,
        summaryFont: .footnote,
        sqlFont: .system(.caption2, design: .monospaced),
        inputFont: .footnote,
        messagePadding: 8,
        bubbleCornerRadius: 10,
        showTimestamps: false,
        showSQLDisclosure: false,
        emptyStateTitle: "Ask a question",
        emptyStateSubtitle: ""
    )

    /// A dark-themed configuration with muted colors suitable for dark backgrounds.
    public static let dark = ChatViewConfiguration(
        userBubbleColor: Color(white: 0.25),
        userTextColor: .white,
        assistantBubbleColor: Color(white: 0.15),
        assistantTextColor: Color(white: 0.9),
        backgroundColor: .black,
        inputBarBackgroundColor: Color(white: 0.1),
        accentColor: .blue,
        errorColor: Color(red: 1.0, green: 0.4, blue: 0.4),
        colorSchemeOverride: .dark
    )
}
