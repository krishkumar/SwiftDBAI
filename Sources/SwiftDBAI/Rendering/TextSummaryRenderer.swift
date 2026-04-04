// TextSummaryRenderer.swift
// SwiftDBAI
//
// Converts raw SQL query results into natural language text summaries
// using the LLM via AnyLanguageModel.

import AnyLanguageModel
import Foundation

/// Renders SQL query results as natural language text summaries.
///
/// The renderer takes a `QueryResult` and the user's original question,
/// sends them to the LLM for summarization, and returns a concise,
/// human-readable response.
///
/// Usage:
/// ```swift
/// let renderer = TextSummaryRenderer(model: myModel)
/// let summary = try await renderer.summarize(
///     result: queryResult,
///     userQuestion: "How many orders were placed last month?"
/// )
/// print(summary) // "There were 42 orders placed last month."
/// ```
public struct TextSummaryRenderer: Sendable {

    /// The language model used to generate summaries.
    private let model: any LanguageModel

    /// Maximum number of rows to include in the LLM prompt.
    ///
    /// Results larger than this are truncated with a note about total count.
    public let maxRowsInPrompt: Int

    /// Creates a new text summary renderer.
    ///
    /// - Parameters:
    ///   - model: Any `AnyLanguageModel`-compatible language model.
    ///   - maxRowsInPrompt: Maximum rows to send to the LLM for summarization (default: 50).
    public init(model: any LanguageModel, maxRowsInPrompt: Int = 50) {
        self.model = model
        self.maxRowsInPrompt = maxRowsInPrompt
    }

    /// Generates a natural language summary of query results.
    ///
    /// - Parameters:
    ///   - result: The raw `QueryResult` from SQL execution.
    ///   - userQuestion: The original natural language question from the user.
    ///   - context: Optional additional context (e.g., table descriptions) to help the LLM.
    /// - Returns: A natural language text summary of the results.
    public func summarize(
        result: QueryResult,
        userQuestion: String,
        context: String? = nil
    ) async throws -> String {
        // For mutation results (INSERT/UPDATE/DELETE), use a simple template
        if let affected = result.rowsAffected {
            return summarizeMutation(result: result, affected: affected)
        }

        // For empty results, no need to call the LLM
        if result.rows.isEmpty {
            return "No results found for your query."
        }

        // For simple aggregates, produce a direct answer without LLM
        if let directAnswer = tryDirectAggregateSummary(result: result, userQuestion: userQuestion) {
            return directAnswer
        }

        // Build the prompt and ask the LLM to summarize
        let prompt = buildSummarizationPrompt(
            result: result,
            userQuestion: userQuestion,
            context: context
        )

        let session = LanguageModelSession(
            model: model,
            instructions: summaryInstructions
        )

        let response = try await session.respond(to: prompt)
        return response.content.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Generates a summary without calling the LLM, using simple templates.
    ///
    /// Useful when LLM access is unavailable, or for fast local rendering.
    ///
    /// - Parameters:
    ///   - result: The raw `QueryResult` from SQL execution.
    ///   - userQuestion: The original natural language question.
    /// - Returns: A template-based text summary.
    public func localSummary(result: QueryResult, userQuestion: String) -> String {
        if let affected = result.rowsAffected {
            return summarizeMutation(result: result, affected: affected)
        }

        if result.rows.isEmpty {
            return "No results found for your query."
        }

        if let directAnswer = tryDirectAggregateSummary(result: result, userQuestion: userQuestion) {
            return directAnswer
        }

        return buildTemplateSummary(result: result)
    }

    // MARK: - Private Helpers

    /// System instructions for the summarization session.
    private var summaryInstructions: String {
        """
        You are a data assistant that summarizes SQL query results in natural language.

        Rules:
        - Be concise and direct. Answer the user's question first, then add detail if helpful.
        - Use natural language, not SQL or code.
        - For numeric results, include the exact numbers.
        - For lists of records, summarize the count and highlight notable items.
        - If the data contains dates, format them in a readable way.
        - Do not mention SQL, databases, tables, columns, or queries in your response.
        - Do not include markdown formatting.
        - Keep your response under 3 sentences for simple results, under 5 for complex ones.
        """
    }

    /// Builds the prompt sent to the LLM for summarization.
    private func buildSummarizationPrompt(
        result: QueryResult,
        userQuestion: String,
        context: String?
    ) -> String {
        var parts: [String] = []

        parts.append("User's question: \(userQuestion)")

        if let context {
            parts.append("Context: \(context)")
        }

        parts.append("Query returned \(result.rowCount) row(s) with columns: \(result.columns.joined(separator: ", "))")

        // Include the result data (truncated if large)
        let dataStr = formatResultData(result)
        parts.append("Data:\n\(dataStr)")

        parts.append("Summarize these results in natural language, directly answering the user's question.")

        return parts.joined(separator: "\n\n")
    }

    /// Formats the query result data as a compact table for the LLM prompt.
    private func formatResultData(_ result: QueryResult) -> String {
        let rowsToInclude = Array(result.rows.prefix(maxRowsInPrompt))
        var lines: [String] = []

        // Header
        lines.append(result.columns.joined(separator: " | "))

        // Rows
        for row in rowsToInclude {
            let values = result.columns.map { col in
                row[col]?.description ?? "NULL"
            }
            lines.append(values.joined(separator: " | "))
        }

        if result.rowCount > maxRowsInPrompt {
            lines.append("(\(result.rowCount - maxRowsInPrompt) additional rows not shown)")
        }

        return lines.joined(separator: "\n")
    }

    /// Produces a direct answer for simple aggregate queries (1 row, few columns).
    private func tryDirectAggregateSummary(result: QueryResult, userQuestion: String) -> String? {
        guard result.isAggregate else { return nil }

        let row = result.rows[0]

        // Single numeric column — e.g., "COUNT(*)" → "42"
        if result.columns.count == 1 {
            let col = result.columns[0]
            guard let value = row[col] else { return nil }
            let formatted = formatNumber(value)
            return "The result is \(formatted)."
        }

        // Multiple aggregate columns — e.g., COUNT, AVG, SUM
        let parts = result.columns.compactMap { col -> String? in
            guard let value = row[col] else { return nil }
            let label = humanizeColumnName(col)
            let formatted = formatNumber(value)
            return "\(label): \(formatted)"
        }
        return parts.joined(separator: ", ") + "."
    }

    /// Formats a numeric Value for display.
    private func formatNumber(_ value: QueryResult.Value) -> String {
        switch value {
        case .integer(let i):
            return NumberFormatter.localizedString(from: NSNumber(value: i), number: .decimal)
        case .real(let d):
            if d == d.rounded() && abs(d) < 1e12 {
                return NumberFormatter.localizedString(from: NSNumber(value: Int64(d)), number: .decimal)
            }
            let formatter = NumberFormatter()
            formatter.numberStyle = .decimal
            formatter.maximumFractionDigits = 2
            return formatter.string(from: NSNumber(value: d)) ?? String(d)
        default:
            return value.description
        }
    }

    /// Converts a column name like "total_count" or "AVG(price)" into a readable label.
    private func humanizeColumnName(_ name: String) -> String {
        // Handle SQL function names: "COUNT(*)" → "count", "AVG(price)" → "average price"
        let functionPatterns: [(pattern: String, label: String)] = [
            ("COUNT", "count"),
            ("SUM", "total"),
            ("AVG", "average"),
            ("MIN", "minimum"),
            ("MAX", "maximum"),
        ]

        let upper = name.uppercased()
        for (pattern, label) in functionPatterns {
            if upper.hasPrefix(pattern + "(") {
                // Extract the inner column name
                let start = name.index(name.startIndex, offsetBy: pattern.count + 1)
                let end = name.index(before: name.endIndex)
                if start < end {
                    let inner = String(name[start..<end])
                    if inner == "*" { return label }
                    return "\(label) \(humanizeColumnName(inner))"
                }
                return label
            }
        }

        // snake_case → space-separated
        return name
            .replacingOccurrences(of: "_", with: " ")
            .lowercased()
    }

    /// Produces a template-based summary without calling the LLM.
    private func buildTemplateSummary(result: QueryResult) -> String {
        let count = result.rowCount

        if count == 1 {
            // Single record — list field values
            let row = result.rows[0]
            let details = result.columns.prefix(5).compactMap { col -> String? in
                guard let val = row[col], !val.isNull else { return nil }
                return "\(humanizeColumnName(col)): \(val.description)"
            }
            return "Found 1 result. \(details.joined(separator: ", "))."
        }

        // Multiple records
        var summary = "Found \(count) results"

        // If there's a clear "name" or "title" column, list first few
        let nameColumns = ["name", "title", "label", "description"]
        if let nameCol = result.columns.first(where: { nameColumns.contains($0.lowercased()) }) {
            let names = result.rows.prefix(3).compactMap { $0[nameCol]?.description }
            if !names.isEmpty {
                summary += " including \(names.joined(separator: ", "))"
                if count > 3 { summary += ", and \(count - 3) more" }
            }
        }

        return summary + "."
    }

    /// Summarizes a mutation (INSERT/UPDATE/DELETE) result.
    private func summarizeMutation(result: QueryResult, affected: Int) -> String {
        let sql = result.sql.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()

        let operation: String
        if sql.hasPrefix("INSERT") {
            operation = "inserted"
        } else if sql.hasPrefix("UPDATE") {
            operation = "updated"
        } else if sql.hasPrefix("DELETE") {
            operation = "deleted"
        } else {
            operation = "affected"
        }

        let noun = affected == 1 ? "row" : "rows"
        return "Successfully \(operation) \(affected) \(noun)."
    }
}
