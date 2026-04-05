/// Builds structured LLM prompts for SQL generation from a database schema
/// and natural language input.
///
/// `PromptBuilder` is the bridge between the introspected database schema and
/// the LLM. It produces two things:
/// 1. A **system instructions** string containing schema context and behavioral rules
/// 2. A **user prompt** string wrapping the natural language question
///
/// Usage:
/// ```swift
/// let builder = PromptBuilder(schema: mySchema, allowlist: .readOnly)
/// let instructions = builder.buildSystemInstructions()
/// let prompt = builder.buildUserPrompt("How many users signed up this week?")
/// ```
public struct PromptBuilder: Sendable {
    /// The database schema to include as context.
    public let schema: DatabaseSchema

    /// Which SQL operations the LLM may generate.
    public let allowlist: OperationAllowlist

    /// Optional additional context to append to the system instructions
    /// (e.g., business-specific terminology or query hints).
    public let additionalContext: String?

    /// Creates a prompt builder for the given schema and allowlist.
    ///
    /// - Parameters:
    ///   - schema: The introspected database schema.
    ///   - allowlist: Permitted SQL operations. Defaults to ``OperationAllowlist/readOnly``.
    ///   - additionalContext: Extra instructions appended to the system prompt.
    public init(
        schema: DatabaseSchema,
        allowlist: OperationAllowlist = .readOnly,
        additionalContext: String? = nil
    ) {
        self.schema = schema
        self.allowlist = allowlist
        self.additionalContext = additionalContext
    }

    // MARK: - System Instructions

    /// Builds the system instructions string that should be passed as the
    /// `instructions` parameter when creating a `LanguageModelSession`.
    ///
    /// The instructions include:
    /// - Role definition
    /// - The full database schema
    /// - SQL generation rules and constraints
    /// - The operation allowlist
    /// - Output format requirements
    public func buildSystemInstructions() -> String {
        var sections: [String] = []

        // 1. Role
        sections.append(Self.roleSection)

        // 2. Schema
        sections.append(buildSchemaSection())

        // 3. Operation permissions
        sections.append(buildPermissionsSection())

        // 4. SQL generation rules
        sections.append(Self.sqlRulesSection)

        // 5. Output format
        sections.append(Self.outputFormatSection)

        // 6. Additional context
        if let additionalContext, !additionalContext.isEmpty {
            sections.append("ADDITIONAL CONTEXT\n=================\n\(additionalContext)")
        }

        return sections.joined(separator: "\n\n")
    }

    // MARK: - User Prompt

    /// Wraps a natural language question into a user prompt string.
    ///
    /// - Parameter question: The user's natural language question.
    /// - Returns: A formatted prompt string for the LLM.
    public func buildUserPrompt(_ question: String) -> String {
        question
    }

    /// Builds a follow-up prompt that includes prior SQL context for
    /// multi-turn conversations.
    ///
    /// - Parameters:
    ///   - question: The user's follow-up question.
    ///   - previousSQL: The SQL from the previous turn, for context.
    ///   - previousResultSummary: A brief summary of what the previous query returned.
    /// - Returns: A formatted prompt string.
    public func buildFollowUpPrompt(
        _ question: String,
        previousSQL: String,
        previousResultSummary: String
    ) -> String {
        """
        Previous query: \(previousSQL)
        Previous result: \(previousResultSummary)

        Follow-up question: \(question)
        """
    }

    /// Builds a prompt that includes the full conversation history within the
    /// configured context window, enabling the LLM to resolve follow-up
    /// references (pronouns, implicit table/column references, etc.).
    ///
    /// - Parameters:
    ///   - question: The user's current question.
    ///   - history: The conversation history messages within the context window.
    /// - Returns: A formatted prompt string with conversation context.
    public func buildConversationPrompt(
        _ question: String,
        history: [ChatMessage]
    ) -> String {
        guard !history.isEmpty else {
            return buildUserPrompt(question)
        }

        var lines: [String] = []
        lines.append("CONVERSATION HISTORY")
        lines.append("====================")

        for message in history {
            switch message.role {
            case .user:
                lines.append("User: \(message.content)")
            case .assistant:
                if let sql = message.sql {
                    lines.append("Assistant SQL: \(sql)")
                }
                lines.append("Assistant: \(message.content)")
            case .error:
                lines.append("Error: \(message.content)")
            }
        }

        lines.append("")
        lines.append("CURRENT QUESTION")
        lines.append("================")
        lines.append(question)

        return lines.joined(separator: "\n")
    }

    // MARK: - Private Sections

    private func buildSchemaSection() -> String {
        var lines: [String] = []
        lines.append("DATABASE SCHEMA")
        lines.append("===============")
        lines.append("")
        lines.append(schema.schemaDescription)
        return lines.joined(separator: "\n")
    }

    private func buildPermissionsSection() -> String {
        var lines: [String] = []
        lines.append("PERMISSIONS")
        lines.append("===========")
        lines.append(allowlist.describeForLLM())
        return lines.joined(separator: "\n")
    }

    // MARK: - Static Content

    static let roleSection = """
        ROLE
        ====
        You are a SQL assistant for a SQLite database. Your job is to translate \
        natural language questions into valid SQLite SQL queries based on the \
        database schema provided below. You must ONLY reference tables and columns \
        that exist in the schema. Never fabricate table or column names.
        """

    static let sqlRulesSection = """
        SQL GENERATION RULES
        ====================
        1. Use ONLY the tables and columns listed in the schema above.
        2. Use SQLite-compatible syntax (e.g., || for string concatenation, \
        IFNULL instead of COALESCE where needed).
        3. Use appropriate JOINs when queries span multiple tables — reference \
        the foreign key relationships in the schema.
        4. For date/time operations, use SQLite date functions \
        (date(), time(), datetime(), strftime()).
        5. Use parameterized-style values where possible. For literal values \
        from the user's question, embed them directly in the SQL.
        6. Always include an ORDER BY clause when the user implies ordering.
        7. Use LIMIT when the user asks for "top N" or "first N" results.
        8. For aggregate queries (count, sum, average, min, max), use the \
        appropriate SQL aggregate functions.
        9. When the user's question is ambiguous, prefer the simplest valid \
        interpretation.
        10. Never generate DDL statements (CREATE, ALTER, DROP TABLE).
        """

    static let outputFormatSection = """
        OUTPUT FORMAT
        =============
        Output ONLY the raw SQL query. \
        Do NOT wrap the SQL in markdown code fences or backticks. \
        Do NOT include any explanation, comments, or formatting before or after the SQL. \
        Do NOT prefix with labels like "SQL:" or "Query:". \
        The output should be directly executable SQL — nothing else.
        """
}
