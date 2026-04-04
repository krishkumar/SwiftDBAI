// DemoLanguageModel.swift
// SwiftDBAIDemo
//
// A mock LanguageModel that returns canned SQL for common GitHub repo queries.
// Pattern-matches natural language questions about GitHub stars, languages,
// and repository metadata.

import AnyLanguageModel
import Foundation

struct DemoLanguageModel: LanguageModel {
    typealias UnavailableReason = Never

    func respond<Content>(
        within session: LanguageModelSession,
        to prompt: Prompt,
        generating type: Content.Type,
        includeSchemaInPrompt: Bool,
        options: GenerationOptions
    ) async throws -> LanguageModelSession.Response<Content> where Content: Generable {
        let promptText = prompt.description.lowercased()
        let responseText: String

        if promptText.contains("row") && (promptText.contains("column") || promptText.contains("|")) {
            responseText = deriveSummary(from: prompt.description)
        } else {
            responseText = deriveSQL(from: promptText)
        }

        let rawContent = GeneratedContent(kind: .string(responseText))
        let content = try Content(rawContent)
        return LanguageModelSession.Response(
            content: content,
            rawContent: rawContent,
            transcriptEntries: [][...]
        )
    }

    func streamResponse<Content>(
        within session: LanguageModelSession,
        to prompt: Prompt,
        generating type: Content.Type,
        includeSchemaInPrompt: Bool,
        options: GenerationOptions
    ) -> sending LanguageModelSession.ResponseStream<Content> where Content: Generable {
        let rawContent = GeneratedContent(kind: .string("SELECT full_name, stars FROM repos ORDER BY stars DESC LIMIT 10"))
        let content = try! Content(rawContent)
        return LanguageModelSession.ResponseStream(content: content, rawContent: rawContent)
    }

    // MARK: - SQL Pattern Matching

    private func deriveSQL(from prompt: String) -> String {
        let q = extractLastQuestion(from: prompt)

        // Specific repo lookups
        if q.contains("react") && !q.contains("react-native") && !q.contains("react native") {
            return "SELECT full_name, stars, forks, language, description FROM repos WHERE name = 'react' OR full_name LIKE '%/react' ORDER BY stars DESC LIMIT 5"
        }

        // How many stars does X have
        if q.contains("how many stars") || q.contains("stars does") || q.contains("stars for") {
            return "SELECT full_name, stars, forks, language FROM repos ORDER BY stars DESC LIMIT 10"
        }

        // Language breakdown MUST come before "most popular" to avoid collision
        if q.contains("language") && (q.contains("breakdown") || q.contains("distribution") || q.contains("popular") || q.contains("most")) {
            return """
                SELECT language, COUNT(*) AS repo_count,
                       SUM(stars) AS total_stars,
                       ROUND(AVG(stars)) AS avg_stars
                FROM repos WHERE language IS NOT NULL AND language != ''
                GROUP BY language
                ORDER BY total_stars DESC
                LIMIT 15
                """
        }

        // Most starred / top repos
        if q.contains("most starred") || q.contains("most popular") || q.contains("top repo") || q.contains("top 10") || q.contains("most stars") {
            return """
                SELECT full_name, stars, forks, language
                FROM repos ORDER BY stars DESC LIMIT 10
                """
        }

        // Language-specific queries
        if q.contains("python") && (q.contains("repo") || q.contains("project")) {
            return """
                SELECT full_name, stars, forks, description
                FROM repos WHERE language = 'Python'
                ORDER BY stars DESC LIMIT 10
                """
        }
        if q.contains("swift") && (q.contains("repo") || q.contains("project")) {
            return """
                SELECT full_name, stars, forks, description
                FROM repos WHERE language = 'Swift'
                ORDER BY stars DESC LIMIT 10
                """
        }
        if q.contains("rust") && (q.contains("repo") || q.contains("project")) {
            return """
                SELECT full_name, stars, forks, description
                FROM repos WHERE language = 'Rust'
                ORDER BY stars DESC LIMIT 10
                """
        }
        if q.contains("typescript") && (q.contains("repo") || q.contains("project")) {
            return """
                SELECT full_name, stars, forks, description
                FROM repos WHERE language = 'TypeScript'
                ORDER BY stars DESC LIMIT 10
                """
        }

        // Count queries
        if q.contains("how many repo") || q.contains("how many project") || q.contains("total repo") {
            return "SELECT COUNT(*) AS total_repos FROM repos"
        }
        if q.contains("how many language") {
            return "SELECT COUNT(DISTINCT language) AS total_languages FROM repos WHERE language IS NOT NULL AND language != ''"
        }

        // Stars threshold queries
        if q.contains("100k") || q.contains("100,000") || q.contains("100000") {
            return """
                SELECT full_name, stars, language
                FROM repos WHERE stars > 100000
                ORDER BY stars DESC
                """
        }

        // Forks
        if q.contains("most forked") || q.contains("most forks") {
            return """
                SELECT full_name, forks, stars, language
                FROM repos ORDER BY forks DESC LIMIT 10
                """
        }

        // Created / oldest / newest
        if q.contains("oldest") || q.contains("first") {
            return """
                SELECT full_name, created_at, stars, language
                FROM repos ORDER BY created_at ASC LIMIT 10
                """
        }
        if q.contains("newest") || q.contains("recent") || q.contains("latest") {
            return """
                SELECT full_name, created_at, stars, language
                FROM repos ORDER BY created_at DESC LIMIT 10
                """
        }

        // Microsoft / Google / Meta specific
        if q.contains("microsoft") {
            return """
                SELECT full_name, stars, forks, language
                FROM repos WHERE owner = 'microsoft'
                ORDER BY stars DESC
                """
        }
        if q.contains("google") {
            return """
                SELECT full_name, stars, forks, language
                FROM repos WHERE owner = 'google'
                ORDER BY stars DESC
                """
        }
        if q.contains("facebook") || q.contains("meta") {
            return """
                SELECT full_name, stars, forks, language
                FROM repos WHERE owner = 'facebook'
                ORDER BY stars DESC
                """
        }

        // Compare
        if q.contains("vs") || q.contains("versus") || q.contains("compare") {
            return """
                SELECT full_name, stars, forks, language
                FROM repos ORDER BY stars DESC LIMIT 20
                """
        }

        // Default
        return """
            SELECT full_name, stars, language
            FROM repos ORDER BY stars DESC LIMIT 10
            """
    }

    private func extractLastQuestion(from prompt: String) -> String {
        let lines = prompt.components(separatedBy: "\n")
        // First pass: find lines ending with "?" (most likely user questions)
        // Take the LAST one (most recent question)
        var lastQuestion: String?
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasSuffix("?") && trimmed.count < 200 && trimmed.count > 5 {
                lastQuestion = trimmed.lowercased()
            }
        }
        if let q = lastQuestion { return q }

        // Fallback: walk backwards looking for short non-SQL lines
        for line in lines.reversed() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, trimmed.count > 3, trimmed.count < 100 else { continue }
            let lower = trimmed.lowercased()
            if lower.hasPrefix("select ") || lower.hasPrefix("create ") { continue }
            if lower.contains("integer") || lower.contains("text not") { continue }
            if lower.contains("respond with only") { continue }
            return lower
        }
        return prompt.lowercased()
    }

    // MARK: - Summary Generation

    private func deriveSummary(from rawPrompt: String) -> String {
        let lines = rawPrompt.components(separatedBy: "\n")
        let dataLines = lines.filter { $0.contains("|") || $0.contains(",") }
        let rowCount = max(dataLines.count - 1, 0)
        let lower = rawPrompt.lowercased()

        if lower.contains("total_repos") || lower.contains("total_languages") || lower.contains("count(") {
            if let countLine = dataLines.last {
                let num = countLine.trimmingCharacters(in: .whitespacesAndNewlines)
                    .components(separatedBy: "|").last?
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? "\(rowCount)"
                return "The count is \(num)."
            }
        }
        if lower.contains("avg_stars") || lower.contains("group by") || lower.contains("total_stars") {
            return "Here's the breakdown across programming languages."
        }
        if lower.contains("forks") && lower.contains("order by forks") {
            return "These are the most forked repositories on GitHub."
        }
        if rowCount == 0 {
            return "No repositories matched your query."
        }
        if rowCount == 1 {
            return "Here's what I found."
        }
        if rowCount <= 5 {
            return "Found \(rowCount) repositories."
        }
        return "Here are the top \(rowCount) repositories."
    }
}
