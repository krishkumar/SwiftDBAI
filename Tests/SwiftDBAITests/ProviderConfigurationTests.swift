// ProviderConfigurationTests.swift
// SwiftDBAI Tests
//
// Tests for ProviderConfiguration — verifying all cloud provider configurations
// produce valid LanguageModel instances with correct settings.

import AnyLanguageModel
import Foundation
@testable import SwiftDBAI
import Testing

@Suite("ProviderConfiguration")
struct ProviderConfigurationTests {

    // MARK: - OpenAI Configuration

    @Test("OpenAI configuration stores provider and model")
    func openAIBasicConfiguration() {
        let config = ProviderConfiguration.openAI(
            apiKey: "sk-test-key-123",
            model: "gpt-4o"
        )

        #expect(config.provider == .openAI)
        #expect(config.model == "gpt-4o")
        #expect(config.apiKey == "sk-test-key-123")
        #expect(config.hasValidAPIKey)
    }

    @Test("OpenAI configuration produces a valid LanguageModel")
    func openAIMakeModel() {
        let config = ProviderConfiguration.openAI(
            apiKey: "sk-test-key",
            model: "gpt-4o-mini"
        )

        let model = config.makeModel()
        #expect(model is OpenAILanguageModel)
    }

    @Test("OpenAI with custom base URL for compatible services")
    func openAICustomBaseURL() {
        let customURL = URL(string: "https://my-proxy.example.com/v1/")!
        let config = ProviderConfiguration.openAI(
            apiKey: "sk-proxy-key",
            model: "gpt-4o",
            baseURL: customURL
        )

        #expect(config.baseURL == customURL)
        let model = config.makeModel()
        #expect(model is OpenAILanguageModel)
    }

    @Test("OpenAI with Responses API variant")
    func openAIResponsesVariant() {
        let config = ProviderConfiguration.openAI(
            apiKey: "sk-test",
            model: "gpt-4o",
            variant: .responses
        )

        #expect(config.openAIVariant == .responses)
        let model = config.makeModel()
        #expect(model is OpenAILanguageModel)
    }

    @Test("OpenAI with dynamic key provider captures key by reference")
    func openAIDynamicKeyProvider() {
        nonisolated(unsafe) var currentKey = "sk-initial"
        let config = ProviderConfiguration.openAI(
            apiKeyProvider: { currentKey },
            model: "gpt-4o"
        )

        #expect(config.apiKey == "sk-initial")
        currentKey = "sk-rotated"
        #expect(config.apiKey == "sk-rotated")
    }

    // MARK: - Anthropic Configuration

    @Test("Anthropic configuration stores provider and model")
    func anthropicBasicConfiguration() {
        let config = ProviderConfiguration.anthropic(
            apiKey: "sk-ant-test-key",
            model: "claude-sonnet-4-20250514"
        )

        #expect(config.provider == .anthropic)
        #expect(config.model == "claude-sonnet-4-20250514")
        #expect(config.apiKey == "sk-ant-test-key")
        #expect(config.hasValidAPIKey)
    }

    @Test("Anthropic configuration produces a valid LanguageModel")
    func anthropicMakeModel() {
        let config = ProviderConfiguration.anthropic(
            apiKey: "sk-ant-test",
            model: "claude-sonnet-4-20250514"
        )

        let model = config.makeModel()
        #expect(model is AnthropicLanguageModel)
    }

    @Test("Anthropic with API version and betas")
    func anthropicWithVersionAndBetas() {
        let config = ProviderConfiguration.anthropic(
            apiKey: "sk-ant-test",
            model: "claude-sonnet-4-20250514",
            apiVersion: "2024-01-01",
            betas: ["computer-use"]
        )

        #expect(config.apiVersion == "2024-01-01")
        #expect(config.betas == ["computer-use"])
        let model = config.makeModel()
        #expect(model is AnthropicLanguageModel)
    }

    @Test("Anthropic with dynamic key provider captures key by reference")
    func anthropicDynamicKeyProvider() {
        nonisolated(unsafe) var currentKey = "sk-ant-initial"
        let config = ProviderConfiguration.anthropic(
            apiKeyProvider: { currentKey },
            model: "claude-sonnet-4-20250514"
        )

        #expect(config.apiKey == "sk-ant-initial")
        currentKey = "sk-ant-rotated"
        #expect(config.apiKey == "sk-ant-rotated")
    }

    // MARK: - Gemini Configuration

    @Test("Gemini configuration stores provider and model")
    func geminiBasicConfiguration() {
        let config = ProviderConfiguration.gemini(
            apiKey: "AIzaSyTest123",
            model: "gemini-2.0-flash"
        )

        #expect(config.provider == .gemini)
        #expect(config.model == "gemini-2.0-flash")
        #expect(config.apiKey == "AIzaSyTest123")
        #expect(config.hasValidAPIKey)
    }

    @Test("Gemini configuration produces a valid LanguageModel")
    func geminiMakeModel() {
        let config = ProviderConfiguration.gemini(
            apiKey: "AIzaSyTest",
            model: "gemini-2.0-flash"
        )

        let model = config.makeModel()
        #expect(model is GeminiLanguageModel)
    }

    @Test("Gemini with custom API version")
    func geminiCustomVersion() {
        let config = ProviderConfiguration.gemini(
            apiKey: "AIzaSyTest",
            model: "gemini-2.0-flash",
            apiVersion: "v1"
        )

        #expect(config.apiVersion == "v1")
        let model = config.makeModel()
        #expect(model is GeminiLanguageModel)
    }

    @Test("Gemini with dynamic key provider captures key by reference")
    func geminiDynamicKeyProvider() {
        nonisolated(unsafe) var currentKey = "AIza-initial"
        let config = ProviderConfiguration.gemini(
            apiKeyProvider: { currentKey },
            model: "gemini-2.0-flash"
        )

        #expect(config.apiKey == "AIza-initial")
        currentKey = "AIza-rotated"
        #expect(config.apiKey == "AIza-rotated")
    }

    // MARK: - OpenAI-Compatible Configuration

    @Test("OpenAI-compatible configuration with custom base URL")
    func openAICompatibleConfiguration() {
        let baseURL = URL(string: "https://api.together.xyz/v1/")!
        let config = ProviderConfiguration.openAICompatible(
            apiKey: "together-key",
            model: "meta-llama/Llama-3.1-70B",
            baseURL: baseURL
        )

        #expect(config.provider == .openAICompatible)
        #expect(config.model == "meta-llama/Llama-3.1-70B")
        #expect(config.baseURL == baseURL)
        let model = config.makeModel()
        #expect(model is OpenAILanguageModel)
    }

    @Test("OpenAI-compatible with dynamic key provider")
    func openAICompatibleDynamicKey() {
        let baseURL = URL(string: "http://localhost:1234/v1/")!
        nonisolated(unsafe) var currentKey = "local-key"
        let config = ProviderConfiguration.openAICompatible(
            apiKeyProvider: { currentKey },
            model: "local-model",
            baseURL: baseURL
        )

        #expect(config.apiKey == "local-key")
        currentKey = "new-local-key"
        #expect(config.apiKey == "new-local-key")
    }

    // MARK: - API Key Validation

    @Test("Empty API key reports invalid")
    func emptyAPIKeyInvalid() {
        let config = ProviderConfiguration.openAI(
            apiKey: "",
            model: "gpt-4o"
        )

        #expect(!config.hasValidAPIKey)
    }

    @Test("Whitespace-only API key reports invalid")
    func whitespaceAPIKeyInvalid() {
        let config = ProviderConfiguration.openAI(
            apiKey: "   \n\t  ",
            model: "gpt-4o"
        )

        #expect(!config.hasValidAPIKey)
    }

    @Test("Non-empty API key reports valid")
    func nonEmptyAPIKeyValid() {
        let config = ProviderConfiguration.openAI(
            apiKey: "x",
            model: "gpt-4o"
        )

        #expect(config.hasValidAPIKey)
    }

    // MARK: - Environment Variable Configuration

    @Test("fromEnvironment creates configuration for each provider")
    func fromEnvironmentCreatesConfig() {
        let openAI = ProviderConfiguration.fromEnvironment(
            provider: .openAI,
            environmentVariable: "SWIFTDAI_TEST_OPENAI_KEY",
            model: "gpt-4o"
        )
        #expect(openAI.provider == .openAI)
        #expect(openAI.model == "gpt-4o")

        let anthropic = ProviderConfiguration.fromEnvironment(
            provider: .anthropic,
            environmentVariable: "SWIFTDAI_TEST_ANTHROPIC_KEY",
            model: "claude-sonnet-4-20250514"
        )
        #expect(anthropic.provider == .anthropic)

        let gemini = ProviderConfiguration.fromEnvironment(
            provider: .gemini,
            environmentVariable: "SWIFTDAI_TEST_GEMINI_KEY",
            model: "gemini-2.0-flash"
        )
        #expect(gemini.provider == .gemini)
    }

    @Test("fromEnvironment returns empty key when variable not set")
    func fromEnvironmentMissingVariable() {
        let config = ProviderConfiguration.fromEnvironment(
            provider: .openAI,
            environmentVariable: "NONEXISTENT_KEY_VAR_SWIFTDBAI_TEST",
            model: "gpt-4o"
        )

        #expect(!config.hasValidAPIKey)
        #expect(config.apiKey == "")
    }

    // MARK: - Provider Enum

    @Test("Provider enum has all expected cases")
    func providerCases() {
        let cases = ProviderConfiguration.Provider.allCases
        #expect(cases.count == 6)
        #expect(cases.contains(.openAI))
        #expect(cases.contains(.anthropic))
        #expect(cases.contains(.gemini))
        #expect(cases.contains(.openAICompatible))
        #expect(cases.contains(.ollama))
        #expect(cases.contains(.llamaCpp))
    }

    // MARK: - Cross-Provider Model Creation

    @Test("All providers produce available models")
    func allProvidersCreateAvailableModels() {
        let configs: [ProviderConfiguration] = [
            .openAI(apiKey: "test", model: "gpt-4o"),
            .anthropic(apiKey: "test", model: "claude-sonnet-4-20250514"),
            .gemini(apiKey: "test", model: "gemini-2.0-flash"),
            .openAICompatible(
                apiKey: "test",
                model: "local",
                baseURL: URL(string: "http://localhost:8080/v1/")!
            ),
        ]

        for config in configs {
            let model = config.makeModel()
            #expect(model.isAvailable, "Model for \(config.provider) should be available")
        }
    }
}
