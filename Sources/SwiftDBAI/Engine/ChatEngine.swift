// ChatEngine.swift
// SwiftDBAI
//
// Orchestrates the conversation loop: user message → SQL generation → query
// execution → result summarization → response.

import AnyLanguageModel
import Foundation
import GRDB

/// A message in the chat conversation.
public struct ChatMessage: Sendable, Identifiable, Equatable {
    public let id: UUID
    public let role: Role
    public let content: String
    public let queryResult: QueryResult?
    public let sql: String?
    public let timestamp: Date
    /// The typed error, if this is an error message.
    public let error: SwiftDBAIError?

    public enum Role: String, Sendable, Equatable {
        case user
        case assistant
        case error
    }

    public init(
        id: UUID = UUID(),
        role: Role,
        content: String,
        queryResult: QueryResult? = nil,
        sql: String? = nil,
        timestamp: Date = Date(),
        error: SwiftDBAIError? = nil
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.queryResult = queryResult
        self.sql = sql
        self.timestamp = timestamp
        self.error = error
    }
}

/// The response returned by `ChatEngine.send(_:)`.
public struct ChatResponse: Sendable {
    /// The natural language summary of the result.
    public let summary: String

    /// The SQL that was generated and executed, if any.
    public let sql: String?

    /// The raw query result, if a query was executed.
    public let queryResult: QueryResult?
}

/// Headless engine that orchestrates the full chat-with-database pipeline.
///
/// The engine:
/// 1. Introspects the database schema (once, lazily)
/// 2. Builds a system prompt with schema context
/// 3. Sends the user's question to the LLM to generate SQL
/// 4. Validates the SQL against the operation allowlist
/// 5. Executes the SQL via GRDB
/// 6. Summarizes results using `TextSummaryRenderer`
/// 7. Returns the summary (and raw data) to the caller
///
/// Usage:
/// ```swift
/// let engine = ChatEngine(
///     database: myDatabasePool,
///     model: myLanguageModel
/// )
/// let response = try await engine.send("How many users signed up this week?")
/// print(response.summary) // "There were 42 new signups this week."
/// ```
public final class ChatEngine: @unchecked Sendable {

    // MARK: - Dependencies

    private let database: any DatabaseWriter
    private let model: any LanguageModel
    private let allowlist: OperationAllowlist
    private let mutationPolicy: MutationPolicy?
    private let configuration: ChatEngineConfiguration
    private let summaryRenderer: TextSummaryRenderer
    private let sqlParser: SQLQueryParser

    /// Optional delegate for intercepting destructive operations and observing SQL execution.
    private let delegate: (any ToolExecutionDelegate)?

    // MARK: - State

    private var schema: DatabaseSchema?
    private var conversationHistory: [ChatMessage] = []
    private let lock = NSLock()

    // MARK: - Initialization

    /// Creates a new ChatEngine with a full configuration object.
    ///
    /// - Parameters:
    ///   - database: A GRDB `DatabaseWriter` (DatabasePool or DatabaseQueue).
    ///   - model: Any `AnyLanguageModel`-compatible language model.
    ///   - allowlist: SQL operations the LLM may generate. Defaults to read-only (SELECT only).
    ///   - configuration: Engine configuration for timeouts, context window, validators, etc.
    ///   - delegate: Optional delegate for confirming destructive operations and observing SQL execution.
    public init(
        database: any DatabaseWriter,
        model: any LanguageModel,
        allowlist: OperationAllowlist = .readOnly,
        configuration: ChatEngineConfiguration = .default,
        delegate: (any ToolExecutionDelegate)? = nil
    ) {
        self.database = database
        self.model = model
        self.allowlist = allowlist
        self.mutationPolicy = nil
        self.configuration = configuration
        self.delegate = delegate
        self.summaryRenderer = TextSummaryRenderer(
            model: model,
            maxRowsInPrompt: configuration.maxSummaryRows
        )
        self.sqlParser = SQLQueryParser(allowlist: allowlist)
    }

    /// Creates a new ChatEngine with a `MutationPolicy` for table-level control.
    ///
    /// This initializer provides fine-grained control over which mutations are
    /// allowed on which tables. The policy's operation allowlist is used for
    /// SQL validation, and table-level restrictions are enforced during parsing.
    ///
    /// - Parameters:
    ///   - database: A GRDB `DatabaseWriter` (DatabasePool or DatabaseQueue).
    ///   - model: Any `AnyLanguageModel`-compatible language model.
    ///   - mutationPolicy: Controls which operations are allowed on which tables.
    ///   - configuration: Engine configuration for timeouts, context window, validators, etc.
    ///   - delegate: Optional delegate for confirming destructive operations and observing SQL execution.
    public init(
        database: any DatabaseWriter,
        model: any LanguageModel,
        mutationPolicy: MutationPolicy,
        configuration: ChatEngineConfiguration = .default,
        delegate: (any ToolExecutionDelegate)? = nil
    ) {
        self.database = database
        self.model = model
        self.allowlist = mutationPolicy.operationAllowlist
        self.mutationPolicy = mutationPolicy
        self.configuration = configuration
        self.delegate = delegate
        self.summaryRenderer = TextSummaryRenderer(
            model: model,
            maxRowsInPrompt: configuration.maxSummaryRows
        )
        self.sqlParser = SQLQueryParser(mutationPolicy: mutationPolicy)
    }

    /// Creates a new ChatEngine with individual parameters (convenience).
    ///
    /// - Parameters:
    ///   - database: A GRDB `DatabaseWriter` (DatabasePool or DatabaseQueue).
    ///   - model: Any `AnyLanguageModel`-compatible language model.
    ///   - allowlist: SQL operations the LLM may generate. Defaults to read-only (SELECT only).
    ///   - additionalContext: Optional extra instructions for the LLM system prompt.
    ///   - maxSummaryRows: Maximum rows to include when summarizing results (default: 50).
    public convenience init(
        database: any DatabaseWriter,
        model: any LanguageModel,
        allowlist: OperationAllowlist,
        additionalContext: String?,
        maxSummaryRows: Int = 50
    ) {
        let config = ChatEngineConfiguration(
            maxSummaryRows: maxSummaryRows,
            additionalContext: additionalContext
        )
        self.init(
            database: database,
            model: model,
            allowlist: allowlist,
            configuration: config
        )
    }

    // MARK: - Public API

    /// Sends a natural language message and returns a summarized response.
    ///
    /// This is the primary entry point. The engine will:
    /// 1. Introspect the schema if not yet cached
    /// 2. Ask the LLM to generate SQL
    /// 3. Validate the SQL against the allowlist and custom validators
    /// 4. Execute the SQL (with timeout if configured)
    /// 5. Summarize the results using `TextSummaryRenderer`
    ///
    /// All errors are caught and mapped to a distinct ``SwiftDBAIError`` case
    /// so callers always receive a typed, user-friendly error with a localized
    /// description suitable for display in a chat UI.
    ///
    /// - Parameter message: The user's natural language question or command.
    /// - Returns: A `ChatResponse` containing the summary, SQL, and raw result.
    /// - Throws: ``SwiftDBAIError`` for every failure mode.
    public func send(_ message: String) async throws -> ChatResponse {
        // 1. Ensure schema is introspected
        let schema: DatabaseSchema
        do {
            schema = try await ensureSchema()
        } catch let error as SwiftDBAIError {
            throw error
        } catch {
            throw SwiftDBAIError.schemaIntrospectionFailed(reason: error.localizedDescription)
        }

        // Check for empty schema
        if schema.tableNames.isEmpty {
            throw SwiftDBAIError.emptySchema
        }

        // 2. Build prompt and get raw LLM response
        let promptBuilder = PromptBuilder(
            schema: schema,
            allowlist: allowlist,
            additionalContext: configuration.additionalContext
        )

        let rawLLMResponse: String
        do {
            rawLLMResponse = try await generateRawResponse(
                question: message,
                promptBuilder: promptBuilder
            )
        } catch let error as SwiftDBAIError {
            throw error
        } catch {
            throw SwiftDBAIError.llmFailure(reason: error.localizedDescription)
        }

        // 3. Parse and validate SQL through SQLQueryParser
        let parsed: ParsedSQL
        do {
            parsed = try sqlParser.parse(rawLLMResponse)
        } catch let error as SQLParsingError {
            throw error.toSwiftDBAIError(rawResponse: rawLLMResponse)
        } catch let error as SwiftDBAIError {
            throw error
        } catch {
            throw SwiftDBAIError.invalidSQL(sql: rawLLMResponse, reason: error.localizedDescription)
        }

        // 4. Run custom validators
        do {
            try runCustomValidators(parsed: parsed)
        } catch let error as QueryValidationError {
            throw error
        } catch let error as SwiftDBAIError {
            throw error
        } catch {
            throw SwiftDBAIError.queryRejected(reason: error.localizedDescription)
        }

        // 5. Handle confirmation-required operations (DELETE, DROP, etc.)
        if parsed.requiresConfirmation {
            if let delegate = self.delegate {
                // Build context for the delegate
                let classification = classifySQL(parsed.sql)
                let context = DestructiveOperationContext(
                    sql: parsed.sql,
                    statementKind: detectStatementKind(parsed.sql) ?? .delete,
                    classification: classification,
                    description: "Execute \(parsed.operation.rawValue.uppercased()) operation: \(parsed.sql)",
                    targetTable: extractTargetTableForDelegate(from: parsed.sql, operation: parsed.operation)
                )
                // Ask the delegate for approval
                let approved = await delegate.confirmDestructiveOperation(context)
                if !approved {
                    throw SwiftDBAIError.confirmationRequired(
                        sql: parsed.sql,
                        operation: parsed.operation.rawValue
                    )
                }
                // Delegate approved — fall through to execution
            } else {
                // No delegate — throw confirmation required so caller can handle it
                throw SwiftDBAIError.confirmationRequired(
                    sql: parsed.sql,
                    operation: parsed.operation.rawValue
                )
            }
        }

        // 6. Execute the SQL (with timeout if configured)
        let result: QueryResult
        do {
            let classification = classifySQL(parsed.sql)
            await delegate?.willExecuteSQL(parsed.sql, classification: classification)
            result = try await executeSQLWithTimeout(parsed.sql)
            await delegate?.didExecuteSQL(parsed.sql, success: true)
        } catch let error as SwiftDBAIError {
            await delegate?.didExecuteSQL(parsed.sql, success: false)
            throw error
        } catch let error as ChatEngineError {
            await delegate?.didExecuteSQL(parsed.sql, success: false)
            // Map internal ChatEngineError (e.g. from timeout) to SwiftDBAIError
            throw error.toSwiftDBAIError()
        } catch {
            await delegate?.didExecuteSQL(parsed.sql, success: false)
            throw SwiftDBAIError.databaseError(reason: error.localizedDescription)
        }

        // 7. Summarize the result using TextSummaryRenderer
        let summary: String
        do {
            summary = try await summaryRenderer.summarize(
                result: result,
                userQuestion: message
            )
        } catch let error as SwiftDBAIError {
            throw error
        } catch {
            throw SwiftDBAIError.llmFailure(reason: "Summarization failed: \(error.localizedDescription)")
        }

        // 8. Record conversation history
        let userMessage = ChatMessage(role: .user, content: message)
        let assistantMessage = ChatMessage(
            role: .assistant,
            content: summary,
            queryResult: result,
            sql: parsed.sql
        )
        lock.withLock {
            conversationHistory.append(userMessage)
            conversationHistory.append(assistantMessage)
        }

        return ChatResponse(
            summary: summary,
            sql: parsed.sql,
            queryResult: result
        )
    }

    /// Sends a natural language message, executing a previously confirmed destructive operation.
    ///
    /// Call this after receiving a `confirmationRequired` error and the user has confirmed.
    ///
    /// - Parameters:
    ///   - message: The original user message (for history recording).
    ///   - confirmedSQL: The SQL that was confirmed by the user.
    /// - Returns: A `ChatResponse` with the result.
    public func sendConfirmed(_ message: String, confirmedSQL: String) async throws -> ChatResponse {
        let result: QueryResult
        do {
            let classification = classifySQL(confirmedSQL)
            await delegate?.willExecuteSQL(confirmedSQL, classification: classification)
            result = try await executeSQLWithTimeout(confirmedSQL)
            await delegate?.didExecuteSQL(confirmedSQL, success: true)
        } catch let error as SwiftDBAIError {
            await delegate?.didExecuteSQL(confirmedSQL, success: false)
            throw error
        } catch let error as ChatEngineError {
            await delegate?.didExecuteSQL(confirmedSQL, success: false)
            throw error.toSwiftDBAIError()
        } catch {
            await delegate?.didExecuteSQL(confirmedSQL, success: false)
            throw SwiftDBAIError.databaseError(reason: error.localizedDescription)
        }

        let summary: String
        do {
            summary = try await summaryRenderer.summarize(
                result: result,
                userQuestion: message
            )
        } catch let error as SwiftDBAIError {
            throw error
        } catch {
            throw SwiftDBAIError.llmFailure(reason: "Summarization failed: \(error.localizedDescription)")
        }

        let userMessage = ChatMessage(role: .user, content: message)
        let assistantMessage = ChatMessage(
            role: .assistant,
            content: summary,
            queryResult: result,
            sql: confirmedSQL
        )
        lock.withLock {
            conversationHistory.append(userMessage)
            conversationHistory.append(assistantMessage)
        }

        return ChatResponse(
            summary: summary,
            sql: confirmedSQL,
            queryResult: result
        )
    }

    /// Returns the current conversation history.
    public var messages: [ChatMessage] {
        lock.lock()
        defer { lock.unlock() }
        return conversationHistory
    }

    /// Eagerly introspects the database schema so it's ready before the first query.
    ///
    /// Call this at view-appear time to pre-warm the schema cache. If the schema
    /// is already cached, this returns immediately. The returned `DatabaseSchema`
    /// can be used to display table/column info in the UI.
    ///
    /// - Returns: The introspected `DatabaseSchema`.
    @discardableResult
    public func prepareSchema() async throws -> DatabaseSchema {
        try await ensureSchema()
    }

    /// The number of tables discovered during schema introspection.
    /// Returns `nil` if the schema has not been introspected yet.
    public var tableCount: Int? {
        lock.withLock { schema?.tableNames.count }
    }

    /// The cached schema, if introspection has completed.
    public var cachedSchema: DatabaseSchema? {
        lock.withLock { schema }
    }

    /// Clears the conversation history and cached schema.
    ///
    /// After calling this, the next `send(_:)` call will re-introspect the
    /// schema. Use ``clearHistory()`` if you only want to reset the conversation
    /// while keeping the cached schema.
    public func reset() {
        lock.withLock {
            conversationHistory.removeAll()
            schema = nil
        }
    }

    /// Clears only the conversation history, keeping the cached schema.
    ///
    /// This is useful when you want to start a fresh conversation thread
    /// without re-introspecting the database. The schema cache remains valid
    /// as long as the database structure hasn't changed.
    public func clearHistory() {
        lock.withLock {
            conversationHistory.removeAll()
        }
    }

    /// The current engine configuration.
    public var currentConfiguration: ChatEngineConfiguration {
        configuration
    }

    // MARK: - Internal Helpers (visible for testing)

    /// Ensures the database schema is introspected and cached.
    func ensureSchema() async throws -> DatabaseSchema {
        if let cached = lock.withLock({ schema }) {
            return cached
        }

        let introspected = try await SchemaIntrospector.introspect(database: database)

        lock.withLock { schema = introspected }

        return introspected
    }

    /// Asks the LLM to generate SQL from a natural language question.
    /// Returns the raw LLM response text (before parsing).
    ///
    /// Uses the configured ``ChatEngineConfiguration/contextWindowSize`` to limit
    /// how many conversation messages are included as context for the LLM.
    private func generateRawResponse(
        question: String,
        promptBuilder: PromptBuilder
    ) async throws -> String {
        let instructions = promptBuilder.buildSystemInstructions()

        // Build user prompt — include full conversation history for follow-ups
        // Respect context window: only use recent messages for context
        let userPrompt: String
        let historySlice = lock.withLock { () -> [ChatMessage] in
            Array(contextWindowSlice())
        }

        if historySlice.isEmpty {
            userPrompt = promptBuilder.buildUserPrompt(question)
        } else {
            userPrompt = promptBuilder.buildConversationPrompt(
                question,
                history: historySlice
            )
        }

        let session = LanguageModelSession(
            model: model,
            instructions: instructions + "\n\nCRITICAL: Respond with ONLY the raw SQL query. Do NOT wrap in markdown code fences or backticks. Do NOT include any explanation, comments, or formatting. The output must be directly executable SQL and nothing else."
        )

        // Structured output mode: uses @Generable to get JSON-constrained SQL.
        // Eliminates parsing issues but requires model support.
        if configuration.useStructuredOutput {
            let structured = try await session.respond(
                to: Prompt(userPrompt),
                generating: StructuredSQLOutput.self
            )
            return structured.content.sql.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        // Default: plain text response, parsed by SQLQueryParser
        let response = try await session.respond(to: userPrompt)
        return response.content.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Returns the conversation history slice within the configured context window.
    /// Must be called within a `lock.withLock` closure.
    private func contextWindowSlice() -> ArraySlice<ChatMessage> {
        guard let windowSize = configuration.contextWindowSize else {
            return conversationHistory[...]
        }
        let count = conversationHistory.count
        let start = max(0, count - windowSize)
        return conversationHistory[start...]
    }

    /// Runs all custom validators from the configuration against the parsed SQL.
    private func runCustomValidators(parsed: ParsedSQL) throws {
        for validator in configuration.validators {
            try validator.validate(sql: parsed.sql, operation: parsed.operation)
        }
    }

    /// Extracts the target table name from a SQL statement for delegate context.
    private func extractTargetTableForDelegate(from sql: String, operation: SQLOperation) -> String? {
        let pattern: String
        switch operation {
        case .insert:
            pattern = #"INSERT\s+INTO\s+[`"\[]?(\w+)[`"\]]?"#
        case .update:
            pattern = #"UPDATE\s+[`"\[]?(\w+)[`"\]]?"#
        case .delete:
            pattern = #"DELETE\s+FROM\s+[`"\[]?(\w+)[`"\]]?"#
        case .select:
            return nil
        }
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else {
            return nil
        }
        let range = NSRange(sql.startIndex..., in: sql)
        guard let match = regex.firstMatch(in: sql, range: range),
              match.numberOfRanges > 1,
              let groupRange = Range(match.range(at: 1), in: sql) else {
            return nil
        }
        return String(sql[groupRange])
    }

    /// Executes SQL with the configured timeout, if any.
    private func executeSQLWithTimeout(_ sql: String) async throws -> QueryResult {
        guard let timeout = configuration.queryTimeout else {
            return try await executeSQL(sql)
        }

        return try await withThrowingTaskGroup(of: QueryResult.self) { group in
            group.addTask {
                try await self.executeSQL(sql)
            }

            group.addTask {
                try await Task.sleep(for: .seconds(timeout))
                throw ChatEngineError.queryTimedOut(seconds: timeout)
            }

            // Return whichever finishes first
            let result = try await group.next()!
            group.cancelAll()
            return result
        }
    }

    /// Executes SQL against the database and returns a `QueryResult`.
    private func executeSQL(_ sql: String) async throws -> QueryResult {
        let trimmed = sql.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let isSelect = trimmed.hasPrefix("SELECT") || trimmed.hasPrefix("WITH")

        let startTime = CFAbsoluteTimeGetCurrent()

        if isSelect {
            let result = try await database.read { db -> (columns: [String], rows: [[String: QueryResult.Value]]) in
                let statement = try db.makeStatement(sql: sql)
                let columnNames = statement.columnNames

                var rows: [[String: QueryResult.Value]] = []
                let cursor = try Row.fetchCursor(statement)
                while let row = try cursor.next() {
                    var dict: [String: QueryResult.Value] = [:]
                    for col in columnNames {
                        dict[col] = Self.extractValue(row: row, column: col)
                    }
                    rows.append(dict)
                }
                return (columns: columnNames, rows: rows)
            }

            let elapsed = CFAbsoluteTimeGetCurrent() - startTime

            return QueryResult(
                columns: result.columns,
                rows: result.rows,
                sql: sql,
                executionTime: elapsed
            )
        } else {
            // Mutation query
            let affected = try await database.write { db -> Int in
                try db.execute(sql: sql)
                return db.changesCount
            }

            let elapsed = CFAbsoluteTimeGetCurrent() - startTime

            return QueryResult(
                columns: [],
                rows: [],
                sql: sql,
                executionTime: elapsed,
                rowsAffected: affected
            )
        }
    }

    /// Extracts a `QueryResult.Value` from a GRDB `Row` for the given column.
    private static func extractValue(row: Row, column: String) -> QueryResult.Value {
        let dbValue: DatabaseValue = row[column]
        switch dbValue.storage {
        case .null:
            return .null
        case .int64(let i):
            return .integer(i)
        case .double(let d):
            return .real(d)
        case .string(let s):
            return .text(s)
        case .blob(let data):
            return .blob(data)
        }
    }
}

// MARK: - Errors

/// Errors that can occur during ChatEngine operations.
public enum ChatEngineError: Error, LocalizedError, Sendable {
    /// SQL parsing/extraction from LLM response failed.
    case sqlParsingFailed(SQLParsingError)
    /// A destructive operation requires user confirmation before execution.
    case confirmationRequired(sql: String, operation: SQLOperation)
    /// Schema introspection failed.
    case schemaIntrospectionFailed(String)
    /// The SQL query exceeded the configured timeout.
    case queryTimedOut(seconds: TimeInterval)
    /// A custom query validator rejected the query.
    case validationFailed(String)

    public var errorDescription: String? {
        switch self {
        case .sqlParsingFailed(let parsingError):
            return "SQL parsing failed: \(parsingError.description)"
        case .confirmationRequired(let sql, let op):
            return "The \(op.rawValue.uppercased()) operation requires confirmation: \(sql)"
        case .schemaIntrospectionFailed(let reason):
            return "Failed to introspect database schema: \(reason)"
        case .queryTimedOut(let seconds):
            return "Query timed out after \(Int(seconds)) seconds."
        case .validationFailed(let reason):
            return "Query validation failed: \(reason)"
        }
    }
}
