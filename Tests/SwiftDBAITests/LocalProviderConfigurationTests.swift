// LocalProviderConfigurationTests.swift
// SwiftDBAI Tests
//
// Tests for local/self-hosted provider configurations (Ollama, llama.cpp):
// factory methods, endpoint discovery, connection handling, and model creation.

import AnyLanguageModel
import Foundation
import GRDB
@testable import SwiftDBAI
import Testing

@Suite("Local Provider Configuration")
struct LocalProviderConfigurationTests {

    // MARK: - Ollama Configuration

    @Test("Ollama configuration stores provider and model")
    func ollamaBasicConfiguration() {
        let config = ProviderConfiguration.ollama(model: "llama3.2")

        #expect(config.provider == .ollama)
        #expect(config.model == "llama3.2")
        #expect(config.baseURL == OllamaLanguageModel.defaultBaseURL)
    }

    @Test("Ollama configuration produces OllamaLanguageModel")
    func ollamaMakeModel() {
        let config = ProviderConfiguration.ollama(model: "qwen2.5")

        let model = config.makeModel()
        #expect(model is OllamaLanguageModel)
    }

    @Test("Ollama with custom base URL for remote instance")
    func ollamaCustomBaseURL() {
        let remoteURL = URL(string: "http://192.168.1.100:11434")!
        let config = ProviderConfiguration.ollama(
            model: "mistral",
            baseURL: remoteURL
        )

        #expect(config.baseURL == remoteURL)
        #expect(config.provider == .ollama)
        let model = config.makeModel()
        #expect(model is OllamaLanguageModel)
    }

    @Test("Ollama does not require an API key")
    func ollamaNoAPIKey() {
        let config = ProviderConfiguration.ollama(model: "llama3.2")

        // Ollama doesn't need an API key, so the key is empty
        #expect(config.apiKey == "")
        // hasValidAPIKey returns false because key is empty, but that's expected
        // for local providers — they don't need authentication
        #expect(!config.hasValidAPIKey)
    }

    @Test("Ollama model is available without API key")
    func ollamaModelAvailable() {
        let config = ProviderConfiguration.ollama(model: "llama3.2")
        let model = config.makeModel()
        #expect(model.isAvailable)
    }

    // MARK: - llama.cpp Configuration

    @Test("llama.cpp configuration stores provider and model")
    func llamaCppBasicConfiguration() {
        let config = ProviderConfiguration.llamaCpp(model: "my-model")

        #expect(config.provider == .llamaCpp)
        #expect(config.model == "my-model")
        #expect(config.baseURL == LocalProviderDiscovery.defaultLlamaCppURL)
    }

    @Test("llama.cpp uses 'default' model name by default")
    func llamaCppDefaultModel() {
        let config = ProviderConfiguration.llamaCpp()

        #expect(config.model == "default")
    }

    @Test("llama.cpp configuration produces OpenAILanguageModel (compatible API)")
    func llamaCppMakeModel() {
        let config = ProviderConfiguration.llamaCpp(model: "my-gguf")

        let model = config.makeModel()
        // llama.cpp uses OpenAI-compatible API
        #expect(model is OpenAILanguageModel)
    }

    @Test("llama.cpp with custom base URL")
    func llamaCppCustomBaseURL() {
        let customURL = URL(string: "http://localhost:9090")!
        let config = ProviderConfiguration.llamaCpp(
            model: "custom-model",
            baseURL: customURL
        )

        #expect(config.baseURL == customURL)
        let model = config.makeModel()
        #expect(model is OpenAILanguageModel)
    }

    @Test("llama.cpp with API key authentication")
    func llamaCppWithAPIKey() {
        let config = ProviderConfiguration.llamaCpp(
            model: "secured-model",
            apiKey: "my-secret-key"
        )

        #expect(config.apiKey == "my-secret-key")
        #expect(config.hasValidAPIKey)
    }

    @Test("llama.cpp without API key")
    func llamaCppNoAPIKey() {
        let config = ProviderConfiguration.llamaCpp(model: "open-model")

        #expect(config.apiKey == "")
    }

    // MARK: - Provider Enum

    @Test("Provider enum includes ollama and llamaCpp cases")
    func providerEnumHasLocalCases() {
        let cases = ProviderConfiguration.Provider.allCases
        #expect(cases.contains(.ollama))
        #expect(cases.contains(.llamaCpp))
        // Total: openAI, anthropic, gemini, openAICompatible, ollama, llamaCpp
        #expect(cases.count == 6)
    }

    // MARK: - fromEnvironment

    @Test("fromEnvironment creates Ollama configuration")
    func fromEnvironmentOllama() {
        let config = ProviderConfiguration.fromEnvironment(
            provider: .ollama,
            environmentVariable: "NONEXISTENT_OLLAMA_KEY",
            model: "llama3.2"
        )

        #expect(config.provider == .ollama)
        #expect(config.model == "llama3.2")
    }

    @Test("fromEnvironment creates llama.cpp configuration")
    func fromEnvironmentLlamaCpp() {
        let config = ProviderConfiguration.fromEnvironment(
            provider: .llamaCpp,
            environmentVariable: "NONEXISTENT_LLAMACPP_KEY",
            model: "default"
        )

        #expect(config.provider == .llamaCpp)
        #expect(config.model == "default")
    }

    // MARK: - ChatEngine Convenience Init with Local Providers

    @Test("ChatEngine can be created with Ollama provider")
    func chatEngineWithOllama() throws {
        let dbQueue = try GRDB.DatabaseQueue()
        let config = ProviderConfiguration.ollama(model: "llama3.2")
        let engine = ChatEngine(database: dbQueue, provider: config)

        #expect(engine.tableCount == nil) // schema not yet introspected
    }

    @Test("ChatEngine can be created with llama.cpp provider")
    func chatEngineWithLlamaCpp() throws {
        let dbQueue = try GRDB.DatabaseQueue()
        let config = ProviderConfiguration.llamaCpp()
        let engine = ChatEngine(database: dbQueue, provider: config)

        #expect(engine.tableCount == nil)
    }

    // MARK: - LocalProviderType

    @Test("LocalProviderType has expected raw values")
    func localProviderTypeRawValues() {
        #expect(LocalProviderType.ollama.rawValue == "ollama")
        #expect(LocalProviderType.llamaCpp.rawValue == "llama.cpp")
    }

    @Test("LocalProviderType CaseIterable includes both cases")
    func localProviderTypeCases() {
        let cases = LocalProviderType.allCases
        #expect(cases.count == 2)
        #expect(cases.contains(.ollama))
        #expect(cases.contains(.llamaCpp))
    }

    // MARK: - LocalProviderEndpoint

    @Test("LocalProviderEndpoint description includes status and model count")
    func endpointDescription() {
        let endpoint = LocalProviderEndpoint(
            baseURL: URL(string: "http://localhost:11434")!,
            providerType: .ollama,
            isReachable: true,
            availableModels: ["llama3.2", "qwen2.5"]
        )

        #expect(endpoint.description.contains("ollama"))
        #expect(endpoint.description.contains("reachable"))
        #expect(endpoint.description.contains("2 models"))
    }

    @Test("LocalProviderEndpoint shows unreachable when not connected")
    func endpointUnreachableDescription() {
        let endpoint = LocalProviderEndpoint(
            baseURL: URL(string: "http://localhost:8080")!,
            providerType: .llamaCpp,
            isReachable: false,
            availableModels: []
        )

        #expect(endpoint.description.contains("unreachable"))
        #expect(endpoint.description.contains("0 models"))
    }

    @Test("LocalProviderEndpoint equality works correctly")
    func endpointEquality() {
        let a = LocalProviderEndpoint(
            baseURL: URL(string: "http://localhost:11434")!,
            providerType: .ollama,
            isReachable: true,
            availableModels: ["llama3.2"]
        )
        let b = LocalProviderEndpoint(
            baseURL: URL(string: "http://localhost:11434")!,
            providerType: .ollama,
            isReachable: true,
            availableModels: ["llama3.2"]
        )
        let c = LocalProviderEndpoint(
            baseURL: URL(string: "http://localhost:11434")!,
            providerType: .ollama,
            isReachable: false,
            availableModels: []
        )

        #expect(a == b)
        #expect(a != c)
    }

    // MARK: - Discovery (No Local Server Running)

    @Test("Discovery returns unreachable when no server is running")
    func discoveryUnreachableEndpoint() async {
        // Use a port that's almost certainly not running anything
        let endpoint = await LocalProviderDiscovery.discover(
            providerType: .ollama,
            host: "127.0.0.1",
            port: 59999,
            timeout: 1
        )

        #expect(!endpoint.isReachable)
        #expect(endpoint.availableModels.isEmpty)
        #expect(endpoint.providerType == .ollama)
    }

    @Test("isOllamaRunning returns false for unreachable endpoint")
    func ollamaNotRunning() async {
        let unreachableURL = URL(string: "http://127.0.0.1:59998")!
        let running = await LocalProviderDiscovery.isOllamaRunning(
            at: unreachableURL,
            timeout: 1
        )

        #expect(!running)
    }

    @Test("isLlamaCppRunning returns false for unreachable endpoint")
    func llamaCppNotRunning() async {
        let unreachableURL = URL(string: "http://127.0.0.1:59997")!
        let running = await LocalProviderDiscovery.isLlamaCppRunning(
            at: unreachableURL,
            timeout: 1
        )

        #expect(!running)
    }

    @Test("listOllamaModels returns empty for unreachable endpoint")
    func ollamaModelsUnreachable() async {
        let unreachableURL = URL(string: "http://127.0.0.1:59996")!
        let models = await LocalProviderDiscovery.listOllamaModels(
            at: unreachableURL,
            timeout: 1
        )

        #expect(models.isEmpty)
    }

    @Test("listLlamaCppModels returns empty for unreachable endpoint")
    func llamaCppModelsUnreachable() async {
        let unreachableURL = URL(string: "http://127.0.0.1:59995")!
        let models = await LocalProviderDiscovery.listLlamaCppModels(
            at: unreachableURL,
            timeout: 1
        )

        #expect(models.isEmpty)
    }

    @Test("discoverAll returns endpoints for both provider types")
    func discoverAllReturnsAllProviders() async {
        // Use very short timeout since we likely don't have servers running
        let endpoints = await LocalProviderDiscovery.discoverAll(timeout: 0.5)

        // Should return exactly 2 endpoints (one per well-known provider)
        #expect(endpoints.count == 2)

        let types = Set(endpoints.map(\.providerType))
        #expect(types.contains(.ollama))
        #expect(types.contains(.llamaCpp))
    }

    // MARK: - Default URLs

    @Test("Default Ollama URL is correct")
    func defaultOllamaURL() {
        #expect(LocalProviderDiscovery.defaultOllamaURL.absoluteString == "http://localhost:11434")
    }

    @Test("Default llama.cpp URL is correct")
    func defaultLlamaCppURL() {
        #expect(LocalProviderDiscovery.defaultLlamaCppURL.absoluteString == "http://localhost:8080")
    }
}
