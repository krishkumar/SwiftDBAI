// OllamaWithSystemPrompt.swift
// SwiftDBAIDemo
//
// Wraps OllamaLanguageModel to prepend session instructions into the user
// prompt, working around AnyLanguageModel's Ollama adapter not forwarding
// system messages.

import AnyLanguageModel
import Foundation

/// Wrapper that injects session instructions into every Ollama request.
struct OllamaWithSystemPrompt: LanguageModel {
    typealias UnavailableReason = Never

    private let inner: OllamaLanguageModel

    init(baseURL: URL = OllamaLanguageModel.defaultBaseURL, model: String) {
        self.inner = OllamaLanguageModel(baseURL: baseURL, model: model)
    }

    func respond<Content>(
        within session: LanguageModelSession,
        to prompt: Prompt,
        generating type: Content.Type,
        includeSchemaInPrompt: Bool,
        options: GenerationOptions
    ) async throws -> LanguageModelSession.Response<Content> where Content: Generable {
        let userText = prompt.description
        let instructionText = session.instructions?.description ?? ""

        let combinedText: String
        if instructionText.isEmpty {
            combinedText = userText
        } else {
            combinedText = """
            [System Instructions]
            \(instructionText)

            [User Message]
            \(userText)
            """
        }

        let plainSession = LanguageModelSession(model: inner)
        let combinedPrompt = Prompt(combinedText)
        return try await inner.respond(
            within: plainSession,
            to: combinedPrompt,
            generating: type,
            includeSchemaInPrompt: includeSchemaInPrompt,
            options: options
        )
    }

    func streamResponse<Content>(
        within session: LanguageModelSession,
        to prompt: Prompt,
        generating type: Content.Type,
        includeSchemaInPrompt: Bool,
        options: GenerationOptions
    ) -> sending LanguageModelSession.ResponseStream<Content> where Content: Generable {
        inner.streamResponse(
            within: session,
            to: prompt,
            generating: type,
            includeSchemaInPrompt: includeSchemaInPrompt,
            options: options
        )
    }
}
