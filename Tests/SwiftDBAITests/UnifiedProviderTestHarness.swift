// UnifiedProviderTestHarness.swift
// SwiftDBAI Tests
//
// A unified test harness that validates all seven provider types
// conform to the AnyLanguageModel protocol and produce consistent
// ChatEngine-compatible output. Covers: OpenAI, Anthropic, Gemini,
// OpenAI-Compatible, Ollama, llama.cpp, and on-device (MLX/CoreML).

import AnyLanguageModel
import Foundation
import GRDB
import Testing

@testable import SwiftDBAI

// MARK: - Provider-Simulating Mock Models

/// A mock that records which LanguageModel protocol methods were called,
/// the arguments passed, and returns configurable responses.
/// Used to validate that every provider path through ChatEngine
/// exercises the same protocol surface.
final class ProviderConformanceMock: LanguageModel, @unchecked Sendable {
    typealias UnavailableReason = Never

    /// Track calls to verify protocol conformance exercised fully.
    struct CallRecord: Sendable {
        let method: String
        let promptDescription: String
        let timestamp: Date
    }

    private let lock = NSLock()
    private var _calls: [CallRecord] = []
    private let _responses: [String]
    private var _callIndex = 0

    /// Label for diagnostics.
    let providerName: String

    var calls: [CallRecord] {
        lock.lock()
        defer { lock.unlock() }
        return _calls
    }

    init(providerName: String, responses: [String]) {
        self.providerName = providerName
        self._responses = responses
    }

    private func nextResponse() -> String {
        lock.lock()
        defer { lock.unlock() }
        let idx = _callIndex
        _callIndex += 1
        return idx < _responses.count ? _responses[idx] : "fallback response"
    }

    private func recordCall(method: String, prompt: String) {
        lock.lock()
        _calls.append(CallRecord(method: method, promptDescription: prompt, timestamp: Date()))
        lock.unlock()
    }

    func respond<Content>(
        within session: LanguageModelSession,
        to prompt: Prompt,
        generating type: Content.Type,
        includeSchemaInPrompt: Bool,
        options: GenerationOptions
    ) async throws -> LanguageModelSession.Response<Content> where Content: Generable {
        recordCall(method: "respond", prompt: prompt.description)
        let text = nextResponse()
        let rawContent = GeneratedContent(kind: .string(text))
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
        recordCall(method: "streamResponse", prompt: prompt.description)
        let text = nextResponse()
        let rawContent = GeneratedContent(kind: .string(text))
        let content = try! Content(rawContent)
        return LanguageModelSession.ResponseStream(content: content, rawContent: rawContent)
    }
}

// MARK: - Test Database Helper

/// Creates a minimal in-memory database for provider integration tests.
private func makeProviderTestDatabase() throws -> DatabaseQueue {
    let db = try DatabaseQueue(path: ":memory:")
    try db.write { db in
        try db.execute(sql: """
            CREATE TABLE products (
                id INTEGER PRIMARY KEY,
                name TEXT NOT NULL,
                price REAL NOT NULL,
                category TEXT NOT NULL
            )
            """)
        try db.execute(sql: """
            INSERT INTO products (name, price, category) VALUES
            ('Widget', 9.99, 'tools'),
            ('Gadget', 24.99, 'electronics'),
            ('Doohickey', 4.50, 'tools')
            """)
    }
    return db
}

// MARK: - Unified Provider Test Harness

@Suite("Unified Provider Test Harness")
struct UnifiedProviderTestHarness {

    // MARK: - Provider Configuration Enumeration

    /// All seven provider types that SwiftDBAI supports.
    enum TestedProvider: String, CaseIterable {
        case openAI
        case anthropic
        case gemini
        case openAICompatible
        case ollama
        case llamaCpp
        case onDevice
    }

    /// Creates a ProviderConformanceMock simulating each provider type.
    private func makeMock(for provider: TestedProvider, responses: [String]) -> ProviderConformanceMock {
        ProviderConformanceMock(providerName: provider.rawValue, responses: responses)
    }

    // MARK: - 1. Protocol Conformance — All Providers Are LanguageModel

    @Test("All provider types produce instances conforming to LanguageModel protocol")
    func allProvidersConformToLanguageModel() {
        // Cloud providers via ProviderConfiguration.makeModel()
        let openAI = ProviderConfiguration.openAI(apiKey: "test-key", model: "gpt-4o").makeModel()
        let anthropic = ProviderConfiguration.anthropic(apiKey: "test-key", model: "claude-sonnet-4-20250514").makeModel()
        let gemini = ProviderConfiguration.gemini(apiKey: "test-key", model: "gemini-2.0-flash").makeModel()
        let openAICompatible = ProviderConfiguration.openAICompatible(
            apiKey: "test-key",
            model: "local-model",
            baseURL: URL(string: "http://localhost:8080/v1/")!
        ).makeModel()
        let ollama = ProviderConfiguration.ollama(model: "llama3.2").makeModel()
        let llamaCpp = ProviderConfiguration.llamaCpp(model: "default").makeModel()
        // On-device MLX (wraps as openAICompatible internally)
        let onDeviceMLX = ProviderConfiguration.onDeviceMLX(
            MLXProviderConfiguration(modelId: "test-model")
        ).makeModel()

        // Verify all are LanguageModel
        let models: [(String, any LanguageModel)] = [
            ("OpenAI", openAI),
            ("Anthropic", anthropic),
            ("Gemini", gemini),
            ("OpenAI-Compatible", openAICompatible),
            ("Ollama", ollama),
            ("llama.cpp", llamaCpp),
            ("On-Device MLX", onDeviceMLX),
        ]

        for (name, model) in models {
            // Protocol conformance is compile-time, but we verify isAvailable works
            #expect(model.isAvailable, "\(name) model should report as available")
        }
    }

    @Test("All provider configurations produce correct concrete model types")
    func providerConfigurationsProduceCorrectTypes() {
        let openAI = ProviderConfiguration.openAI(apiKey: "k", model: "m").makeModel()
        #expect(openAI is OpenAILanguageModel, "OpenAI config should produce OpenAILanguageModel")

        let anthropic = ProviderConfiguration.anthropic(apiKey: "k", model: "m").makeModel()
        #expect(anthropic is AnthropicLanguageModel, "Anthropic config should produce AnthropicLanguageModel")

        let gemini = ProviderConfiguration.gemini(apiKey: "k", model: "m").makeModel()
        #expect(gemini is GeminiLanguageModel, "Gemini config should produce GeminiLanguageModel")

        let openAICompat = ProviderConfiguration.openAICompatible(
            apiKey: "k", model: "m", baseURL: URL(string: "http://localhost:1234")!
        ).makeModel()
        #expect(openAICompat is OpenAILanguageModel, "OpenAI-Compatible config should produce OpenAILanguageModel")

        let ollama = ProviderConfiguration.ollama(model: "m").makeModel()
        #expect(ollama is OllamaLanguageModel, "Ollama config should produce OllamaLanguageModel")

        let llamaCpp = ProviderConfiguration.llamaCpp(model: "m").makeModel()
        #expect(llamaCpp is OpenAILanguageModel, "llama.cpp config should produce OpenAILanguageModel (OpenAI-compatible)")

        // On-device uses OpenAILanguageModel internally as a wrapper
        let onDevice = ProviderConfiguration.onDeviceMLX(
            MLXProviderConfiguration(modelId: "test")
        ).makeModel()
        #expect(onDevice is OpenAILanguageModel, "On-device MLX config should produce OpenAILanguageModel wrapper")
    }

    // MARK: - 2. Consistent ChatEngine-Compatible Output

    @Test("Every provider mock produces valid ChatEngine responses for SELECT queries",
          arguments: TestedProvider.allCases)
    func providerProducesValidChatEngineResponse(provider: TestedProvider) async throws {
        let db = try makeProviderTestDatabase()
        let mock = makeMock(for: provider, responses: [
            "SELECT COUNT(*) FROM products",        // SQL generation
            "There are 3 products in the database.", // Summary (fallback)
        ])

        let engine = ChatEngine(database: db, model: mock)
        let response = try await engine.send("How many products are there?")

        // All providers must produce:
        // 1. Non-empty summary
        #expect(!response.summary.isEmpty, "\(provider.rawValue): summary must not be empty")

        // 2. Valid SQL that was executed
        #expect(response.sql == "SELECT COUNT(*) FROM products",
                "\(provider.rawValue): SQL must match generated query")

        // 3. A QueryResult with data
        #expect(response.queryResult != nil, "\(provider.rawValue): queryResult must exist")
        #expect(response.queryResult?.rowCount == 1, "\(provider.rawValue): should have 1 row for COUNT")
    }

    @Test("Every provider mock produces valid ChatEngine responses for multi-row SELECT",
          arguments: TestedProvider.allCases)
    func providerProducesMultiRowResponse(provider: TestedProvider) async throws {
        let db = try makeProviderTestDatabase()
        let mock = makeMock(for: provider, responses: [
            "SELECT name, price FROM products ORDER BY price DESC",
            "Here are the products sorted by price.",
        ])

        let engine = ChatEngine(database: db, model: mock)
        let response = try await engine.send("List products by price")

        #expect(response.queryResult != nil, "\(provider.rawValue): queryResult must exist")
        #expect(response.queryResult?.rowCount == 3, "\(provider.rawValue): should return all 3 products")
        #expect(response.queryResult?.columns.contains("name") == true,
                "\(provider.rawValue): columns must include 'name'")
        #expect(response.queryResult?.columns.contains("price") == true,
                "\(provider.rawValue): columns must include 'price'")
    }

    // MARK: - 3. Consistent LanguageModelSession Integration

    @Test("Every provider mock works through LanguageModelSession.respond(to:)",
          arguments: TestedProvider.allCases)
    func providerWorksWithSession(provider: TestedProvider) async throws {
        let mock = makeMock(for: provider, responses: [
            "SELECT 1 AS test",
        ])

        let session = LanguageModelSession(
            model: mock,
            instructions: "You are a SQL assistant."
        )

        let response = try await session.respond(to: "Generate a test query")

        // Verify the response content is the expected string
        #expect(response.content == "SELECT 1 AS test",
                "\(provider.rawValue): session response should match mock output")

        // Verify the mock received the call
        #expect(mock.calls.count == 1, "\(provider.rawValue): should have exactly 1 call")
        #expect(mock.calls.first?.method == "respond",
                "\(provider.rawValue): should call respond method")
    }

    @Test("Every provider mock works through LanguageModelSession.streamResponse(to:)",
          arguments: TestedProvider.allCases)
    func providerWorksWithStreamSession(provider: TestedProvider) async throws {
        let mock = makeMock(for: provider, responses: [
            "SELECT 42 AS answer",
        ])

        let session = LanguageModelSession(
            model: mock,
            instructions: "You are a SQL assistant."
        )

        let stream = session.streamResponse(to: "Give me a number")
        let collected = try await stream.collect()

        #expect(collected.content == "SELECT 42 AS answer",
                "\(provider.rawValue): stream collected response should match mock output")
        #expect(mock.calls.count == 1, "\(provider.rawValue): should have exactly 1 call")
        #expect(mock.calls.first?.method == "streamResponse",
                "\(provider.rawValue): should call streamResponse method")
    }

    // MARK: - 4. Schema Introspection Works Identically Across Providers

    @Test("Schema introspection returns same schema regardless of provider",
          arguments: TestedProvider.allCases)
    func schemaIntrospectionIsProviderAgnostic(provider: TestedProvider) async throws {
        let db = try makeProviderTestDatabase()
        let mock = makeMock(for: provider, responses: ["SELECT 1"])

        let engine = ChatEngine(database: db, model: mock)
        let schema = try await engine.prepareSchema()

        #expect(schema.tableNames.contains("products"),
                "\(provider.rawValue): schema must include 'products' table")
        #expect(schema.tableNames.count == 1,
                "\(provider.rawValue): should have exactly 1 table")

        let table = schema.tables["products"]
        #expect(table != nil, "\(provider.rawValue): must find products table")
        #expect(table?.columns.count == 4,
                "\(provider.rawValue): products table must have 4 columns")
    }

    // MARK: - 5. Error Handling Consistency

    @Test("All providers handle empty schema consistently",
          arguments: TestedProvider.allCases)
    func emptySchemaHandledConsistently(provider: TestedProvider) async throws {
        let db = try DatabaseQueue(path: ":memory:")
        let mock = makeMock(for: provider, responses: ["SELECT 1"])

        let engine = ChatEngine(database: db, model: mock)

        do {
            _ = try await engine.send("Show me data")
            Issue.record("\(provider.rawValue): should throw for empty schema")
        } catch let error as SwiftDBAIError {
            #expect(error == .emptySchema,
                    "\(provider.rawValue): must throw .emptySchema for database with no tables")
        }
    }

    @Test("All providers reject disallowed SQL operations consistently",
          arguments: TestedProvider.allCases)
    func disallowedSQLRejectedConsistently(provider: TestedProvider) async throws {
        let db = try makeProviderTestDatabase()
        let mock = makeMock(for: provider, responses: [
            "DELETE FROM products WHERE id = 1",
        ])

        // Default allowlist is readOnly (SELECT only)
        let engine = ChatEngine(database: db, model: mock)

        do {
            _ = try await engine.send("Delete the first product")
            Issue.record("\(provider.rawValue): should reject DELETE when allowlist is readOnly")
        } catch {
            // All providers must trigger the same error path for disallowed operations
            #expect(error is SwiftDBAIError,
                    "\(provider.rawValue): error must be SwiftDBAIError")
        }
    }

    // MARK: - 6. Conversation History Consistency

    @Test("Conversation history works identically for all providers",
          arguments: TestedProvider.allCases)
    func conversationHistoryConsistent(provider: TestedProvider) async throws {
        let db = try makeProviderTestDatabase()
        // ChatEngine calls LLM for SQL generation, then TextSummaryRenderer
        // may call LLM for summarization. For aggregate queries (COUNT, AVG),
        // TextSummaryRenderer uses a template and skips the LLM call.
        // So the mock sequence is: SQL1, SQL2 (each followed by template summary).
        let mock = makeMock(for: provider, responses: [
            "SELECT COUNT(*) FROM products",
            "SELECT AVG(price) FROM products",
        ])

        let engine = ChatEngine(database: db, model: mock)

        _ = try await engine.send("How many products?")
        _ = try await engine.send("What is the average price?")

        let messages = engine.messages
        #expect(messages.count == 4,
                "\(provider.rawValue): should have 4 messages (2 user + 2 assistant)")
        #expect(messages[0].role == .user, "\(provider.rawValue): first message should be user")
        #expect(messages[1].role == .assistant, "\(provider.rawValue): second message should be assistant")
        #expect(messages[2].role == .user, "\(provider.rawValue): third message should be user")
        #expect(messages[3].role == .assistant, "\(provider.rawValue): fourth message should be assistant")

        // Both assistant messages must have SQL
        #expect(messages[1].sql != nil, "\(provider.rawValue): first response must have SQL")
        #expect(messages[3].sql != nil, "\(provider.rawValue): second response must have SQL")
    }

    // MARK: - 7. ProviderConfiguration Roundtrip

    @Test("All cloud provider configurations roundtrip through makeModel()")
    func allCloudProvidersRoundtrip() {
        let configs: [(String, ProviderConfiguration)] = [
            ("OpenAI", .openAI(apiKey: "sk-test", model: "gpt-4o")),
            ("OpenAI Responses", .openAI(apiKey: "sk-test", model: "gpt-4o", variant: .responses)),
            ("Anthropic", .anthropic(apiKey: "sk-ant-test", model: "claude-sonnet-4-20250514")),
            ("Anthropic+version", .anthropic(apiKey: "sk-ant-test", model: "claude-sonnet-4-20250514", apiVersion: "2024-01-01")),
            ("Anthropic+betas", .anthropic(apiKey: "sk-ant-test", model: "claude-sonnet-4-20250514", betas: ["computer-use"])),
            ("Gemini", .gemini(apiKey: "AIza-test", model: "gemini-2.0-flash")),
            ("Gemini+version", .gemini(apiKey: "AIza-test", model: "gemini-2.0-flash", apiVersion: "v1")),
            ("OpenAI-Compatible", .openAICompatible(
                apiKey: "key", model: "model", baseURL: URL(string: "http://localhost:1234")!
            )),
            ("Ollama", .ollama(model: "llama3.2")),
            ("Ollama+custom URL", .ollama(model: "qwen2.5", baseURL: URL(string: "http://192.168.1.100:11434")!)),
            ("llama.cpp", .llamaCpp(model: "default")),
            ("llama.cpp+custom", .llamaCpp(model: "my-model", baseURL: URL(string: "http://localhost:9090")!)),
        ]

        for (name, config) in configs {
            let model = config.makeModel()
            #expect(model.isAvailable, "\(name): model must be available after makeModel()")
        }
    }

    @Test("On-device provider configurations produce valid models")
    func onDeviceProvidersRoundtrip() {
        let mlxConfigs: [MLXProviderConfiguration] = [
            .llama3_2_3B(),
            .qwen2_5_coder_3B(),
            .phi3_5_mini(),
            MLXProviderConfiguration(modelId: "custom-model", temperature: 0.2),
        ]

        for mlxConfig in mlxConfigs {
            let providerConfig = ProviderConfiguration.onDeviceMLX(mlxConfig)
            let model = providerConfig.makeModel()
            #expect(model.isAvailable, "MLX model '\(mlxConfig.modelId)' must be available")
        }
    }

    // MARK: - 8. Write Operation Allowlist Consistency

    @Test("Write operations require explicit opt-in for all providers",
          arguments: TestedProvider.allCases)
    func writeOperationsRequireOptIn(provider: TestedProvider) async throws {
        let db = try makeProviderTestDatabase()

        // Mock returns an INSERT statement
        let mock = makeMock(for: provider, responses: [
            "INSERT INTO products (name, price, category) VALUES ('New', 1.00, 'misc')",
        ])

        // readOnly allowlist (default)
        let readOnlyEngine = ChatEngine(database: db, model: mock)

        do {
            _ = try await readOnlyEngine.send("Add a new product")
            Issue.record("\(provider.rawValue): INSERT should be rejected with readOnly allowlist")
        } catch {
            #expect(error is SwiftDBAIError,
                    "\(provider.rawValue): must throw SwiftDBAIError for disallowed INSERT")
        }
    }

    @Test("Allowed write operations work for all providers",
          arguments: TestedProvider.allCases)
    func allowedWriteOperationsWork(provider: TestedProvider) async throws {
        let db = try makeProviderTestDatabase()

        let mock = makeMock(for: provider, responses: [
            "INSERT INTO products (name, price, category) VALUES ('NewItem', 1.00, 'misc')",
            "Successfully added 1 product.",
        ])

        let engine = ChatEngine(
            database: db,
            model: mock,
            allowlist: .standard
        )

        let response = try await engine.send("Add a product called NewItem")
        #expect(response.sql?.uppercased().hasPrefix("INSERT") == true,
                "\(provider.rawValue): SQL should be an INSERT")
    }

    // MARK: - 9. Response Format Consistency

    @Test("ChatResponse structure is identical regardless of provider",
          arguments: TestedProvider.allCases)
    func responseStructureConsistent(provider: TestedProvider) async throws {
        let db = try makeProviderTestDatabase()
        let mock = makeMock(for: provider, responses: [
            "SELECT name, price, category FROM products",
            "Found 3 products across 2 categories.",
        ])

        let engine = ChatEngine(database: db, model: mock)
        let response = try await engine.send("Show all products")

        // ChatResponse must always have these properties populated
        #expect(response.summary.count > 0,
                "\(provider.rawValue): summary must be non-empty")
        #expect(response.sql != nil,
                "\(provider.rawValue): sql must be present")
        #expect(response.queryResult != nil,
                "\(provider.rawValue): queryResult must be present")

        // QueryResult structure must match the query
        let qr = response.queryResult!
        #expect(qr.columns == ["name", "price", "category"],
                "\(provider.rawValue): columns must match SELECT clause")
        #expect(qr.rowCount == 3,
                "\(provider.rawValue): must return all rows")
        #expect(qr.sql == "SELECT name, price, category FROM products",
                "\(provider.rawValue): QueryResult.sql must match executed SQL")
        #expect(qr.executionTime >= 0,
                "\(provider.rawValue): execution time must be non-negative")
    }

    // MARK: - 10. Provider Enum Completeness

    @Test("TestedProvider covers all ProviderConfiguration.Provider cases plus on-device")
    func testedProviderCoversAllCases() {
        // ProviderConfiguration.Provider has 6 cases
        let configProviderCount = ProviderConfiguration.Provider.allCases.count
        #expect(configProviderCount == 6, "ProviderConfiguration.Provider should have 6 cases")

        // TestedProvider adds on-device for 7 total
        #expect(TestedProvider.allCases.count == 7, "TestedProvider should cover all 7 provider types")

        // Verify 1:1 mapping for the config providers
        let configNames = Set(ProviderConfiguration.Provider.allCases.map(\.rawValue))
        for tested in TestedProvider.allCases where tested != .onDevice {
            #expect(configNames.contains(tested.rawValue),
                    "\(tested.rawValue) must map to a ProviderConfiguration.Provider case")
        }
    }

    // MARK: - 11. ChatEngine Convenience Init Consistency

    @Test("ChatEngine convenience init with ProviderConfiguration works for all cloud providers")
    func chatEngineConvenienceInitWorks() throws {
        let db = try makeProviderTestDatabase()

        let configs: [ProviderConfiguration] = [
            .openAI(apiKey: "test", model: "gpt-4o"),
            .anthropic(apiKey: "test", model: "claude-sonnet-4-20250514"),
            .gemini(apiKey: "test", model: "gemini-2.0-flash"),
            .openAICompatible(apiKey: "test", model: "m", baseURL: URL(string: "http://localhost:1234")!),
            .ollama(model: "llama3.2"),
            .llamaCpp(model: "default"),
        ]

        for config in configs {
            // This should not throw — it only creates the engine, doesn't call the LLM
            let engine = ChatEngine(database: db, provider: config)
            #expect(engine.tableCount == nil, "tableCount should be nil before first query")
        }
    }

    // MARK: - 12. Availability Reporting

    @Test("All real provider models report available by default")
    func allModelsReportAvailable() {
        let models: [(String, any LanguageModel)] = [
            ("OpenAI", OpenAILanguageModel(apiKey: "k", model: "m")),
            ("Anthropic", AnthropicLanguageModel(apiKey: "k", model: "m")),
            ("Gemini", GeminiLanguageModel(apiKey: "k", model: "m")),
            ("Ollama", OllamaLanguageModel(model: "m")),
        ]

        for (name, model) in models {
            #expect(model.isAvailable, "\(name) should be available by default")
        }
    }

    // MARK: - 13. On-Device Pipeline Status

    @Test("On-device inference pipeline starts in notLoaded state")
    func onDevicePipelineInitialState() {
        let mlxPipeline = OnDeviceInferencePipeline(
            mlxConfiguration: .llama3_2_3B()
        )
        #expect(mlxPipeline.status == .notLoaded)
        #expect(mlxPipeline.providerType == .mlx)

        let coreMLPipeline = OnDeviceInferencePipeline(
            coreMLConfiguration: CoreMLProviderConfiguration(
                modelURL: URL(fileURLWithPath: "/tmp/test.mlmodelc")
            )
        )
        #expect(coreMLPipeline.status == .notLoaded)
        #expect(coreMLPipeline.providerType == .coreML)
    }

    @Test("On-device SQL generation hints are populated for both provider types")
    func onDeviceSQLHints() {
        let mlxPipeline = OnDeviceInferencePipeline(mlxConfiguration: .llama3_2_3B())
        let mlxHints = mlxPipeline.recommendedSQLGenerationHints
        #expect(mlxHints.maxTokens > 0)
        #expect(mlxHints.temperature >= 0)
        #expect(!mlxHints.systemPromptSuffix.isEmpty)

        let coreMLPipeline = OnDeviceInferencePipeline(
            coreMLConfiguration: CoreMLProviderConfiguration(
                modelURL: URL(fileURLWithPath: "/tmp/test.mlmodelc")
            )
        )
        let coreMLHints = coreMLPipeline.recommendedSQLGenerationHints
        #expect(coreMLHints.maxTokens > 0)
        #expect(coreMLHints.temperature >= 0)
        #expect(!coreMLHints.systemPromptSuffix.isEmpty)
    }
}
