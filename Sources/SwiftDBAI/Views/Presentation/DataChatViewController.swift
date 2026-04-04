// DataChatViewController.swift
// SwiftDBAI
//
// UIKit bridge: a UIHostingController subclass for presenting DataChatSheet
// in UIKit-based apps via modal presentation or navigation push.

#if canImport(UIKit) && !os(watchOS)
import AnyLanguageModel
import GRDB
import SwiftUI
import UIKit

/// A `UIHostingController` subclass that wraps ``DataChatSheet`` for UIKit apps.
///
/// Present modally:
/// ```swift
/// let vc = DataChatViewController(databasePath: path, model: myLLM)
/// present(vc, animated: true)
/// ```
///
/// Or push onto a navigation stack:
/// ```swift
/// let vc = DataChatViewController(databasePath: path, model: myLLM)
/// navigationController?.pushViewController(vc, animated: true)
/// ```
@available(iOS 17.0, visionOS 1.0, *)
public final class DataChatViewController: UIHostingController<DataChatSheet> {

    /// Creates a DataChatViewController from a database file path and language model.
    ///
    /// - Parameters:
    ///   - databasePath: Absolute path to a SQLite database file.
    ///   - model: Any `AnyLanguageModel`-compatible language model instance.
    ///   - allowlist: SQL operations the LLM may generate. Defaults to `.readOnly`.
    ///   - additionalContext: Optional extra context about the database for the LLM.
    ///   - title: Navigation bar title. Defaults to `"AI Chat"`.
    public convenience init(
        databasePath: String,
        model: any LanguageModel,
        allowlist: OperationAllowlist = .readOnly,
        additionalContext: String? = nil,
        title: String = "AI Chat"
    ) {
        let sheet = DataChatSheet(
            databasePath: databasePath,
            model: model,
            allowlist: allowlist,
            additionalContext: additionalContext,
            title: title
        )
        self.init(rootView: sheet)
        self.modalPresentationStyle = .formSheet
    }

    /// Creates a DataChatViewController from an existing GRDB database connection.
    ///
    /// - Parameters:
    ///   - database: A GRDB `DatabaseWriter` (`DatabasePool` or `DatabaseQueue`).
    ///   - model: Any `AnyLanguageModel`-compatible language model instance.
    ///   - allowlist: SQL operations the LLM may generate. Defaults to `.readOnly`.
    ///   - additionalContext: Optional extra context about the database for the LLM.
    ///   - title: Navigation bar title. Defaults to `"AI Chat"`.
    public convenience init(
        database: any DatabaseWriter,
        model: any LanguageModel,
        allowlist: OperationAllowlist = .readOnly,
        additionalContext: String? = nil,
        title: String = "AI Chat"
    ) {
        let sheet = DataChatSheet(
            database: database,
            model: model,
            allowlist: allowlist,
            additionalContext: additionalContext,
            title: title
        )
        self.init(rootView: sheet)
        self.modalPresentationStyle = .formSheet
    }
}
#endif
