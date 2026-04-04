// LocalProviderConfiguration.swift
// SwiftDBAI
//
// Configuration and endpoint discovery for local/self-hosted LLM providers
// (Ollama, llama.cpp). Wraps AnyLanguageModel's OllamaLanguageModel and
// OpenAILanguageModel with convenient factory methods and health checking.

import AnyLanguageModel
import Foundation

#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif

// MARK: - Local Provider Endpoint

/// Represents a discovered local LLM endpoint with its connection status.
public struct LocalProviderEndpoint: Sendable, Equatable {
    /// The base URL of the local provider.
    public let baseURL: URL

    /// The provider type (Ollama or llama.cpp).
    public let providerType: LocalProviderType

    /// Whether the endpoint was reachable at discovery time.
    public let isReachable: Bool

    /// The list of available models, if the endpoint supports model listing.
    public let availableModels: [String]

    /// Human-readable description of the endpoint.
    public var description: String {
        let status = isReachable ? "reachable" : "unreachable"
        return "\(providerType.rawValue) at \(baseURL.absoluteString) (\(status), \(availableModels.count) models)"
    }
}

/// The type of local LLM provider.
public enum LocalProviderType: String, Sendable, Hashable, CaseIterable {
    /// Ollama — runs models locally via `ollama serve`.
    /// Default endpoint: http://localhost:11434
    case ollama

    /// llama.cpp server — runs GGUF models via `llama-server`.
    /// Default endpoint: http://localhost:8080
    /// Exposes an OpenAI-compatible API.
    case llamaCpp = "llama.cpp"
}

// MARK: - Local Provider Discovery

/// Discovers and validates local LLM provider endpoints.
///
/// Use `LocalProviderDiscovery` to automatically find running Ollama or llama.cpp
/// instances on the local machine, check their health, and list available models.
///
/// ```swift
/// // Check if Ollama is running
/// let isRunning = await LocalProviderDiscovery.isOllamaRunning()
///
/// // Discover all local providers
/// let endpoints = await LocalProviderDiscovery.discoverAll()
/// for endpoint in endpoints where endpoint.isReachable {
///     print("Found \(endpoint.description)")
/// }
///
/// // List models available on Ollama
/// let models = await LocalProviderDiscovery.listOllamaModels()
/// ```
public enum LocalProviderDiscovery {

    /// Default Ollama endpoint.
    public static let defaultOllamaURL = URL(string: "http://localhost:11434")!

    /// Default llama.cpp server endpoint.
    public static let defaultLlamaCppURL = URL(string: "http://localhost:8080")!

    /// Well-known ports to probe for local providers.
    /// Ollama: 11434, llama.cpp: 8080
    private static let wellKnownEndpoints: [(URL, LocalProviderType)] = [
        (defaultOllamaURL, .ollama),
        (defaultLlamaCppURL, .llamaCpp),
    ]

    // MARK: - Health Checks

    /// Checks if an Ollama instance is reachable at the given URL.
    ///
    /// Sends a GET request to the Ollama root endpoint and checks for a 200 response.
    ///
    /// - Parameter baseURL: The Ollama base URL. Defaults to `http://localhost:11434`.
    /// - Parameter timeout: Connection timeout in seconds. Defaults to 3.
    /// - Returns: `true` if the Ollama server responded successfully.
    public static func isOllamaRunning(
        at baseURL: URL = defaultOllamaURL,
        timeout: TimeInterval = 3
    ) async -> Bool {
        await checkEndpointHealth(baseURL, timeout: timeout)
    }

    /// Checks if a llama.cpp server is reachable at the given URL.
    ///
    /// Sends a GET request to the `/health` endpoint and checks for a 200 response.
    ///
    /// - Parameter baseURL: The llama.cpp base URL. Defaults to `http://localhost:8080`.
    /// - Parameter timeout: Connection timeout in seconds. Defaults to 3.
    /// - Returns: `true` if the llama.cpp server responded successfully.
    public static func isLlamaCppRunning(
        at baseURL: URL = defaultLlamaCppURL,
        timeout: TimeInterval = 3
    ) async -> Bool {
        let healthURL = baseURL.appendingPathComponent("health")
        return await checkEndpointHealth(healthURL, timeout: timeout)
    }

    /// Checks if any endpoint at the given URL responds to HTTP requests.
    ///
    /// - Parameters:
    ///   - url: The URL to probe.
    ///   - timeout: Connection timeout in seconds.
    /// - Returns: `true` if the endpoint returned an HTTP response with status 200.
    private static func checkEndpointHealth(
        _ url: URL,
        timeout: TimeInterval
    ) async -> Bool {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = timeout
        config.timeoutIntervalForResource = timeout
        let session = URLSession(configuration: config)

        do {
            let (_, response) = try await session.data(from: url)
            if let httpResponse = response as? HTTPURLResponse {
                return httpResponse.statusCode == 200
            }
            return false
        } catch {
            return false
        }
    }

    // MARK: - Model Listing

    /// Lists models available on an Ollama instance.
    ///
    /// Calls the Ollama `/api/tags` endpoint to retrieve the list of
    /// locally installed models.
    ///
    /// - Parameter baseURL: The Ollama base URL. Defaults to `http://localhost:11434`.
    /// - Parameter timeout: Request timeout in seconds. Defaults to 5.
    /// - Returns: An array of model name strings, or an empty array if unreachable.
    public static func listOllamaModels(
        at baseURL: URL = defaultOllamaURL,
        timeout: TimeInterval = 5
    ) async -> [String] {
        let tagsURL = baseURL.appendingPathComponent("api/tags")
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = timeout
        config.timeoutIntervalForResource = timeout
        let session = URLSession(configuration: config)

        do {
            let (data, response) = try await session.data(from: tagsURL)
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200
            else {
                return []
            }

            let decoded = try JSONDecoder().decode(OllamaTagsResponse.self, from: data)
            return decoded.models.map(\.name)
        } catch {
            return []
        }
    }

    /// Lists models available on a llama.cpp server via its OpenAI-compatible endpoint.
    ///
    /// Calls `/v1/models` which llama.cpp exposes when running with
    /// `--api-key` or in default mode.
    ///
    /// - Parameter baseURL: The llama.cpp base URL. Defaults to `http://localhost:8080`.
    /// - Parameter timeout: Request timeout in seconds. Defaults to 5.
    /// - Returns: An array of model ID strings, or an empty array if unreachable.
    public static func listLlamaCppModels(
        at baseURL: URL = defaultLlamaCppURL,
        timeout: TimeInterval = 5
    ) async -> [String] {
        let modelsURL = baseURL.appendingPathComponent("v1/models")
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = timeout
        config.timeoutIntervalForResource = timeout
        let session = URLSession(configuration: config)

        do {
            let (data, response) = try await session.data(from: modelsURL)
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200
            else {
                return []
            }

            let decoded = try JSONDecoder().decode(OpenAIModelsResponse.self, from: data)
            return decoded.data.map(\.id)
        } catch {
            return []
        }
    }

    // MARK: - Full Discovery

    /// Discovers all running local LLM providers by probing well-known endpoints.
    ///
    /// Probes Ollama (port 11434) and llama.cpp (port 8080) concurrently,
    /// returning their status and available models.
    ///
    /// ```swift
    /// let endpoints = await LocalProviderDiscovery.discoverAll()
    /// for endpoint in endpoints where endpoint.isReachable {
    ///     print("Found: \(endpoint.description)")
    /// }
    /// ```
    ///
    /// - Parameter timeout: Connection timeout per endpoint in seconds. Defaults to 3.
    /// - Returns: An array of `LocalProviderEndpoint` for each probed location.
    public static func discoverAll(
        timeout: TimeInterval = 3
    ) async -> [LocalProviderEndpoint] {
        await withTaskGroup(of: LocalProviderEndpoint.self, returning: [LocalProviderEndpoint].self) { group in
            for (url, providerType) in wellKnownEndpoints {
                group.addTask {
                    await discover(providerType: providerType, at: url, timeout: timeout)
                }
            }

            var results: [LocalProviderEndpoint] = []
            for await endpoint in group {
                results.append(endpoint)
            }
            return results
        }
    }

    /// Discovers a specific local provider at the given URL.
    ///
    /// - Parameters:
    ///   - providerType: The type of provider to probe.
    ///   - baseURL: The base URL to check.
    ///   - timeout: Connection timeout in seconds.
    /// - Returns: A `LocalProviderEndpoint` with reachability and model info.
    public static func discover(
        providerType: LocalProviderType,
        at baseURL: URL,
        timeout: TimeInterval = 3
    ) async -> LocalProviderEndpoint {
        switch providerType {
        case .ollama:
            let reachable = await isOllamaRunning(at: baseURL, timeout: timeout)
            let models = reachable ? await listOllamaModels(at: baseURL) : []
            return LocalProviderEndpoint(
                baseURL: baseURL,
                providerType: .ollama,
                isReachable: reachable,
                availableModels: models
            )

        case .llamaCpp:
            let reachable = await isLlamaCppRunning(at: baseURL, timeout: timeout)
            let models = reachable ? await listLlamaCppModels(at: baseURL) : []
            return LocalProviderEndpoint(
                baseURL: baseURL,
                providerType: .llamaCpp,
                isReachable: reachable,
                availableModels: models
            )
        }
    }

    /// Discovers a specific local provider at a custom URL and port.
    ///
    /// Use this for non-standard configurations where Ollama or llama.cpp
    /// is running on a custom host or port.
    ///
    /// ```swift
    /// let endpoint = await LocalProviderDiscovery.discover(
    ///     providerType: .ollama,
    ///     host: "192.168.1.100",
    ///     port: 11434
    /// )
    /// ```
    ///
    /// - Parameters:
    ///   - providerType: The provider type.
    ///   - host: The hostname or IP address.
    ///   - port: The port number.
    ///   - timeout: Connection timeout in seconds. Defaults to 3.
    /// - Returns: A `LocalProviderEndpoint` with reachability and model info.
    public static func discover(
        providerType: LocalProviderType,
        host: String,
        port: Int,
        timeout: TimeInterval = 3
    ) async -> LocalProviderEndpoint {
        guard let url = URL(string: "http://\(host):\(port)") else {
            return LocalProviderEndpoint(
                baseURL: URL(string: "http://\(host):\(port)")!,
                providerType: providerType,
                isReachable: false,
                availableModels: []
            )
        }
        return await discover(providerType: providerType, at: url, timeout: timeout)
    }
}

// MARK: - JSON Response Types

/// Response from Ollama's `/api/tags` endpoint.
private struct OllamaTagsResponse: Decodable, Sendable {
    let models: [OllamaModelInfo]
}

/// Individual model info from Ollama's tags endpoint.
private struct OllamaModelInfo: Decodable, Sendable {
    let name: String
}

/// Response from the OpenAI-compatible `/v1/models` endpoint.
private struct OpenAIModelsResponse: Decodable, Sendable {
    let data: [OpenAIModelInfo]
}

/// Individual model info from the OpenAI models endpoint.
private struct OpenAIModelInfo: Decodable, Sendable {
    let id: String
}
