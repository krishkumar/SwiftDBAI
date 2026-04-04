// ChatViewConfigurationTests.swift
// SwiftDBAITests
//
// Tests for ChatViewConfiguration defaults, presets, and environment propagation.

import Testing
import SwiftUI
@testable import SwiftDBAI

@Suite("ChatViewConfiguration Tests")
struct ChatViewConfigurationTests {

    // MARK: - Default Values

    @Test("Default configuration has expected color values")
    func defaultColors() {
        let config = ChatViewConfiguration.default
        #expect(config.userBubbleColor == .accentColor)
        #expect(config.userTextColor == .white)
        #expect(config.assistantTextColor == .primary)
        #expect(config.backgroundColor == .clear)
        #expect(config.inputBarBackgroundColor == .clear)
        #expect(config.accentColor == .accentColor)
        #expect(config.errorColor == .red)
    }

    @Test("Default configuration has expected typography values")
    func defaultTypography() {
        let config = ChatViewConfiguration.default
        #expect(config.messageFont == .body)
        #expect(config.summaryFont == .body)
        #expect(config.sqlFont == .system(.caption, design: .monospaced))
        #expect(config.inputFont == .body)
    }

    @Test("Default configuration has expected layout values")
    func defaultLayout() {
        let config = ChatViewConfiguration.default
        #expect(config.messagePadding == 14)
        #expect(config.bubbleCornerRadius == 16)
        #expect(config.showTimestamps == false)
        #expect(config.showSQLDisclosure == true)
        #expect(config.inputPlaceholder == "Ask about your data\u{2026}")
        #expect(config.emptyStateTitle == "Ask a question about your data")
        #expect(config.emptyStateSubtitle == "Try something like \"How many records are in the database?\"")
        #expect(config.emptyStateIcon == "bubble.left.and.text.bubble.right")
    }

    // MARK: - Compact Preset

    @Test("Compact preset has smaller fonts and tighter padding")
    func compactPreset() {
        let config = ChatViewConfiguration.compact
        #expect(config.messageFont == .footnote)
        #expect(config.summaryFont == .footnote)
        #expect(config.sqlFont == .system(.caption2, design: .monospaced))
        #expect(config.inputFont == .footnote)
        #expect(config.messagePadding == 8)
        #expect(config.bubbleCornerRadius == 10)
        #expect(config.showTimestamps == false)
        #expect(config.showSQLDisclosure == false)
    }

    // MARK: - Dark Preset

    @Test("Dark preset has dark-themed colors")
    func darkPreset() {
        let config = ChatViewConfiguration.dark
        #expect(config.userBubbleColor == Color(white: 0.25))
        #expect(config.userTextColor == .white)
        #expect(config.assistantBubbleColor == Color(white: 0.15))
        #expect(config.assistantTextColor == Color(white: 0.9))
        #expect(config.backgroundColor == .black)
        #expect(config.inputBarBackgroundColor == Color(white: 0.1))
        #expect(config.accentColor == .blue)
        #expect(config.errorColor == Color(red: 1.0, green: 0.4, blue: 0.4))
    }

    // MARK: - Mutability

    @Test("Configuration properties can be mutated individually")
    func mutateProperties() {
        var config = ChatViewConfiguration.default
        config.userBubbleColor = .purple
        config.inputPlaceholder = "Ask about your recipes..."
        config.bubbleCornerRadius = 20
        config.showTimestamps = true

        #expect(config.userBubbleColor == .purple)
        #expect(config.inputPlaceholder == "Ask about your recipes...")
        #expect(config.bubbleCornerRadius == 20)
        #expect(config.showTimestamps == true)
        // Other properties remain at defaults
        #expect(config.userTextColor == .white)
        #expect(config.messageFont == .body)
    }

    // MARK: - All Public Properties Accessible

    @Test("All public properties are readable and writable")
    func allPropertiesAccessible() {
        var config = ChatViewConfiguration.default

        // Colors
        _ = config.userBubbleColor
        _ = config.userTextColor
        _ = config.assistantBubbleColor
        _ = config.assistantTextColor
        _ = config.backgroundColor
        _ = config.inputBarBackgroundColor
        _ = config.accentColor
        _ = config.errorColor

        // Typography
        _ = config.messageFont
        _ = config.summaryFont
        _ = config.sqlFont
        _ = config.inputFont

        // Layout
        _ = config.messagePadding
        _ = config.bubbleCornerRadius
        _ = config.showTimestamps
        _ = config.showSQLDisclosure
        _ = config.inputPlaceholder
        _ = config.emptyStateTitle
        _ = config.emptyStateSubtitle
        _ = config.emptyStateIcon

        // Verify write access compiles (set and read back)
        config.userBubbleColor = .green
        #expect(config.userBubbleColor == .green)

        config.emptyStateIcon = "star"
        #expect(config.emptyStateIcon == "star")
    }

    // MARK: - Presets Are Static

    @Test("Static presets are available as expected")
    func staticPresets() {
        let _ = ChatViewConfiguration.default
        let _ = ChatViewConfiguration.compact
        let _ = ChatViewConfiguration.dark
    }

    // MARK: - Sendable Conformance

    @Test("Configuration is Sendable")
    func sendableConformance() async {
        let config = ChatViewConfiguration.default
        // Verify Sendable by passing across isolation boundary
        let result: ChatViewConfiguration = await Task.detached {
            return config
        }.value
        #expect(result.bubbleCornerRadius == config.bubbleCornerRadius)
    }

    // MARK: - Environment Propagation

    @Test("Environment key default value matches ChatViewConfiguration.default")
    func environmentKeyDefault() {
        let defaultConfig = ChatViewConfiguration.default
        let envDefault = ChatViewConfigurationKey.defaultValue
        #expect(defaultConfig.bubbleCornerRadius == envDefault.bubbleCornerRadius)
        #expect(defaultConfig.messagePadding == envDefault.messagePadding)
        #expect(defaultConfig.showSQLDisclosure == envDefault.showSQLDisclosure)
        #expect(defaultConfig.inputPlaceholder == envDefault.inputPlaceholder)
    }
}
