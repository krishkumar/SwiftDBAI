// DataChatSheetModifier.swift
// SwiftDBAI
//
// View modifiers for presenting DataChatSheet as a sheet or full-screen cover.

import AnyLanguageModel
import GRDB
import SwiftUI

// MARK: - Sheet Modifier

/// A view modifier that presents a ``DataChatSheet`` as a standard sheet.
@available(iOS 17.0, macOS 14.0, visionOS 1.0, *)
struct DataChatSheetModifier: ViewModifier {
    @Binding var isPresented: Bool
    let databasePath: String
    let model: any LanguageModel
    var allowlist: OperationAllowlist
    var additionalContext: String?
    var title: String

    func body(content: Content) -> some View {
        content.sheet(isPresented: $isPresented) {
            DataChatSheet(
                databasePath: databasePath,
                model: model,
                allowlist: allowlist,
                additionalContext: additionalContext,
                title: title
            )
        }
    }
}

/// A view modifier that presents a ``DataChatSheet`` as a sheet using
/// an existing GRDB database connection.
@available(iOS 17.0, macOS 14.0, visionOS 1.0, *)
struct DataChatSheetDatabaseModifier: ViewModifier {
    @Binding var isPresented: Bool
    let database: any DatabaseWriter
    let model: any LanguageModel
    var allowlist: OperationAllowlist
    var additionalContext: String?
    var title: String

    func body(content: Content) -> some View {
        content.sheet(isPresented: $isPresented) {
            DataChatSheet(
                database: database,
                model: model,
                allowlist: allowlist,
                additionalContext: additionalContext,
                title: title
            )
        }
    }
}

// MARK: - Full-Screen Modifier

#if os(iOS) || os(visionOS)
/// A view modifier that presents a ``DataChatSheet`` as a full-screen cover.
@available(iOS 17.0, visionOS 1.0, *)
struct DataChatFullScreenModifier: ViewModifier {
    @Binding var isPresented: Bool
    let databasePath: String
    let model: any LanguageModel
    var allowlist: OperationAllowlist
    var additionalContext: String?
    var title: String

    func body(content: Content) -> some View {
        content.fullScreenCover(isPresented: $isPresented) {
            DataChatSheet(
                databasePath: databasePath,
                model: model,
                allowlist: allowlist,
                additionalContext: additionalContext,
                title: title
            )
        }
    }
}

/// A view modifier that presents a ``DataChatSheet`` as a full-screen cover
/// using an existing GRDB database connection.
@available(iOS 17.0, visionOS 1.0, *)
struct DataChatFullScreenDatabaseModifier: ViewModifier {
    @Binding var isPresented: Bool
    let database: any DatabaseWriter
    let model: any LanguageModel
    var allowlist: OperationAllowlist
    var additionalContext: String?
    var title: String

    func body(content: Content) -> some View {
        content.fullScreenCover(isPresented: $isPresented) {
            DataChatSheet(
                database: database,
                model: model,
                allowlist: allowlist,
                additionalContext: additionalContext,
                title: title
            )
        }
    }
}
#endif

// MARK: - View Extensions

@available(iOS 17.0, macOS 14.0, visionOS 1.0, *)
public extension View {

    /// Presents a database chat interface as a sheet.
    ///
    /// ```swift
    /// .dataChatSheet(
    ///     isPresented: $showChat,
    ///     databasePath: "/path/to/db.sqlite",
    ///     model: myLLM
    /// )
    /// ```
    func dataChatSheet(
        isPresented: Binding<Bool>,
        databasePath: String,
        model: any LanguageModel,
        allowlist: OperationAllowlist = .readOnly,
        additionalContext: String? = nil,
        title: String = "AI Chat"
    ) -> some View {
        modifier(DataChatSheetModifier(
            isPresented: isPresented,
            databasePath: databasePath,
            model: model,
            allowlist: allowlist,
            additionalContext: additionalContext,
            title: title
        ))
    }

    /// Presents a database chat interface as a sheet using an existing GRDB connection.
    func dataChatSheet(
        isPresented: Binding<Bool>,
        database: any DatabaseWriter,
        model: any LanguageModel,
        allowlist: OperationAllowlist = .readOnly,
        additionalContext: String? = nil,
        title: String = "AI Chat"
    ) -> some View {
        modifier(DataChatSheetDatabaseModifier(
            isPresented: isPresented,
            database: database,
            model: model,
            allowlist: allowlist,
            additionalContext: additionalContext,
            title: title
        ))
    }
}

#if os(iOS) || os(visionOS)
@available(iOS 17.0, visionOS 1.0, *)
public extension View {

    /// Presents a database chat interface as a full-screen cover.
    ///
    /// ```swift
    /// .dataChatFullScreen(
    ///     isPresented: $showChat,
    ///     databasePath: "/path/to/db.sqlite",
    ///     model: myLLM
    /// )
    /// ```
    func dataChatFullScreen(
        isPresented: Binding<Bool>,
        databasePath: String,
        model: any LanguageModel,
        allowlist: OperationAllowlist = .readOnly,
        additionalContext: String? = nil,
        title: String = "AI Chat"
    ) -> some View {
        modifier(DataChatFullScreenModifier(
            isPresented: isPresented,
            databasePath: databasePath,
            model: model,
            allowlist: allowlist,
            additionalContext: additionalContext,
            title: title
        ))
    }

    /// Presents a database chat interface as a full-screen cover using an existing GRDB connection.
    func dataChatFullScreen(
        isPresented: Binding<Bool>,
        database: any DatabaseWriter,
        model: any LanguageModel,
        allowlist: OperationAllowlist = .readOnly,
        additionalContext: String? = nil,
        title: String = "AI Chat"
    ) -> some View {
        modifier(DataChatFullScreenDatabaseModifier(
            isPresented: isPresented,
            database: database,
            model: model,
            allowlist: allowlist,
            additionalContext: additionalContext,
            title: title
        ))
    }
}
#endif
