// MockLanguageModel.swift
// SwiftDBAI Tests
//
// A mock LanguageModel for unit tests that returns canned responses.

import AnyLanguageModel
import Foundation

/// A mock language model that returns a configurable canned response.
///
/// Used in tests to avoid hitting a real LLM provider.
struct MockLanguageModel: LanguageModel {
    typealias UnavailableReason = Never

    /// The text the mock will return from `respond(...)`.
    let responseText: String

    init(responseText: String = "Mock summary response.") {
        self.responseText = responseText
    }

    func respond<Content>(
        within session: LanguageModelSession,
        to prompt: Prompt,
        generating type: Content.Type,
        includeSchemaInPrompt: Bool,
        options: GenerationOptions
    ) async throws -> LanguageModelSession.Response<Content> where Content: Generable {
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
        let rawContent = GeneratedContent(kind: .string(responseText))
        let content = try! Content(rawContent)
        return LanguageModelSession.ResponseStream(content: content, rawContent: rawContent)
    }
}
