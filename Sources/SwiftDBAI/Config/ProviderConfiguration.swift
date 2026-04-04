// ProviderConfiguration.swift
// SwiftDBAI
//
// Unified provider configuration for cloud-based LLM providers.
// Wraps AnyLanguageModel provider types with convenient factory methods.

import AnyLanguageModel
import Foundation
import GRDB

/// Configuration for connecting to a cloud-based LLM provider.
///
/// `ProviderConfiguration` provides a unified way to configure any supported
/// LLM provider (OpenAI, Anthropic, Gemini, or OpenAI-compatible services).
/// Each configuration produces a properly configured `LanguageModel` instance
/// that works with ``ChatEngine`` and ``TextSummaryRenderer``.
///
/// ## Quick Start
///
/// ```swift
/// // OpenAI
/// let config = ProviderConfiguration.openAI(apiKey: "sk-...", model: "gpt-4o")
///
/// // Anthropic
/// let config = ProviderConfiguration.anthropic(apiKey: "sk-ant-...", model: "claude-sonnet-4-20250514")
///
/// // Gemini
/// let config = ProviderConfiguration.gemini(apiKey: "AIza...", model: "gemini-2.0-flash")
///
/// // Use with ChatEngine
/// let engine = ChatEngine(database: db, model: config.makeModel())
/// ```
///
/// ## API Key Handling
///
/// API keys are stored as closures to support both static strings and
/// dynamic retrieval from keychains, environment variables, or secure storage:
///
/// ```swift
/// // Static key
/// let config = ProviderConfiguration.openAI(apiKey: "sk-...", model: "gpt-4o")
///
/// // Dynamic key from environment
/// let config = ProviderConfiguration.openAI(
///     apiKeyProvider: { ProcessInfo.processInfo.environment["OPENAI_API_KEY"] ?? "" },
///     model: "gpt-4o"
/// )
/// ```
public struct ProviderConfiguration: Sendable {

    /// The supported LLM provider types.
    public enum Provider: String, Sendable, Hashable, CaseIterable {
        /// OpenAI's GPT models via the Chat Completions or Responses API.
        case openAI

        /// Anthropic's Claude models.
        case anthropic

        /// Google's Gemini models.
        case gemini

        /// Any OpenAI-compatible API (e.g., local servers, third-party providers).
        case openAICompatible

        /// Ollama — local models via `ollama serve`.
        /// Default endpoint: http://localhost:11434
        case ollama

        /// llama.cpp server — local GGUF models via `llama-server`.
        /// Default endpoint: http://localhost:8080
        /// Uses the OpenAI-compatible API.
        case llamaCpp
    }

    /// The provider type for this configuration.
    public let provider: Provider

    /// The model identifier (e.g., "gpt-4o", "claude-sonnet-4-20250514", "gemini-2.0-flash").
    public let model: String

    /// A closure that provides the API key on demand.
    ///
    /// Using a closure allows lazy evaluation and integration with secure
    /// storage systems (Keychain, environment variables, etc.).
    private let apiKeyProvider: @Sendable () -> String

    /// Optional custom base URL for OpenAI-compatible providers.
    public let baseURL: URL?

    /// Optional API version override (used by Anthropic and Gemini).
    public let apiVersion: String?

    /// Optional beta headers (used by Anthropic).
    public let betas: [String]?

    /// The OpenAI API variant to use (Chat Completions or Responses).
    public let openAIVariant: OpenAILanguageModel.APIVariant?

    // MARK: - Internal Init

    /// Internal memberwise initializer used by factory methods.
    internal init(
        provider: Provider,
        model: String,
        apiKeyProvider: @escaping @Sendable () -> String,
        baseURL: URL?,
        apiVersion: String?,
        betas: [String]?,
        openAIVariant: OpenAILanguageModel.APIVariant?
    ) {
        self.provider = provider
        self.model = model
        self.apiKeyProvider = apiKeyProvider
        self.baseURL = baseURL
        self.apiVersion = apiVersion
        self.betas = betas
        self.openAIVariant = openAIVariant
    }

    // MARK: - Factory Methods

    /// Creates a configuration for OpenAI's API.
    ///
    /// - Parameters:
    ///   - apiKey: Your OpenAI API key (e.g., "sk-...").
    ///   - model: The model identifier (e.g., "gpt-4o", "gpt-4o-mini").
    ///   - variant: The API variant to use. Defaults to `.chatCompletions`.
    ///   - baseURL: Optional custom base URL. Defaults to OpenAI's API.
    /// - Returns: A configured `ProviderConfiguration`.
    public static func openAI(
        apiKey: String,
        model: String,
        variant: OpenAILanguageModel.APIVariant = .chatCompletions,
        baseURL: URL? = nil
    ) -> ProviderConfiguration {
        ProviderConfiguration(
            provider: .openAI,
            model: model,
            apiKeyProvider: { apiKey },
            baseURL: baseURL,
            apiVersion: nil,
            betas: nil,
            openAIVariant: variant
        )
    }

    /// Creates a configuration for OpenAI's API with a dynamic key provider.
    ///
    /// Use this when the API key comes from a keychain, environment variable,
    /// or other dynamic source.
    ///
    /// - Parameters:
    ///   - apiKeyProvider: A closure that returns the API key.
    ///   - model: The model identifier.
    ///   - variant: The API variant to use. Defaults to `.chatCompletions`.
    ///   - baseURL: Optional custom base URL.
    /// - Returns: A configured `ProviderConfiguration`.
    public static func openAI(
        apiKeyProvider: @escaping @Sendable () -> String,
        model: String,
        variant: OpenAILanguageModel.APIVariant = .chatCompletions,
        baseURL: URL? = nil
    ) -> ProviderConfiguration {
        ProviderConfiguration(
            provider: .openAI,
            model: model,
            apiKeyProvider: apiKeyProvider,
            baseURL: baseURL,
            apiVersion: nil,
            betas: nil,
            openAIVariant: variant
        )
    }

    /// Creates a configuration for Anthropic's Claude API.
    ///
    /// - Parameters:
    ///   - apiKey: Your Anthropic API key (e.g., "sk-ant-...").
    ///   - model: The model identifier (e.g., "claude-sonnet-4-20250514").
    ///   - apiVersion: Optional API version override.
    ///   - betas: Optional beta feature headers.
    /// - Returns: A configured `ProviderConfiguration`.
    public static func anthropic(
        apiKey: String,
        model: String,
        apiVersion: String? = nil,
        betas: [String]? = nil
    ) -> ProviderConfiguration {
        ProviderConfiguration(
            provider: .anthropic,
            model: model,
            apiKeyProvider: { apiKey },
            baseURL: nil,
            apiVersion: apiVersion,
            betas: betas,
            openAIVariant: nil
        )
    }

    /// Creates a configuration for Anthropic's Claude API with a dynamic key provider.
    ///
    /// - Parameters:
    ///   - apiKeyProvider: A closure that returns the API key.
    ///   - model: The model identifier.
    ///   - apiVersion: Optional API version override.
    ///   - betas: Optional beta feature headers.
    /// - Returns: A configured `ProviderConfiguration`.
    public static func anthropic(
        apiKeyProvider: @escaping @Sendable () -> String,
        model: String,
        apiVersion: String? = nil,
        betas: [String]? = nil
    ) -> ProviderConfiguration {
        ProviderConfiguration(
            provider: .anthropic,
            model: model,
            apiKeyProvider: apiKeyProvider,
            baseURL: nil,
            apiVersion: apiVersion,
            betas: betas,
            openAIVariant: nil
        )
    }

    /// Creates a configuration for Google's Gemini API.
    ///
    /// - Parameters:
    ///   - apiKey: Your Gemini API key (e.g., "AIza...").
    ///   - model: The model identifier (e.g., "gemini-2.0-flash").
    ///   - apiVersion: Optional API version override (defaults to "v1beta").
    /// - Returns: A configured `ProviderConfiguration`.
    public static func gemini(
        apiKey: String,
        model: String,
        apiVersion: String? = nil
    ) -> ProviderConfiguration {
        ProviderConfiguration(
            provider: .gemini,
            model: model,
            apiKeyProvider: { apiKey },
            baseURL: nil,
            apiVersion: apiVersion,
            betas: nil,
            openAIVariant: nil
        )
    }

    /// Creates a configuration for Google's Gemini API with a dynamic key provider.
    ///
    /// - Parameters:
    ///   - apiKeyProvider: A closure that returns the API key.
    ///   - model: The model identifier.
    ///   - apiVersion: Optional API version override.
    /// - Returns: A configured `ProviderConfiguration`.
    public static func gemini(
        apiKeyProvider: @escaping @Sendable () -> String,
        model: String,
        apiVersion: String? = nil
    ) -> ProviderConfiguration {
        ProviderConfiguration(
            provider: .gemini,
            model: model,
            apiKeyProvider: apiKeyProvider,
            baseURL: nil,
            apiVersion: apiVersion,
            betas: nil,
            openAIVariant: nil
        )
    }

    /// Creates a configuration for any OpenAI-compatible API.
    ///
    /// Use this for third-party services that implement the OpenAI Chat Completions
    /// API (e.g., local LLM servers, Groq, Together AI, etc.).
    ///
    /// ```swift
    /// let config = ProviderConfiguration.openAICompatible(
    ///     apiKey: "your-key",
    ///     model: "llama-3.1-70b",
    ///     baseURL: URL(string: "https://api.together.xyz/v1/")!
    /// )
    /// ```
    ///
    /// - Parameters:
    ///   - apiKey: The API key for the service.
    ///   - model: The model identifier.
    ///   - baseURL: The base URL of the compatible API.
    ///   - variant: The API variant. Defaults to `.chatCompletions`.
    /// - Returns: A configured `ProviderConfiguration`.
    public static func openAICompatible(
        apiKey: String,
        model: String,
        baseURL: URL,
        variant: OpenAILanguageModel.APIVariant = .chatCompletions
    ) -> ProviderConfiguration {
        ProviderConfiguration(
            provider: .openAICompatible,
            model: model,
            apiKeyProvider: { apiKey },
            baseURL: baseURL,
            apiVersion: nil,
            betas: nil,
            openAIVariant: variant
        )
    }

    /// Creates a configuration for any OpenAI-compatible API with a dynamic key provider.
    ///
    /// - Parameters:
    ///   - apiKeyProvider: A closure that returns the API key.
    ///   - model: The model identifier.
    ///   - baseURL: The base URL of the compatible API.
    ///   - variant: The API variant. Defaults to `.chatCompletions`.
    /// - Returns: A configured `ProviderConfiguration`.
    public static func openAICompatible(
        apiKeyProvider: @escaping @Sendable () -> String,
        model: String,
        baseURL: URL,
        variant: OpenAILanguageModel.APIVariant = .chatCompletions
    ) -> ProviderConfiguration {
        ProviderConfiguration(
            provider: .openAICompatible,
            model: model,
            apiKeyProvider: apiKeyProvider,
            baseURL: baseURL,
            apiVersion: nil,
            betas: nil,
            openAIVariant: variant
        )
    }

    // MARK: - Local Provider Factory Methods

    /// Creates a configuration for a local Ollama instance.
    ///
    /// Ollama runs models locally and exposes a native API on port 11434.
    /// No API key is required by default.
    ///
    /// ```swift
    /// // Default local Ollama
    /// let config = ProviderConfiguration.ollama(model: "llama3.2")
    ///
    /// // Ollama on a remote machine
    /// let config = ProviderConfiguration.ollama(
    ///     model: "qwen2.5",
    ///     baseURL: URL(string: "http://192.168.1.100:11434")!
    /// )
    ///
    /// // Use with ChatEngine
    /// let engine = ChatEngine(database: db, provider: config)
    /// ```
    ///
    /// - Parameters:
    ///   - model: The Ollama model name (e.g., "llama3.2", "qwen2.5", "mistral").
    ///   - baseURL: The Ollama server URL. Defaults to `http://localhost:11434`.
    /// - Returns: A configured `ProviderConfiguration`.
    public static func ollama(
        model: String,
        baseURL: URL = OllamaLanguageModel.defaultBaseURL
    ) -> ProviderConfiguration {
        ProviderConfiguration(
            provider: .ollama,
            model: model,
            apiKeyProvider: { "" },
            baseURL: baseURL,
            apiVersion: nil,
            betas: nil,
            openAIVariant: nil
        )
    }

    /// Creates a configuration for a local llama.cpp server.
    ///
    /// llama.cpp's `llama-server` exposes an OpenAI-compatible Chat Completions
    /// API, typically on port 8080. No API key is required by default.
    ///
    /// ```swift
    /// // Default local llama.cpp
    /// let config = ProviderConfiguration.llamaCpp(model: "default")
    ///
    /// // llama.cpp on a custom port with API key
    /// let config = ProviderConfiguration.llamaCpp(
    ///     model: "my-model",
    ///     baseURL: URL(string: "http://localhost:9090")!,
    ///     apiKey: "my-secret-key"
    /// )
    /// ```
    ///
    /// - Parameters:
    ///   - model: The model identifier. Use "default" if llama-server loads a single model.
    ///   - baseURL: The llama.cpp server URL. Defaults to `http://localhost:8080`.
    ///   - apiKey: Optional API key if the server requires authentication.
    /// - Returns: A configured `ProviderConfiguration`.
    public static func llamaCpp(
        model: String = "default",
        baseURL: URL = LocalProviderDiscovery.defaultLlamaCppURL,
        apiKey: String = ""
    ) -> ProviderConfiguration {
        ProviderConfiguration(
            provider: .llamaCpp,
            model: model,
            apiKeyProvider: { apiKey },
            baseURL: baseURL,
            apiVersion: nil,
            betas: nil,
            openAIVariant: .chatCompletions
        )
    }

    // MARK: - Model Construction

    /// Creates a configured `LanguageModel` instance for this provider.
    ///
    /// This is the primary way to get a model from a configuration.
    /// The returned model is ready to use with ``ChatEngine`` or
    /// ``TextSummaryRenderer``.
    ///
    /// ```swift
    /// let config = ProviderConfiguration.openAI(apiKey: "sk-...", model: "gpt-4o")
    /// let engine = ChatEngine(database: db, model: config.makeModel())
    /// ```
    ///
    /// - Returns: A configured `LanguageModel` instance.
    public func makeModel() -> any LanguageModel {
        let key = apiKeyProvider

        switch provider {
        case .openAI:
            if let baseURL {
                return OpenAILanguageModel(
                    baseURL: baseURL,
                    apiKey: key(),
                    model: model,
                    apiVariant: openAIVariant ?? .chatCompletions
                )
            }
            return OpenAILanguageModel(
                apiKey: key(),
                model: model,
                apiVariant: openAIVariant ?? .chatCompletions
            )

        case .anthropic:
            if let apiVersion {
                return AnthropicLanguageModel(
                    apiKey: key(),
                    apiVersion: apiVersion,
                    betas: betas,
                    model: model
                )
            }
            if let betas {
                return AnthropicLanguageModel(
                    apiKey: key(),
                    betas: betas,
                    model: model
                )
            }
            return AnthropicLanguageModel(
                apiKey: key(),
                model: model
            )

        case .gemini:
            if let apiVersion {
                return GeminiLanguageModel(
                    apiKey: key(),
                    apiVersion: apiVersion,
                    model: model
                )
            }
            return GeminiLanguageModel(
                apiKey: key(),
                model: model
            )

        case .openAICompatible:
            return OpenAILanguageModel(
                baseURL: baseURL ?? OpenAILanguageModel.defaultBaseURL,
                apiKey: key(),
                model: model,
                apiVariant: openAIVariant ?? .chatCompletions
            )

        case .ollama:
            return OllamaLanguageModel(
                baseURL: baseURL ?? OllamaLanguageModel.defaultBaseURL,
                model: model
            )

        case .llamaCpp:
            // llama.cpp exposes an OpenAI-compatible API
            return OpenAILanguageModel(
                baseURL: baseURL ?? LocalProviderDiscovery.defaultLlamaCppURL,
                apiKey: key(),
                model: model,
                apiVariant: openAIVariant ?? .chatCompletions
            )
        }
    }

    // MARK: - API Key Access

    /// Returns the current API key.
    ///
    /// Useful for validation or debugging. In production, prefer using
    /// ``makeModel()`` which handles key injection automatically.
    public var apiKey: String {
        apiKeyProvider()
    }

    /// Returns `true` if the API key is non-empty.
    ///
    /// Use this to check configuration validity before creating an engine:
    /// ```swift
    /// guard config.hasValidAPIKey else {
    ///     // Show API key setup UI
    ///     return
    /// }
    /// ```
    public var hasValidAPIKey: Bool {
        !apiKeyProvider().trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    // MARK: - Environment Variable Helpers

    /// Creates a configuration using an API key from an environment variable.
    ///
    /// Falls back to an empty string if the environment variable is not set,
    /// which will cause API calls to fail with an authentication error.
    ///
    /// ```swift
    /// let config = ProviderConfiguration.fromEnvironment(
    ///     provider: .openAI,
    ///     environmentVariable: "OPENAI_API_KEY",
    ///     model: "gpt-4o"
    /// )
    /// ```
    ///
    /// - Parameters:
    ///   - provider: The LLM provider.
    ///   - environmentVariable: The name of the environment variable holding the API key.
    ///   - model: The model identifier.
    /// - Returns: A configured `ProviderConfiguration`.
    public static func fromEnvironment(
        provider: Provider,
        environmentVariable: String,
        model: String
    ) -> ProviderConfiguration {
        let keyProvider: @Sendable () -> String = {
            ProcessInfo.processInfo.environment[environmentVariable] ?? ""
        }

        switch provider {
        case .openAI:
            return .openAI(apiKeyProvider: keyProvider, model: model)
        case .anthropic:
            return .anthropic(apiKeyProvider: keyProvider, model: model)
        case .gemini:
            return .gemini(apiKeyProvider: keyProvider, model: model)
        case .openAICompatible:
            return .openAICompatible(
                apiKeyProvider: keyProvider,
                model: model,
                baseURL: OpenAILanguageModel.defaultBaseURL
            )
        case .ollama:
            return .ollama(model: model)
        case .llamaCpp:
            return .llamaCpp(model: model)
        }
    }
}

// MARK: - ChatEngine Convenience Init

extension ChatEngine {

    /// Creates a ChatEngine using a ``ProviderConfiguration``.
    ///
    /// This is the most convenient way to set up a ChatEngine with a
    /// cloud provider:
    ///
    /// ```swift
    /// let engine = ChatEngine(
    ///     database: myDB,
    ///     provider: .openAI(apiKey: "sk-...", model: "gpt-4o")
    /// )
    /// ```
    ///
    /// - Parameters:
    ///   - database: A GRDB `DatabaseWriter` (DatabasePool or DatabaseQueue).
    ///   - provider: The provider configuration.
    ///   - allowlist: SQL operations the LLM may generate. Defaults to read-only.
    ///   - configuration: Engine configuration for timeouts, context window, validators, etc.
    public convenience init(
        database: any DatabaseWriter,
        provider: ProviderConfiguration,
        allowlist: OperationAllowlist = .readOnly,
        configuration: ChatEngineConfiguration = .default
    ) {
        self.init(
            database: database,
            model: provider.makeModel(),
            allowlist: allowlist,
            configuration: configuration
        )
    }
}
