// ChatViewConfigurationKey.swift
// SwiftDBAI
//
// SwiftUI environment key for propagating ChatViewConfiguration
// through the view hierarchy.

import SwiftUI

/// Environment key that stores the ``ChatViewConfiguration``.
@available(iOS 17.0, macOS 14.0, visionOS 1.0, *)
struct ChatViewConfigurationKey: EnvironmentKey {
    static let defaultValue = ChatViewConfiguration.default
}

@available(iOS 17.0, macOS 14.0, visionOS 1.0, *)
extension EnvironmentValues {
    /// The chat view configuration for the current environment.
    var chatViewConfiguration: ChatViewConfiguration {
        get { self[ChatViewConfigurationKey.self] }
        set { self[ChatViewConfigurationKey.self] = newValue }
    }
}

@available(iOS 17.0, macOS 14.0, visionOS 1.0, *)
extension View {
    /// Applies a ``ChatViewConfiguration`` to this view and its descendants.
    ///
    /// ```swift
    /// DataChatView(databasePath: path, model: myLLM)
    ///     .chatViewConfiguration(.dark)
    /// ```
    public func chatViewConfiguration(_ config: ChatViewConfiguration) -> some View {
        environment(\.chatViewConfiguration, config)
    }
}
