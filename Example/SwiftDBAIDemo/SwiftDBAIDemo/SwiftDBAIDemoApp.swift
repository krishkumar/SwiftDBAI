// SwiftDBAIDemoApp.swift
// SwiftDBAIDemo
//
// A minimal demo app showing DataChatView with a seeded SQLite database.

import SwiftUI
import SwiftDBAI

@main
struct SwiftDBAIDemoApp: App {
    @State private var databasePath: String?
    @State private var setupError: String?

    var body: some Scene {
        WindowGroup {
            Group {
                if let path = databasePath {
                    DataChatView(
                        databasePath: path,
                        model: DemoLanguageModel(),
                        allowlist: .readOnly,
                        additionalContext: """
                            This is a database of the top ~2000 most-starred GitHub \
                            repositories. Each repo has: full_name (owner/name), stars, \
                            forks, language (programming language), description, \
                            open_issues, created_at date, and topics. \
                            Star counts are real and current as of April 2026.
                            """
                    )
                } else if let error = setupError {
                    ContentUnavailableView(
                        "Database Setup Failed",
                        systemImage: "exclamationmark.triangle",
                        description: Text(error)
                    )
                } else {
                    ProgressView("Setting up database...")
                }
            }
            .task {
                do {
                    let path = try DatabaseSeeder.seedIfNeeded()
                    databasePath = path
                } catch {
                    setupError = error.localizedDescription
                }
            }
        }
    }
}
