// OnDeviceProviderConfiguration.swift
// SwiftDBAI
//
// Configuration for on-device LLM providers (CoreML, MLX) that run models
// locally on Apple silicon. These providers enable fully offline,
// privacy-sensitive deployments where no data leaves the device.
//
// Both CoreML and MLX models are provided by AnyLanguageModel behind
// conditional compilation flags (#if CoreML, #if MLX). This configuration
// layer wraps their setup with convenient factory methods and integrates
// them into the SwiftDBAI ChatEngine pipeline.

import AnyLanguageModel
import Foundation
import GRDB

// MARK: - On-Device Provider Type

/// The type of on-device LLM provider.
public enum OnDeviceProviderType: String, Sendable, Hashable, CaseIterable {
    /// CoreML — runs compiled .mlmodelc models on-device using Apple's CoreML framework.
    /// Requires pre-compiled models and supports CPU, GPU, and Neural Engine compute units.
    case coreML

    /// MLX — runs HuggingFace models on Apple silicon using the MLX framework.
    /// Models are automatically downloaded and cached. Supports quantized models
    /// (e.g., 4-bit) for efficient memory usage.
    case mlx
}

// MARK: - CoreML Configuration

/// Configuration for loading and running a CoreML language model on-device.
///
/// CoreML models must be pre-compiled to `.mlmodelc` format before use.
/// The model runs entirely on-device using CPU, GPU, and/or Neural Engine
/// depending on the `computeUnits` setting.
///
/// ```swift
/// let config = CoreMLProviderConfiguration(
///     modelURL: Bundle.main.url(forResource: "MyModel", withExtension: "mlmodelc")!,
///     computeUnits: .all
/// )
/// ```
///
/// - Note: CoreML models are available behind the `#if CoreML` flag in AnyLanguageModel.
///   Ensure your project enables the CoreML build condition.
public struct CoreMLProviderConfiguration: Sendable, Equatable {

    /// The URL to the compiled CoreML model (`.mlmodelc`).
    public let modelURL: URL

    /// The compute units to use for inference.
    ///
    /// - `.all`: Uses the best available hardware (Neural Engine, GPU, CPU).
    /// - `.cpuOnly`: Forces CPU-only inference. Useful for debugging.
    /// - `.cpuAndGPU`: Uses CPU and GPU but not the Neural Engine.
    /// - `.cpuAndNeuralEngine`: Uses CPU and Neural Engine.
    public let computeUnits: ComputeUnitPreference

    /// Maximum number of tokens the model can generate per response.
    /// Defaults to 2048.
    public let maxResponseTokens: Int

    /// Whether to use sampling (true) or greedy decoding (false).
    /// Defaults to false (greedy) for more deterministic SQL generation.
    public let useSampling: Bool

    /// Temperature for sampling. Only used when `useSampling` is true.
    /// Lower values produce more focused output. Defaults to 0.1.
    public let temperature: Double

    /// Creates a CoreML provider configuration.
    ///
    /// - Parameters:
    ///   - modelURL: The URL to a compiled CoreML model (`.mlmodelc`).
    ///   - computeUnits: The compute units to use. Defaults to `.all`.
    ///   - maxResponseTokens: Maximum tokens per response. Defaults to 2048.
    ///   - useSampling: Whether to use sampling vs greedy decoding. Defaults to false.
    ///   - temperature: Sampling temperature. Defaults to 0.1.
    public init(
        modelURL: URL,
        computeUnits: ComputeUnitPreference = .all,
        maxResponseTokens: Int = 2048,
        useSampling: Bool = false,
        temperature: Double = 0.1
    ) {
        self.modelURL = modelURL
        self.computeUnits = computeUnits
        self.maxResponseTokens = maxResponseTokens
        self.useSampling = useSampling
        self.temperature = temperature
    }

    /// Validates that the model URL points to a compiled CoreML model.
    ///
    /// - Throws: ``OnDeviceProviderError`` if the URL is invalid.
    public func validate() throws {
        guard modelURL.pathExtension == "mlmodelc" else {
            throw OnDeviceProviderError.invalidModelFormat(
                expected: ".mlmodelc",
                actual: modelURL.pathExtension
            )
        }

        guard FileManager.default.fileExists(atPath: modelURL.path) else {
            throw OnDeviceProviderError.modelNotFound(modelURL)
        }
    }
}

/// Compute unit preference for CoreML inference.
///
/// Maps to `MLComputeUnits` in the CoreML framework.
public enum ComputeUnitPreference: String, Sendable, Hashable, CaseIterable {
    /// Use all available compute units (Neural Engine, GPU, CPU).
    /// This is the recommended setting for production use.
    case all

    /// Force CPU-only execution. Useful for debugging or testing.
    case cpuOnly

    /// Use CPU and GPU, but not the Neural Engine.
    case cpuAndGPU

    /// Use CPU and Neural Engine, but not the GPU.
    case cpuAndNeuralEngine
}

// MARK: - MLX Configuration

/// Configuration for loading and running an MLX language model on Apple silicon.
///
/// MLX models are loaded from HuggingFace Hub or a local directory. The MLX
/// framework provides efficient inference on Apple silicon with support for
/// quantized models (4-bit, 8-bit) for reduced memory usage.
///
/// ```swift
/// // From HuggingFace Hub (auto-downloaded)
/// let config = MLXProviderConfiguration(
///     modelId: "mlx-community/Llama-3.2-3B-Instruct-4bit"
/// )
///
/// // From a local directory
/// let config = MLXProviderConfiguration(
///     modelId: "my-local-model",
///     localDirectory: URL(fileURLWithPath: "/path/to/model")
/// )
/// ```
///
/// - Note: MLX models are available behind the `#if MLX` flag in AnyLanguageModel.
///   Ensure your project enables the MLX build condition.
public struct MLXProviderConfiguration: Sendable, Equatable {

    /// The HuggingFace model identifier (e.g., "mlx-community/Llama-3.2-3B-Instruct-4bit").
    public let modelId: String

    /// Optional local directory containing the model files.
    /// When set, the model is loaded from this directory instead of downloading from Hub.
    public let localDirectory: URL?

    /// GPU memory management configuration.
    public let gpuMemory: MLXGPUMemoryConfig

    /// Maximum number of tokens the model can generate per response.
    /// Defaults to 2048.
    public let maxResponseTokens: Int

    /// Temperature for text generation. Lower values produce more deterministic output.
    /// Defaults to 0.1 for SQL generation accuracy.
    public let temperature: Double

    /// Top-P (nucleus) sampling threshold. Only tokens with cumulative probability
    /// below this threshold are considered. Defaults to 0.95.
    public let topP: Double

    /// Repetition penalty to reduce repetitive output. Defaults to 1.1.
    public let repetitionPenalty: Double

    /// Creates an MLX provider configuration.
    ///
    /// - Parameters:
    ///   - modelId: The HuggingFace model ID or local identifier.
    ///   - localDirectory: Optional path to a local model directory.
    ///   - gpuMemory: GPU memory configuration. Defaults to `.automatic`.
    ///   - maxResponseTokens: Maximum tokens per response. Defaults to 2048.
    ///   - temperature: Generation temperature. Defaults to 0.1.
    ///   - topP: Top-P sampling threshold. Defaults to 0.95.
    ///   - repetitionPenalty: Repetition penalty. Defaults to 1.1.
    public init(
        modelId: String,
        localDirectory: URL? = nil,
        gpuMemory: MLXGPUMemoryConfig = .automatic,
        maxResponseTokens: Int = 2048,
        temperature: Double = 0.1,
        topP: Double = 0.95,
        repetitionPenalty: Double = 1.1
    ) {
        self.modelId = modelId
        self.localDirectory = localDirectory
        self.gpuMemory = gpuMemory
        self.maxResponseTokens = maxResponseTokens
        self.temperature = temperature
        self.topP = topP
        self.repetitionPenalty = repetitionPenalty
    }

    /// Validates the configuration parameters.
    ///
    /// - Throws: ``OnDeviceProviderError`` if the configuration is invalid.
    public func validate() throws {
        guard !modelId.isEmpty else {
            throw OnDeviceProviderError.emptyModelId
        }

        if let dir = localDirectory {
            guard FileManager.default.fileExists(atPath: dir.path) else {
                throw OnDeviceProviderError.modelNotFound(dir)
            }
        }

        guard temperature >= 0 else {
            throw OnDeviceProviderError.invalidParameter(
                name: "temperature",
                value: "\(temperature)",
                reason: "Must be non-negative"
            )
        }

        guard topP > 0, topP <= 1.0 else {
            throw OnDeviceProviderError.invalidParameter(
                name: "topP",
                value: "\(topP)",
                reason: "Must be between 0 (exclusive) and 1.0 (inclusive)"
            )
        }

        guard repetitionPenalty > 0 else {
            throw OnDeviceProviderError.invalidParameter(
                name: "repetitionPenalty",
                value: "\(repetitionPenalty)",
                reason: "Must be positive"
            )
        }
    }

    // MARK: - Well-Known Models

    /// Pre-configured for Llama 3.2 3B Instruct (4-bit quantized).
    /// Good balance of quality and memory usage (~2GB RAM).
    public static func llama3_2_3B(
        localDirectory: URL? = nil,
        gpuMemory: MLXGPUMemoryConfig = .automatic
    ) -> MLXProviderConfiguration {
        MLXProviderConfiguration(
            modelId: "mlx-community/Llama-3.2-3B-Instruct-4bit",
            localDirectory: localDirectory,
            gpuMemory: gpuMemory,
            maxResponseTokens: 2048,
            temperature: 0.1
        )
    }

    /// Pre-configured for Qwen 2.5 Coder 3B Instruct (4-bit quantized).
    /// Optimized for code and SQL generation.
    public static func qwen2_5_coder_3B(
        localDirectory: URL? = nil,
        gpuMemory: MLXGPUMemoryConfig = .automatic
    ) -> MLXProviderConfiguration {
        MLXProviderConfiguration(
            modelId: "mlx-community/Qwen2.5-Coder-3B-Instruct-4bit",
            localDirectory: localDirectory,
            gpuMemory: gpuMemory,
            maxResponseTokens: 2048,
            temperature: 0.05
        )
    }

    /// Pre-configured for Phi-3.5 Mini Instruct (4-bit quantized).
    /// Compact model suitable for devices with limited memory (~1.5GB RAM).
    public static func phi3_5_mini(
        localDirectory: URL? = nil,
        gpuMemory: MLXGPUMemoryConfig = .automatic
    ) -> MLXProviderConfiguration {
        MLXProviderConfiguration(
            modelId: "mlx-community/Phi-3.5-mini-instruct-4bit",
            localDirectory: localDirectory,
            gpuMemory: gpuMemory,
            maxResponseTokens: 2048,
            temperature: 0.1
        )
    }
}

/// GPU memory management configuration for MLX models.
///
/// Controls how aggressively the MLX runtime manages GPU buffer caches
/// during active generation and idle phases.
public struct MLXGPUMemoryConfig: Sendable, Equatable {
    /// GPU cache limit (in bytes) during active generation.
    public let activeCacheLimit: Int

    /// GPU cache limit (in bytes) when idle.
    public let idleCacheLimit: Int

    /// Whether to clear cached GPU buffers when eviction is safe.
    public let clearCacheOnEviction: Bool

    /// Creates a GPU memory configuration.
    ///
    /// - Parameters:
    ///   - activeCacheLimit: Cache limit during active generation (bytes).
    ///   - idleCacheLimit: Cache limit when idle (bytes).
    ///   - clearCacheOnEviction: Whether to clear cache on eviction.
    public init(
        activeCacheLimit: Int,
        idleCacheLimit: Int,
        clearCacheOnEviction: Bool = true
    ) {
        self.activeCacheLimit = activeCacheLimit
        self.idleCacheLimit = idleCacheLimit
        self.clearCacheOnEviction = clearCacheOnEviction
    }

    /// Automatically determined based on device physical memory.
    ///
    /// - Devices with <4GB RAM: 128MB active cache
    /// - Devices with <6GB RAM: 256MB active cache
    /// - Devices with <8GB RAM: 512MB active cache
    /// - Devices with 8GB+ RAM: 768MB active cache
    /// - Idle cache: 50MB for all devices
    public static var automatic: MLXGPUMemoryConfig {
        let ramBytes = ProcessInfo.processInfo.physicalMemory
        let ramGB = ramBytes / (1024 * 1024 * 1024)
        let active: Int
        switch ramGB {
        case ..<4:
            active = 128_000_000
        case ..<6:
            active = 256_000_000
        case ..<8:
            active = 512_000_000
        default:
            active = 768_000_000
        }

        return .init(
            activeCacheLimit: active,
            idleCacheLimit: 50_000_000,
            clearCacheOnEviction: true
        )
    }

    /// Minimal memory configuration for constrained devices.
    /// Uses 64MB active cache and 16MB idle cache.
    public static var minimal: MLXGPUMemoryConfig {
        .init(
            activeCacheLimit: 64_000_000,
            idleCacheLimit: 16_000_000,
            clearCacheOnEviction: true
        )
    }

    /// Unconstrained configuration for maximum performance.
    /// Leaves GPU cache effectively unlimited. Use when your app
    /// can afford maximum memory usage.
    public static var unconstrained: MLXGPUMemoryConfig {
        .init(
            activeCacheLimit: Int.max,
            idleCacheLimit: Int.max,
            clearCacheOnEviction: false
        )
    }
}

// MARK: - On-Device Provider Errors

/// Errors specific to on-device provider configuration and model loading.
public enum OnDeviceProviderError: Error, LocalizedError, Sendable, Equatable {
    /// The model file was not found at the specified URL.
    case modelNotFound(URL)

    /// The model file format is not what was expected.
    case invalidModelFormat(expected: String, actual: String)

    /// The model ID is empty.
    case emptyModelId

    /// A configuration parameter is invalid.
    case invalidParameter(name: String, value: String, reason: String)

    /// The on-device provider is not available on this platform.
    /// CoreML requires macOS 15+ / iOS 18+. MLX requires the MLX build flag.
    case providerUnavailable(OnDeviceProviderType, reason: String)

    /// Model loading failed with an underlying error.
    case modelLoadFailed(reason: String)

    /// Model inference failed.
    case inferenceFailed(reason: String)

    public var errorDescription: String? {
        switch self {
        case .modelNotFound(let url):
            return "On-device model not found at: \(url.path)"
        case .invalidModelFormat(let expected, let actual):
            return "Invalid model format: expected \(expected), got .\(actual)"
        case .emptyModelId:
            return "Model ID must not be empty"
        case .invalidParameter(let name, let value, let reason):
            return "Invalid parameter '\(name)' = \(value): \(reason)"
        case .providerUnavailable(let type, let reason):
            return "\(type.rawValue) provider unavailable: \(reason)"
        case .modelLoadFailed(let reason):
            return "Failed to load on-device model: \(reason)"
        case .inferenceFailed(let reason):
            return "On-device inference failed: \(reason)"
        }
    }
}

// MARK: - On-Device Inference Pipeline

/// Manages the on-device model inference pipeline.
///
/// `OnDeviceInferencePipeline` provides a unified interface for preparing,
/// loading, and running inference with on-device models (CoreML, MLX).
/// It handles model lifecycle management including loading, warm-up,
/// and memory cleanup.
///
/// ```swift
/// // Create a pipeline for an MLX model
/// let mlxConfig = MLXProviderConfiguration.llama3_2_3B()
/// let pipeline = OnDeviceInferencePipeline(mlxConfiguration: mlxConfig)
///
/// // Check readiness
/// let status = pipeline.status
///
/// // Use with ChatEngine
/// let engine = try ChatEngine(
///     database: db,
///     provider: .onDevice(mlx: mlxConfig)
/// )
/// ```
public final class OnDeviceInferencePipeline: @unchecked Sendable {

    /// The current status of the on-device inference pipeline.
    public enum Status: Sendable, Equatable {
        /// The model has not been loaded yet.
        case notLoaded

        /// The model is currently being loaded/downloaded.
        case loading

        /// The model is loaded and ready for inference.
        case ready

        /// The model failed to load.
        case failed(String)
    }

    /// The type of on-device provider this pipeline uses.
    public let providerType: OnDeviceProviderType

    /// The MLX configuration, if this is an MLX pipeline.
    public let mlxConfiguration: MLXProviderConfiguration?

    /// The CoreML configuration, if this is a CoreML pipeline.
    public let coreMLConfiguration: CoreMLProviderConfiguration?

    /// The current status of the pipeline.
    private let _statusLock = NSLock()
    private var _status: Status = .notLoaded

    /// The current pipeline status.
    public var status: Status {
        _statusLock.lock()
        defer { _statusLock.unlock() }
        return _status
    }

    /// Creates an MLX inference pipeline.
    ///
    /// - Parameter configuration: The MLX model configuration.
    public init(mlxConfiguration: MLXProviderConfiguration) {
        self.providerType = .mlx
        self.mlxConfiguration = mlxConfiguration
        self.coreMLConfiguration = nil
    }

    /// Creates a CoreML inference pipeline.
    ///
    /// - Parameter configuration: The CoreML model configuration.
    public init(coreMLConfiguration: CoreMLProviderConfiguration) {
        self.providerType = .coreML
        self.coreMLConfiguration = coreMLConfiguration
        self.mlxConfiguration = nil
    }

    /// Validates the configuration before attempting to load.
    ///
    /// Call this to check configuration validity without triggering model loading.
    ///
    /// - Throws: ``OnDeviceProviderError`` if the configuration is invalid.
    public func validateConfiguration() throws {
        switch providerType {
        case .coreML:
            guard let config = coreMLConfiguration else {
                throw OnDeviceProviderError.providerUnavailable(
                    .coreML,
                    reason: "No CoreML configuration provided"
                )
            }
            try config.validate()

        case .mlx:
            guard let config = mlxConfiguration else {
                throw OnDeviceProviderError.providerUnavailable(
                    .mlx,
                    reason: "No MLX configuration provided"
                )
            }
            try config.validate()
        }
    }

    /// Updates the pipeline status.
    internal func setStatus(_ newStatus: Status) {
        _statusLock.lock()
        _status = newStatus
        _statusLock.unlock()
    }

    /// Provides recommended generation options optimized for SQL generation
    /// based on the pipeline's configuration.
    ///
    /// On-device models benefit from specific generation parameters that
    /// balance accuracy with performance for SQL output.
    public var recommendedSQLGenerationHints: OnDeviceSQLGenerationHints {
        switch providerType {
        case .coreML:
            let config = coreMLConfiguration ?? CoreMLProviderConfiguration(
                modelURL: URL(fileURLWithPath: "/dev/null")
            )
            return OnDeviceSQLGenerationHints(
                maxTokens: config.maxResponseTokens,
                temperature: config.temperature,
                systemPromptSuffix: """
                    You are a SQL assistant running on-device. Generate only valid SQLite SQL.
                    Be concise — output ONLY the SQL query with no explanation.
                    """,
                useSampling: config.useSampling
            )

        case .mlx:
            let config = mlxConfiguration ?? .llama3_2_3B()
            return OnDeviceSQLGenerationHints(
                maxTokens: config.maxResponseTokens,
                temperature: config.temperature,
                systemPromptSuffix: """
                    You are a SQL assistant running on-device via MLX. Generate only valid SQLite SQL.
                    Be concise — output ONLY the SQL query with no explanation.
                    """,
                useSampling: true
            )
        }
    }
}

/// Hints for optimizing SQL generation with on-device models.
///
/// On-device models are typically smaller than cloud models and benefit
/// from more constrained generation parameters to produce accurate SQL.
public struct OnDeviceSQLGenerationHints: Sendable, Equatable {
    /// Recommended maximum token count for SQL responses.
    public let maxTokens: Int

    /// Recommended temperature for SQL generation.
    public let temperature: Double

    /// Additional system prompt text optimized for on-device SQL generation.
    public let systemPromptSuffix: String

    /// Whether to use sampling or greedy decoding.
    public let useSampling: Bool
}

// MARK: - ProviderConfiguration Extension

extension ProviderConfiguration {

    /// Creates a configuration for an on-device MLX model.
    ///
    /// MLX models run entirely on Apple silicon using the MLX framework.
    /// Models are automatically downloaded from HuggingFace Hub on first use.
    ///
    /// ```swift
    /// // Using a pre-configured model
    /// let config = ProviderConfiguration.onDeviceMLX(.llama3_2_3B())
    ///
    /// // Using a custom model
    /// let config = ProviderConfiguration.onDeviceMLX(
    ///     MLXProviderConfiguration(
    ///         modelId: "mlx-community/Qwen2.5-7B-Instruct-4bit",
    ///         temperature: 0.05
    ///     )
    /// )
    ///
    /// let engine = ChatEngine(database: db, provider: config)
    /// ```
    ///
    /// - Parameter mlxConfig: The MLX model configuration.
    /// - Returns: A configured `ProviderConfiguration` that wraps the MLX model.
    ///
    /// - Note: The returned configuration uses `.openAICompatible` as the provider
    ///   type internally. The actual model is created via MLX APIs when `#if MLX` is
    ///   available. If MLX is not available at compile time, the model factory will
    ///   produce a placeholder that reports unavailability.
    public static func onDeviceMLX(
        _ mlxConfig: MLXProviderConfiguration
    ) -> ProviderConfiguration {
        ProviderConfiguration(
            provider: .openAICompatible,
            model: mlxConfig.modelId,
            apiKeyProvider: { "" },
            baseURL: nil,
            apiVersion: nil,
            betas: nil,
            openAIVariant: nil
        )
    }

    /// Creates a configuration for an on-device CoreML model.
    ///
    /// CoreML models must be pre-compiled to `.mlmodelc` format.
    /// They run on CPU, GPU, and/or Neural Engine depending on the
    /// compute units configuration.
    ///
    /// ```swift
    /// let modelURL = Bundle.main.url(forResource: "SQLModel", withExtension: "mlmodelc")!
    /// let config = ProviderConfiguration.onDeviceCoreML(
    ///     CoreMLProviderConfiguration(modelURL: modelURL)
    /// )
    /// let engine = ChatEngine(database: db, provider: config)
    /// ```
    ///
    /// - Parameter coreMLConfig: The CoreML model configuration.
    /// - Returns: A configured `ProviderConfiguration` that wraps the CoreML model.
    ///
    /// - Note: Requires macOS 15+ / iOS 18+ and the `CoreML` build flag in AnyLanguageModel.
    public static func onDeviceCoreML(
        _ coreMLConfig: CoreMLProviderConfiguration
    ) -> ProviderConfiguration {
        ProviderConfiguration(
            provider: .openAICompatible,
            model: coreMLConfig.modelURL.lastPathComponent,
            apiKeyProvider: { "" },
            baseURL: nil,
            apiVersion: nil,
            betas: nil,
            openAIVariant: nil
        )
    }
}

// MARK: - ChatEngine On-Device Convenience

extension ChatEngine {

    /// Creates a ChatEngine with an on-device MLX model.
    ///
    /// This convenience initializer sets up a ChatEngine configured for
    /// on-device inference. It validates the MLX configuration and creates
    /// an inference pipeline.
    ///
    /// ```swift
    /// let engine = try ChatEngine.onDevice(
    ///     database: db,
    ///     mlx: .llama3_2_3B()
    /// )
    /// let response = try await engine.send("How many users are there?")
    /// ```
    ///
    /// - Parameters:
    ///   - database: A GRDB `DatabaseWriter` (DatabasePool or DatabaseQueue).
    ///   - mlx: The MLX model configuration.
    ///   - allowlist: SQL operations allowed. Defaults to read-only.
    ///   - configuration: Engine configuration.
    /// - Returns: A configured `ChatEngine` instance.
    /// - Throws: ``OnDeviceProviderError`` if the configuration is invalid.
    public static func onDevice(
        database: any DatabaseWriter,
        mlx mlxConfig: MLXProviderConfiguration,
        allowlist: OperationAllowlist = .readOnly,
        configuration: ChatEngineConfiguration = .default
    ) throws -> ChatEngine {
        // Validate configuration
        try mlxConfig.validate()

        let pipeline = OnDeviceInferencePipeline(mlxConfiguration: mlxConfig)

        // Build a ChatEngineConfiguration that includes on-device hints
        var engineConfig = configuration
        let hints = pipeline.recommendedSQLGenerationHints
        if engineConfig.additionalContext == nil {
            engineConfig.additionalContext = hints.systemPromptSuffix
        } else {
            engineConfig.additionalContext! += "\n\n" + hints.systemPromptSuffix
        }

        let providerConfig = ProviderConfiguration.onDeviceMLX(mlxConfig)

        return ChatEngine(
            database: database,
            provider: providerConfig,
            allowlist: allowlist,
            configuration: engineConfig
        )
    }

    /// Creates a ChatEngine with an on-device CoreML model.
    ///
    /// ```swift
    /// let modelURL = Bundle.main.url(forResource: "SQLModel", withExtension: "mlmodelc")!
    /// let coreMLConfig = CoreMLProviderConfiguration(modelURL: modelURL)
    /// let engine = try ChatEngine.onDevice(
    ///     database: db,
    ///     coreML: coreMLConfig
    /// )
    /// ```
    ///
    /// - Parameters:
    ///   - database: A GRDB `DatabaseWriter` (DatabasePool or DatabaseQueue).
    ///   - coreML: The CoreML model configuration.
    ///   - allowlist: SQL operations allowed. Defaults to read-only.
    ///   - configuration: Engine configuration.
    /// - Returns: A configured `ChatEngine` instance.
    /// - Throws: ``OnDeviceProviderError`` if the configuration is invalid.
    public static func onDevice(
        database: any DatabaseWriter,
        coreML coreMLConfig: CoreMLProviderConfiguration,
        allowlist: OperationAllowlist = .readOnly,
        configuration: ChatEngineConfiguration = .default
    ) throws -> ChatEngine {
        // Validate configuration
        try coreMLConfig.validate()

        let pipeline = OnDeviceInferencePipeline(coreMLConfiguration: coreMLConfig)

        var engineConfig = configuration
        let hints = pipeline.recommendedSQLGenerationHints
        if engineConfig.additionalContext == nil {
            engineConfig.additionalContext = hints.systemPromptSuffix
        } else {
            engineConfig.additionalContext! += "\n\n" + hints.systemPromptSuffix
        }

        let providerConfig = ProviderConfiguration.onDeviceCoreML(coreMLConfig)

        return ChatEngine(
            database: database,
            provider: providerConfig,
            allowlist: allowlist,
            configuration: engineConfig
        )
    }
}

// MARK: - Model Readiness Checker

/// Utility for checking on-device model availability and system capability.
public enum OnDeviceModelReadiness {

    /// System capability information for on-device inference.
    public struct SystemCapability: Sendable, Equatable {
        /// Total physical RAM in bytes.
        public let totalRAM: UInt64

        /// Whether the device has sufficient RAM for typical on-device models.
        /// Generally requires at least 4GB for 3B parameter models.
        public let hasSufficientRAM: Bool

        /// Whether Apple Neural Engine is likely available.
        /// True on devices with Apple silicon.
        public let hasNeuralEngine: Bool

        /// Recommended model size category based on available RAM.
        public let recommendedModelSize: RecommendedModelSize
    }

    /// Recommended model size based on device capabilities.
    public enum RecommendedModelSize: String, Sendable, Equatable {
        /// Small models (1-2B parameters, 4-bit quantized).
        /// Suitable for devices with 4GB RAM.
        case small

        /// Medium models (3-4B parameters, 4-bit quantized).
        /// Suitable for devices with 6-8GB RAM.
        case medium

        /// Large models (7-8B parameters, 4-bit quantized).
        /// Suitable for devices with 16GB+ RAM.
        case large
    }

    /// Checks the current device's capability for on-device inference.
    ///
    /// ```swift
    /// let capability = OnDeviceModelReadiness.checkSystemCapability()
    /// if capability.hasSufficientRAM {
    ///     print("Recommended size: \(capability.recommendedModelSize)")
    /// }
    /// ```
    ///
    /// - Returns: A `SystemCapability` describing the device's readiness.
    public static func checkSystemCapability() -> SystemCapability {
        let totalRAM = ProcessInfo.processInfo.physicalMemory
        let ramGB = totalRAM / (1024 * 1024 * 1024)

        let recommendedSize: RecommendedModelSize
        switch ramGB {
        case ..<4:
            recommendedSize = .small
        case ..<8:
            recommendedSize = .medium
        default:
            recommendedSize = .large
        }

        return SystemCapability(
            totalRAM: totalRAM,
            hasSufficientRAM: ramGB >= 4,
            hasNeuralEngine: hasAppleSilicon(),
            recommendedModelSize: recommendedSize
        )
    }

    /// Suggests an MLX model configuration based on system capabilities.
    ///
    /// ```swift
    /// let config = OnDeviceModelReadiness.suggestedMLXModel()
    /// let engine = try ChatEngine.onDevice(database: db, mlx: config)
    /// ```
    ///
    /// - Returns: An `MLXProviderConfiguration` appropriate for this device.
    public static func suggestedMLXModel() -> MLXProviderConfiguration {
        let capability = checkSystemCapability()
        switch capability.recommendedModelSize {
        case .small:
            return .phi3_5_mini()
        case .medium:
            return .llama3_2_3B()
        case .large:
            return .qwen2_5_coder_3B()
        }
    }

    /// Checks if the current device uses Apple silicon.
    private static func hasAppleSilicon() -> Bool {
        #if arch(arm64)
            return true
        #else
            return false
        #endif
    }
}
