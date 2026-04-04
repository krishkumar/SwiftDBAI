// SwiftDBAIDemoApp.swift
// SwiftDBAIDemo
//
// Showcase app demonstrating all SwiftDBAI UI variants and presentation modes.

import SwiftUI
import SwiftDBAI

@main
struct SwiftDBAIDemoApp: App {
    @State private var databasePath: String?
    @State private var setupError: String?

    private let context = """
        This is a database of the top ~2000 most-starred GitHub \
        repositories. Each repo has: full_name (owner/name), stars, \
        forks, language (programming language), description, \
        open_issues, created_at date, and topics. \
        Star counts are real and current as of April 2026.
        """

    var body: some Scene {
        WindowGroup {
            Group {
                if let path = databasePath {
                    ShowcaseTabView(databasePath: path, context: context)
                } else if let error = setupError {
                    ContentUnavailableView(
                        "Database Setup Failed",
                        systemImage: "exclamationmark.triangle",
                        description: Text(error)
                    )
                } else {
                    ProgressView("Setting up database...")
                }
            }
            .task {
                do {
                    let path = try DatabaseSeeder.seedIfNeeded()
                    databasePath = path
                } catch {
                    setupError = error.localizedDescription
                }
            }
        }
    }
}

struct ShowcaseTabView: View {
    let databasePath: String
    let context: String
    @State private var showSheet = false
    @State private var showFullScreen = false

    var body: some View {
        TabView {
            // Tab 1: Default theme
            DataChatView(
                databasePath: databasePath,
                model: DemoLanguageModel(),
                allowlist: .readOnly,
                additionalContext: context
            )
            .tabItem { Label("Default", systemImage: "bubble.left.and.text.bubble.right") }

            // Tab 2: Dark theme
            DataChatView(
                databasePath: databasePath,
                model: DemoLanguageModel(),
                allowlist: .readOnly,
                additionalContext: context
            )
            .chatViewConfiguration(.dark)
            .tabItem { Label("Dark", systemImage: "moon.fill") }

            // Tab 3: Compact theme
            DataChatView(
                databasePath: databasePath,
                model: DemoLanguageModel(),
                allowlist: .readOnly,
                additionalContext: context
            )
            .chatViewConfiguration(.compact)
            .tabItem { Label("Compact", systemImage: "rectangle.compress.vertical") }

            // Tab 4: Custom styling
            DataChatView(
                databasePath: databasePath,
                model: DemoLanguageModel(),
                allowlist: .readOnly,
                additionalContext: context
            )
            .chatViewConfiguration(customConfig)
            .tabItem { Label("Custom", systemImage: "paintbrush") }

            // Tab 5: Presentation modes
            PresentationShowcase(databasePath: databasePath, context: context)
                .tabItem { Label("Present", systemImage: "rectangle.portrait.and.arrow.forward") }

            // Tab 6: Tool calling API
            ToolDemoView(databasePath: databasePath)
                .tabItem { Label("Tool", systemImage: "wrench") }
        }
    }

    private var customConfig: ChatViewConfiguration {
        var config = ChatViewConfiguration.default
        config.userBubbleColor = .purple
        config.userTextColor = .white
        config.accentColor = .purple
        config.inputPlaceholder = "Search GitHub repos..."
        config.emptyStateTitle = "Explore GitHub Data"
        config.emptyStateSubtitle = "Ask about stars, forks, languages, and trends"
        config.emptyStateIcon = "star.circle"
        config.assistantAvatarIcon = "sparkles"
        config.assistantAvatarColor = .purple
        return config
    }
}

struct PresentationShowcase: View {
    let databasePath: String
    let context: String
    @State private var showSheet = false
    @State private var showFullScreen = false

    var body: some View {
        NavigationStack {
            List {
                Section("Sheet Presentations") {
                    Button("Show as Sheet") {
                        showSheet = true
                    }
                    Button("Show Full Screen") {
                        showFullScreen = true
                    }
                }
                Section("Navigation") {
                    NavigationLink("Push DataChatView") {
                        DataChatView(
                            databasePath: databasePath,
                            model: DemoLanguageModel(),
                            allowlist: .readOnly,
                            additionalContext: context
                        )
                        .navigationTitle("Chat")
                    }
                }
                Section("Info") {
                    LabeledContent("DataChatSheet", value: "Nav + Done button")
                    LabeledContent("DataChatViewController", value: "UIKit bridge")
                    LabeledContent(".dataChatSheet()", value: "View modifier")
                    LabeledContent(".dataChatFullScreen()", value: "View modifier")
                }
            }
            .navigationTitle("Presentation Modes")
        }
        .sheet(isPresented: $showSheet) {
            DataChatSheet(
                databasePath: databasePath,
                model: DemoLanguageModel(),
                additionalContext: context,
                title: "GitHub Stars"
            )
        }
        .dataChatFullScreen(
            isPresented: $showFullScreen,
            databasePath: databasePath,
            model: DemoLanguageModel(),
            additionalContext: context
        )
    }
}

struct ToolDemoView: View {
    let databasePath: String
    @State private var tool: DatabaseTool?
    @State private var sqlInput = "SELECT full_name, stars FROM repos ORDER BY stars DESC LIMIT 5"
    @State private var result: ToolResult?
    @State private var error: String?
    @State private var showSchema = false

    var body: some View {
        NavigationStack {
            List {
                if let tool {
                    Section("Schema") {
                        Button(showSchema ? "Hide Schema" : "Show Schema") {
                            showSchema.toggle()
                        }
                        if showSchema {
                            Text(tool.schemaContext)
                                .font(.caption2.monospaced())
                        }
                    }

                    Section("SQL Query") {
                        TextField("Enter SQL", text: $sqlInput, axis: .vertical)
                            .font(.footnote.monospaced())
                            .lineLimit(3...6)
                        Button("Execute") {
                            do {
                                result = try tool.execute(sql: sqlInput)
                                error = nil
                            } catch {
                                self.error = error.localizedDescription
                                result = nil
                            }
                        }
                        .disabled(sqlInput.isEmpty)
                    }

                    if let error {
                        Section("Error") {
                            Text(error)
                                .foregroundStyle(.red)
                                .font(.footnote)
                        }
                    }

                    if let result {
                        Section("Result (\(result.rowCount) rows, \(String(format: "%.1fms", result.executionTime * 1000)))") {
                            Text(result.markdownTable)
                                .font(.caption2.monospaced())
                        }
                        Section("JSON Response") {
                            Text(result.jsonString)
                                .font(.caption2.monospaced())
                                .lineLimit(15)
                        }
                    }

                    Section("OpenAI Tool Definition") {
                        Text(toolDefinitionJSON(tool))
                            .font(.caption2.monospaced())
                            .lineLimit(10)
                    }
                } else {
                    ProgressView("Loading database...")
                }
            }
            .navigationTitle("DatabaseTool API")
        }
        .task {
            do {
                tool = try await DatabaseTool(databasePath: databasePath)
            } catch {
                self.error = error.localizedDescription
            }
        }
    }

    private func toolDefinitionJSON(_ tool: DatabaseTool) -> String {
        let def = tool.openAIFunctionDefinition
        if let data = try? JSONSerialization.data(withJSONObject: def, options: [.prettyPrinted, .sortedKeys]),
           let str = String(data: data, encoding: .utf8) {
            return str
        }
        return "{}"
    }
}
