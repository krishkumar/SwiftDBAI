// StructuredSQLOutput.swift
// SwiftDBAI
//
// @Generable struct for structured SQL output from LLMs.
// When the LLM supports structured generation, this eliminates
// the need for text-based SQL parsing entirely.

import AnyLanguageModel

/// Structured output type for SQL generation.
/// Uses AnyLanguageModel's @Generable macro to constrain the LLM
/// to output valid JSON matching this schema, rather than free-form text.
@available(iOS 17.0, macOS 14.0, visionOS 1.0, *)
@Generable
struct StructuredSQLOutput {
    @Guide(description: "The SQL query to execute. Must be a valid SQLite SELECT statement. Do not include markdown, backticks, or explanations -- only the raw SQL.")
    var sql: String
}
