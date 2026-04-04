// DatabaseSeeder.swift
// SwiftDBAIDemo
//
// Copies the bundled GitHub stars database to the Documents directory.
// The database contains real star counts for ~2000 top GitHub repos,
// fetched live from the GitHub API.

import Foundation

enum DatabaseSeeder {

    /// Returns the path to the GitHub stars database, copying from bundle if needed.
    static func seedIfNeeded() throws -> String {
        let url = URL.documentsDirectory.appending(path: "github_stars.sqlite")
        let path = url.path(percentEncoded: false)

        // If the database already exists, just return the path.
        if FileManager.default.fileExists(atPath: path) {
            return path
        }

        // Copy bundled database to Documents
        guard let bundledURL = Bundle.main.url(forResource: "github_stars", withExtension: "sqlite") else {
            throw SeederError.bundledDatabaseNotFound
        }

        try FileManager.default.copyItem(at: bundledURL, to: url)
        return path
    }

    enum SeederError: LocalizedError {
        case bundledDatabaseNotFound

        var errorDescription: String? {
            "Could not find github_stars.sqlite in app bundle."
        }
    }
}
