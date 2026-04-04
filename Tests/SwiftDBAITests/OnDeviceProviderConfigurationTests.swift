// OnDeviceProviderConfigurationTests.swift
// SwiftDBAI Tests
//
// Tests for on-device provider configurations (CoreML, MLX) including
// configuration validation, inference pipeline setup, and system readiness.

import AnyLanguageModel
import Foundation
@testable import SwiftDBAI
import Testing

@Suite("OnDeviceProviderConfiguration")
struct OnDeviceProviderConfigurationTests {

    // MARK: - OnDeviceProviderType

    @Test("OnDeviceProviderType has CoreML and MLX cases")
    func providerTypeCases() {
        let cases = OnDeviceProviderType.allCases
        #expect(cases.count == 2)
        #expect(cases.contains(.coreML))
        #expect(cases.contains(.mlx))
    }

    @Test("OnDeviceProviderType raw values are descriptive")
    func providerTypeRawValues() {
        #expect(OnDeviceProviderType.coreML.rawValue == "coreML")
        #expect(OnDeviceProviderType.mlx.rawValue == "mlx")
    }

    // MARK: - CoreML Configuration

    @Test("CoreML configuration stores all properties")
    func coreMLBasicConfiguration() {
        let url = URL(fileURLWithPath: "/tmp/TestModel.mlmodelc")
        let config = CoreMLProviderConfiguration(
            modelURL: url,
            computeUnits: .cpuAndGPU,
            maxResponseTokens: 1024,
            useSampling: true,
            temperature: 0.3
        )

        #expect(config.modelURL == url)
        #expect(config.computeUnits == .cpuAndGPU)
        #expect(config.maxResponseTokens == 1024)
        #expect(config.useSampling == true)
        #expect(config.temperature == 0.3)
    }

    @Test("CoreML configuration uses sensible defaults")
    func coreMLDefaultConfiguration() {
        let url = URL(fileURLWithPath: "/tmp/TestModel.mlmodelc")
        let config = CoreMLProviderConfiguration(modelURL: url)

        #expect(config.computeUnits == .all)
        #expect(config.maxResponseTokens == 2048)
        #expect(config.useSampling == false)
        #expect(config.temperature == 0.1)
    }

    @Test("CoreML validation fails for non-mlmodelc extension")
    func coreMLValidateWrongExtension() {
        let url = URL(fileURLWithPath: "/tmp/TestModel.onnx")
        let config = CoreMLProviderConfiguration(modelURL: url)

        #expect(throws: OnDeviceProviderError.self) {
            try config.validate()
        }
    }

    @Test("CoreML validation fails for missing model file")
    func coreMLValidateMissingFile() {
        let url = URL(fileURLWithPath: "/nonexistent/path/Model.mlmodelc")
        let config = CoreMLProviderConfiguration(modelURL: url)

        #expect(throws: OnDeviceProviderError.self) {
            try config.validate()
        }
    }

    @Test("CoreML configuration is Equatable")
    func coreMLEquatable() {
        let url = URL(fileURLWithPath: "/tmp/TestModel.mlmodelc")
        let a = CoreMLProviderConfiguration(modelURL: url, computeUnits: .all)
        let b = CoreMLProviderConfiguration(modelURL: url, computeUnits: .all)
        let c = CoreMLProviderConfiguration(modelURL: url, computeUnits: .cpuOnly)

        #expect(a == b)
        #expect(a != c)
    }

    // MARK: - ComputeUnitPreference

    @Test("ComputeUnitPreference has all expected cases")
    func computeUnitCases() {
        let cases = ComputeUnitPreference.allCases
        #expect(cases.count == 4)
        #expect(cases.contains(.all))
        #expect(cases.contains(.cpuOnly))
        #expect(cases.contains(.cpuAndGPU))
        #expect(cases.contains(.cpuAndNeuralEngine))
    }

    // MARK: - MLX Configuration

    @Test("MLX configuration stores all properties")
    func mlxBasicConfiguration() {
        let dir = URL(fileURLWithPath: "/tmp/models/my-model")
        let config = MLXProviderConfiguration(
            modelId: "mlx-community/Test-Model-4bit",
            localDirectory: dir,
            gpuMemory: .minimal,
            maxResponseTokens: 512,
            temperature: 0.2,
            topP: 0.9,
            repetitionPenalty: 1.2
        )

        #expect(config.modelId == "mlx-community/Test-Model-4bit")
        #expect(config.localDirectory == dir)
        #expect(config.gpuMemory == .minimal)
        #expect(config.maxResponseTokens == 512)
        #expect(config.temperature == 0.2)
        #expect(config.topP == 0.9)
        #expect(config.repetitionPenalty == 1.2)
    }

    @Test("MLX configuration uses sensible defaults")
    func mlxDefaultConfiguration() {
        let config = MLXProviderConfiguration(modelId: "test-model")

        #expect(config.localDirectory == nil)
        #expect(config.gpuMemory == .automatic)
        #expect(config.maxResponseTokens == 2048)
        #expect(config.temperature == 0.1)
        #expect(config.topP == 0.95)
        #expect(config.repetitionPenalty == 1.1)
    }

    @Test("MLX validation fails for empty model ID")
    func mlxValidateEmptyModelId() {
        let config = MLXProviderConfiguration(modelId: "")

        #expect(throws: OnDeviceProviderError.self) {
            try config.validate()
        }
    }

    @Test("MLX validation fails for nonexistent local directory")
    func mlxValidateMissingDirectory() {
        let config = MLXProviderConfiguration(
            modelId: "test-model",
            localDirectory: URL(fileURLWithPath: "/nonexistent/directory")
        )

        #expect(throws: OnDeviceProviderError.self) {
            try config.validate()
        }
    }

    @Test("MLX validation fails for negative temperature")
    func mlxValidateNegativeTemperature() {
        let config = MLXProviderConfiguration(
            modelId: "test-model",
            temperature: -0.5
        )

        #expect(throws: OnDeviceProviderError.self) {
            try config.validate()
        }
    }

    @Test("MLX validation fails for topP out of range")
    func mlxValidateInvalidTopP() {
        let configZero = MLXProviderConfiguration(
            modelId: "test-model",
            topP: 0.0
        )

        #expect(throws: OnDeviceProviderError.self) {
            try configZero.validate()
        }

        let configOver = MLXProviderConfiguration(
            modelId: "test-model",
            topP: 1.5
        )

        #expect(throws: OnDeviceProviderError.self) {
            try configOver.validate()
        }
    }

    @Test("MLX validation fails for zero repetition penalty")
    func mlxValidateInvalidRepetitionPenalty() {
        let config = MLXProviderConfiguration(
            modelId: "test-model",
            repetitionPenalty: 0.0
        )

        #expect(throws: OnDeviceProviderError.self) {
            try config.validate()
        }
    }

    @Test("MLX validation succeeds for valid configuration")
    func mlxValidateSuccess() throws {
        let config = MLXProviderConfiguration(modelId: "test-model")
        // Should not throw (no local directory set, model ID is non-empty)
        try config.validate()
    }

    @Test("MLX configuration is Equatable")
    func mlxEquatable() {
        let a = MLXProviderConfiguration(modelId: "model-a")
        let b = MLXProviderConfiguration(modelId: "model-a")
        let c = MLXProviderConfiguration(modelId: "model-b")

        #expect(a == b)
        #expect(a != c)
    }

    // MARK: - Well-Known MLX Models

    @Test("Llama 3.2 3B preset has correct model ID")
    func llama3_2_3BPreset() {
        let config = MLXProviderConfiguration.llama3_2_3B()
        #expect(config.modelId == "mlx-community/Llama-3.2-3B-Instruct-4bit")
        #expect(config.temperature == 0.1)
        #expect(config.maxResponseTokens == 2048)
    }

    @Test("Qwen 2.5 Coder 3B preset has correct model ID")
    func qwen2_5_coder3BPreset() {
        let config = MLXProviderConfiguration.qwen2_5_coder_3B()
        #expect(config.modelId == "mlx-community/Qwen2.5-Coder-3B-Instruct-4bit")
        #expect(config.temperature == 0.05)
    }

    @Test("Phi 3.5 Mini preset has correct model ID")
    func phi3_5_miniPreset() {
        let config = MLXProviderConfiguration.phi3_5_mini()
        #expect(config.modelId == "mlx-community/Phi-3.5-mini-instruct-4bit")
        #expect(config.temperature == 0.1)
    }

    @Test("Well-known models accept custom GPU memory config")
    func wellKnownModelsCustomGPU() {
        let config = MLXProviderConfiguration.llama3_2_3B(
            gpuMemory: .minimal
        )
        #expect(config.gpuMemory == .minimal)
    }

    // MARK: - GPU Memory Configuration

    @Test("Automatic GPU memory config scales with RAM")
    func automaticGPUMemory() {
        let config = MLXGPUMemoryConfig.automatic
        #expect(config.activeCacheLimit > 0)
        #expect(config.idleCacheLimit == 50_000_000)
        #expect(config.clearCacheOnEviction == true)
    }

    @Test("Minimal GPU memory config is conservative")
    func minimalGPUMemory() {
        let config = MLXGPUMemoryConfig.minimal
        #expect(config.activeCacheLimit == 64_000_000)
        #expect(config.idleCacheLimit == 16_000_000)
        #expect(config.clearCacheOnEviction == true)
    }

    @Test("Unconstrained GPU memory config uses max values")
    func unconstrainedGPUMemory() {
        let config = MLXGPUMemoryConfig.unconstrained
        #expect(config.activeCacheLimit == Int.max)
        #expect(config.idleCacheLimit == Int.max)
        #expect(config.clearCacheOnEviction == false)
    }

    @Test("GPU memory config is Equatable")
    func gpuMemoryEquatable() {
        #expect(MLXGPUMemoryConfig.minimal == MLXGPUMemoryConfig.minimal)
        #expect(MLXGPUMemoryConfig.minimal != MLXGPUMemoryConfig.unconstrained)
    }

    // MARK: - On-Device Provider Errors

    @Test("OnDeviceProviderError has descriptive messages")
    func errorDescriptions() {
        let errors: [OnDeviceProviderError] = [
            .modelNotFound(URL(fileURLWithPath: "/tmp/model")),
            .invalidModelFormat(expected: ".mlmodelc", actual: ".onnx"),
            .emptyModelId,
            .invalidParameter(name: "temperature", value: "-1", reason: "Must be non-negative"),
            .providerUnavailable(.mlx, reason: "MLX build flag not enabled"),
            .modelLoadFailed(reason: "Out of memory"),
            .inferenceFailed(reason: "Token limit exceeded"),
        ]

        for error in errors {
            #expect(error.errorDescription != nil)
            #expect(!error.errorDescription!.isEmpty)
        }
    }

    @Test("OnDeviceProviderError is Equatable")
    func errorEquatable() {
        let a = OnDeviceProviderError.emptyModelId
        let b = OnDeviceProviderError.emptyModelId
        let c = OnDeviceProviderError.modelLoadFailed(reason: "test")

        #expect(a == b)
        #expect(a != c)
    }

    // MARK: - Inference Pipeline

    @Test("MLX inference pipeline initializes with correct type")
    func mlxPipelineInit() {
        let config = MLXProviderConfiguration.llama3_2_3B()
        let pipeline = OnDeviceInferencePipeline(mlxConfiguration: config)

        #expect(pipeline.providerType == .mlx)
        #expect(pipeline.mlxConfiguration != nil)
        #expect(pipeline.coreMLConfiguration == nil)
        #expect(pipeline.status == .notLoaded)
    }

    @Test("CoreML inference pipeline initializes with correct type")
    func coreMLPipelineInit() {
        let url = URL(fileURLWithPath: "/tmp/TestModel.mlmodelc")
        let config = CoreMLProviderConfiguration(modelURL: url)
        let pipeline = OnDeviceInferencePipeline(coreMLConfiguration: config)

        #expect(pipeline.providerType == .coreML)
        #expect(pipeline.coreMLConfiguration != nil)
        #expect(pipeline.mlxConfiguration == nil)
        #expect(pipeline.status == .notLoaded)
    }

    @Test("Pipeline validates MLX configuration")
    func pipelineValidatesMLX() throws {
        let validConfig = MLXProviderConfiguration(modelId: "test-model")
        let pipeline = OnDeviceInferencePipeline(mlxConfiguration: validConfig)
        try pipeline.validateConfiguration()

        let invalidConfig = MLXProviderConfiguration(modelId: "")
        let invalidPipeline = OnDeviceInferencePipeline(mlxConfiguration: invalidConfig)
        #expect(throws: OnDeviceProviderError.self) {
            try invalidPipeline.validateConfiguration()
        }
    }

    @Test("Pipeline validates CoreML configuration")
    func pipelineValidatesCoreML() {
        let url = URL(fileURLWithPath: "/tmp/TestModel.onnx")
        let config = CoreMLProviderConfiguration(modelURL: url)
        let pipeline = OnDeviceInferencePipeline(coreMLConfiguration: config)

        #expect(throws: OnDeviceProviderError.self) {
            try pipeline.validateConfiguration()
        }
    }

    @Test("Pipeline provides SQL generation hints for MLX")
    func mlxSQLHints() {
        let config = MLXProviderConfiguration(
            modelId: "test-model",
            maxResponseTokens: 512,
            temperature: 0.2
        )
        let pipeline = OnDeviceInferencePipeline(mlxConfiguration: config)
        let hints = pipeline.recommendedSQLGenerationHints

        #expect(hints.maxTokens == 512)
        #expect(hints.temperature == 0.2)
        #expect(hints.useSampling == true)
        #expect(hints.systemPromptSuffix.contains("MLX"))
    }

    @Test("Pipeline provides SQL generation hints for CoreML")
    func coreMLSQLHints() {
        let url = URL(fileURLWithPath: "/tmp/TestModel.mlmodelc")
        let config = CoreMLProviderConfiguration(
            modelURL: url,
            maxResponseTokens: 1024,
            useSampling: false,
            temperature: 0.05
        )
        let pipeline = OnDeviceInferencePipeline(coreMLConfiguration: config)
        let hints = pipeline.recommendedSQLGenerationHints

        #expect(hints.maxTokens == 1024)
        #expect(hints.temperature == 0.05)
        #expect(hints.useSampling == false)
        #expect(hints.systemPromptSuffix.contains("SQL"))
    }

    // MARK: - System Readiness

    @Test("System capability check returns valid data")
    func systemCapability() {
        let capability = OnDeviceModelReadiness.checkSystemCapability()

        #expect(capability.totalRAM > 0)
        // On any modern test machine, we should have at least some RAM
        #expect(capability.totalRAM > 1024 * 1024 * 1024) // > 1GB

        // On Apple silicon Macs, this should be true
        #if arch(arm64)
            #expect(capability.hasNeuralEngine == true)
        #endif
    }

    @Test("Suggested MLX model returns a valid configuration")
    func suggestedMLXModel() {
        let config = OnDeviceModelReadiness.suggestedMLXModel()
        #expect(!config.modelId.isEmpty)
        #expect(config.temperature >= 0)
        #expect(config.maxResponseTokens > 0)
    }

    @Test("Recommended model size enum has correct raw values")
    func recommendedModelSizeRawValues() {
        #expect(OnDeviceModelReadiness.RecommendedModelSize.small.rawValue == "small")
        #expect(OnDeviceModelReadiness.RecommendedModelSize.medium.rawValue == "medium")
        #expect(OnDeviceModelReadiness.RecommendedModelSize.large.rawValue == "large")
    }

    // MARK: - ProviderConfiguration Integration

    @Test("onDeviceMLX creates a ProviderConfiguration")
    func onDeviceMLXProviderConfig() {
        let mlxConfig = MLXProviderConfiguration.llama3_2_3B()
        let providerConfig = ProviderConfiguration.onDeviceMLX(mlxConfig)

        #expect(providerConfig.model == mlxConfig.modelId)
        #expect(!providerConfig.hasValidAPIKey) // No API key needed for on-device
    }

    @Test("onDeviceCoreML creates a ProviderConfiguration")
    func onDeviceCoreMLProviderConfig() {
        let url = URL(fileURLWithPath: "/tmp/SQLModel.mlmodelc")
        let coreMLConfig = CoreMLProviderConfiguration(modelURL: url)
        let providerConfig = ProviderConfiguration.onDeviceCoreML(coreMLConfig)

        #expect(providerConfig.model == "SQLModel.mlmodelc")
        #expect(!providerConfig.hasValidAPIKey)
    }

    // MARK: - Pipeline Status

    @Test("Pipeline status transitions")
    func pipelineStatusTransitions() {
        let config = MLXProviderConfiguration(modelId: "test-model")
        let pipeline = OnDeviceInferencePipeline(mlxConfiguration: config)

        #expect(pipeline.status == .notLoaded)

        pipeline.setStatus(.loading)
        #expect(pipeline.status == .loading)

        pipeline.setStatus(.ready)
        #expect(pipeline.status == .ready)

        pipeline.setStatus(.failed("Out of memory"))
        #expect(pipeline.status == .failed("Out of memory"))
    }

    @Test("Pipeline Status is Equatable")
    func pipelineStatusEquatable() {
        #expect(OnDeviceInferencePipeline.Status.notLoaded == .notLoaded)
        #expect(OnDeviceInferencePipeline.Status.loading == .loading)
        #expect(OnDeviceInferencePipeline.Status.ready == .ready)
        #expect(OnDeviceInferencePipeline.Status.failed("a") == .failed("a"))
        #expect(OnDeviceInferencePipeline.Status.failed("a") != .failed("b"))
        #expect(OnDeviceInferencePipeline.Status.notLoaded != .ready)
    }

    // MARK: - SQL Generation Hints

    @Test("SQL generation hints are Equatable")
    func sqlHintsEquatable() {
        let a = OnDeviceSQLGenerationHints(
            maxTokens: 512,
            temperature: 0.1,
            systemPromptSuffix: "test",
            useSampling: true
        )
        let b = OnDeviceSQLGenerationHints(
            maxTokens: 512,
            temperature: 0.1,
            systemPromptSuffix: "test",
            useSampling: true
        )
        let c = OnDeviceSQLGenerationHints(
            maxTokens: 1024,
            temperature: 0.1,
            systemPromptSuffix: "test",
            useSampling: true
        )

        #expect(a == b)
        #expect(a != c)
    }
}
