# SwiftDBAI

Chat with any SQLite database using natural language.

<!-- badges -->
![Swift 6.1+](https://img.shields.io/badge/Swift-6.1+-orange.svg)
![Platforms](https://img.shields.io/badge/Platforms-iOS%2017%20|%20macOS%2014%20|%20visionOS%201-blue.svg)
![License](https://img.shields.io/badge/License-MIT-green.svg)

## Features

- Drop-in SwiftUI chat view (`DataChatView`) -- one line to add a database chat UI
- Headless `ChatEngine` for programmatic / non-UI use
- LLM-agnostic via [AnyLanguageModel](https://github.com/huggingface/AnyLanguageModel) -- works with OpenAI, Anthropic, Gemini, Ollama, llama.cpp, or any OpenAI-compatible endpoint
- Automatic schema introspection -- no manual annotations required
- Safety-first: read-only by default, operation allowlists, table-level mutation policies, destructive operation confirmation delegate
- Configurable query timeouts, context windows, and custom validators

## Installation

Add SwiftDBAI via Swift Package Manager:

```swift
dependencies: [
    .package(url: "https://github.com/<org>/SwiftDBAI.git", from: "1.0.0"),
]
```

Then add the dependency to your target:

```swift
.target(
    name: "MyApp",
    dependencies: ["SwiftDBAI"]
)
```

## Quick Start

Drop a full chat UI into any SwiftUI view with `DataChatView`:

```swift
import SwiftDBAI
import AnyLanguageModel

struct ContentView: View {
    var body: some View {
        DataChatView(
            databasePath: "/path/to/mydata.sqlite",
            model: OllamaLanguageModel(model: "llama3")
        )
    }
}
```

That's it. `DataChatView` opens the database, introspects the schema, and renders a chat interface. The default mode is **read-only** (SELECT only).

To pass an existing GRDB connection and customize behavior:

```swift
DataChatView(
    database: myDatabasePool,
    model: OpenAILanguageModel(apiKey: "sk-...", model: "gpt-4o"),
    allowlist: .standard,
    additionalContext: "This database stores a recipe app's data.",
    maxSummaryRows: 100
)
```

## Headless / Programmatic Use

Use `ChatEngine` directly when you don't need a UI:

```swift
import SwiftDBAI
import AnyLanguageModel
import GRDB

let pool = try DatabasePool(path: "/path/to/mydata.sqlite")
let engine = ChatEngine(
    database: pool,
    model: OpenAILanguageModel(apiKey: "sk-...", model: "gpt-4o")
)

let response = try await engine.send("How many users signed up this week?")
print(response.summary)   // "There were 42 new signups this week."
print(response.sql)        // Optional("SELECT COUNT(*) FROM users WHERE ...")
```

`ChatEngine` also accepts a `ProviderConfiguration` for convenience:

```swift
let engine = ChatEngine(
    database: pool,
    provider: .anthropic(apiKey: "sk-ant-...", model: "claude-sonnet-4-20250514")
)
```

For fine-grained control, pass a `ChatEngineConfiguration`:

```swift
var config = ChatEngineConfiguration(
    queryTimeout: 10,
    contextWindowSize: 20,
    maxSummaryRows: 100,
    additionalContext: "The 'status' column uses: 'active', 'inactive', 'suspended'."
)

let engine = ChatEngine(
    database: pool,
    model: model,
    allowlist: .standard,
    configuration: config
)
```

## Choosing a Provider

SwiftDBAI works with any provider supported by AnyLanguageModel. Use `ProviderConfiguration` factory methods or construct model instances directly.

```swift
// OpenAI
let config = ProviderConfiguration.openAI(apiKey: "sk-...", model: "gpt-4o")

// Anthropic
let config = ProviderConfiguration.anthropic(apiKey: "sk-ant-...", model: "claude-sonnet-4-20250514")

// Gemini
let config = ProviderConfiguration.gemini(apiKey: "AIza...", model: "gemini-2.0-flash")

// Ollama (local, no API key needed)
let config = ProviderConfiguration.ollama(model: "llama3.2")

// llama.cpp (local)
let config = ProviderConfiguration.llamaCpp(model: "default")

// Any OpenAI-compatible endpoint
let config = ProviderConfiguration.openAICompatible(
    apiKey: "your-key",
    model: "llama-3.1-70b",
    baseURL: URL(string: "https://api.together.xyz/v1/")!
)
```

Use with ChatEngine:

```swift
let engine = ChatEngine(database: pool, provider: config)
// or
let engine = ChatEngine(database: pool, model: config.makeModel())
```

API keys can also come from environment variables:

```swift
let config = ProviderConfiguration.fromEnvironment(
    provider: .openAI,
    environmentVariable: "OPENAI_API_KEY",
    model: "gpt-4o"
)
```

## Safety and Mutation Control

### Operation Allowlist

By default, only SELECT queries are allowed. Opt in to writes explicitly:

| Preset | Allowed Operations |
|---|---|
| `.readOnly` (default) | SELECT |
| `.standard` | SELECT, INSERT, UPDATE |
| `.unrestricted` | SELECT, INSERT, UPDATE, DELETE |

```swift
// Custom allowlist
let allowlist = OperationAllowlist([.select, .insert])
```

### Mutation Policy

For table-level control, use `MutationPolicy`:

```swift
// Allow INSERT and UPDATE only on specific tables
let policy = MutationPolicy(
    allowedOperations: [.insert, .update],
    allowedTables: ["orders", "order_items"]
)

let engine = ChatEngine(
    database: pool,
    model: model,
    mutationPolicy: policy
)
```

Presets: `.readOnly`, `.readWrite`, `.unrestricted`.

### Confirmation Delegate

Destructive operations (DELETE, DROP, ALTER, TRUNCATE) require confirmation through a `ToolExecutionDelegate`:

```swift
struct MyDelegate: ToolExecutionDelegate {
    func confirmDestructiveOperation(
        _ context: DestructiveOperationContext
    ) async -> Bool {
        // Present confirmation UI, return true to proceed
        return await showConfirmationDialog(context.description)
    }
}

let engine = ChatEngine(
    database: pool,
    model: model,
    allowlist: .unrestricted,
    delegate: MyDelegate()
)
```

Without a delegate, destructive operations throw `SwiftDBAIError.confirmationRequired` so you can handle confirmation in your own flow.

Built-in delegates: `AutoApproveDelegate` (testing only), `RejectAllDelegate` (safest).

## Architecture

```
User Question
    |
    v
ChatEngine
    |-- SchemaIntrospector   (auto-discovers tables, columns, keys, indexes)
    |-- PromptBuilder        (builds LLM system prompt with schema context)
    |-- LanguageModel        (generates SQL via AnyLanguageModel)
    |-- SQLQueryParser       (parses and validates against allowlist/policy)
    |-- QueryValidator       (optional custom validators)
    |-- GRDB                 (executes SQL against SQLite)
    |-- TextSummaryRenderer  (summarizes results via LLM)
    v
ChatResponse { summary, sql, queryResult }
```

`DataChatView` wraps this pipeline in a SwiftUI view with `ChatViewModel` managing state.

## Requirements

- iOS 17.0+ / macOS 14.0+ / visionOS 1.0+
- Swift 6.1+
- Xcode 16+

## License

MIT. See [LICENSE](LICENSE) for details.
