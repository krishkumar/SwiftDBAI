// ChatView.swift
// SwiftDBAI
//
// Drop-in SwiftUI view for chatting with a SQLite database.
// Renders messages with automatic data table display for query results.

import SwiftUI

/// A drop-in SwiftUI chat interface for querying SQLite databases
/// with natural language.
///
/// `ChatView` renders the full conversation including:
/// - User messages (right-aligned, accent-colored)
/// - Assistant responses with text summaries
/// - **Automatic data tables** via `ScrollableDataTableView` when query results
///   contain tabular data (rows + columns)
/// - SQL query disclosure for transparency
/// - Error messages with red styling
/// - A loading indicator while the engine is processing
///
/// Usage:
/// ```swift
/// let engine = ChatEngine(database: myPool, model: myModel)
/// let viewModel = ChatViewModel(engine: engine)
///
/// ChatView(viewModel: viewModel)
/// ```
///
/// Or use the convenience initializer:
/// ```swift
/// ChatView(engine: myEngine)
/// ```
@available(iOS 17.0, macOS 14.0, visionOS 1.0, *)
public struct ChatView: View {
    @Bindable private var viewModel: ChatViewModel
    @State private var inputText: String = ""
    @FocusState private var isInputFocused: Bool

    /// Creates a ChatView with an existing view model.
    ///
    /// - Parameter viewModel: The `ChatViewModel` driving this view.
    public init(viewModel: ChatViewModel) {
        self.viewModel = viewModel
    }

    /// Creates a ChatView with a `ChatEngine`, automatically creating
    /// a `ChatViewModel`.
    ///
    /// - Parameter engine: The `ChatEngine` to power the chat.
    public init(engine: ChatEngine) {
        self.viewModel = ChatViewModel(engine: engine)
    }

    public var body: some View {
        VStack(spacing: 0) {
            messageList
            Divider()
            inputBar
        }
    }

    // MARK: - Message List

    @ViewBuilder
    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 12) {
                    if viewModel.messages.isEmpty {
                        emptyState
                    }

                    ForEach(viewModel.messages) { message in
                        messageBubble(for: message)
                            .id(message.id)
                    }

                    if viewModel.isLoading {
                        loadingIndicator
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .onChange(of: viewModel.messages.count) { _, _ in
                if let lastMessage = viewModel.messages.last {
                    withAnimation(.easeOut(duration: 0.3)) {
                        proxy.scrollTo(lastMessage.id, anchor: .bottom)
                    }
                }
            }
        }
    }

    // MARK: - Empty State

    @ViewBuilder
    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "bubble.left.and.text.bubble.right")
                .font(.system(size: 40))
                .foregroundStyle(.tertiary)
            Text("Ask a question about your data")
                .font(.headline)
                .foregroundStyle(.secondary)
            Text("Try something like \"How many records are in the database?\"")
                .font(.subheadline)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }

    // MARK: - Loading Indicator

    @ViewBuilder
    private var loadingIndicator: some View {
        HStack(alignment: .top) {
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text("Querying…")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                Self.assistantBackgroundColor,
                in: RoundedRectangle(cornerRadius: 16, style: .continuous)
            )

            Spacer(minLength: 48)
        }
        .id("loading-indicator")
        .transition(.opacity.combined(with: .move(edge: .bottom)))
    }

    private static var assistantBackgroundColor: Color {
        #if os(macOS)
        Color(nsColor: .controlBackgroundColor)
        #else
        Color(uiColor: .secondarySystemGroupedBackground)
        #endif
    }

    // MARK: - Input Bar

    @ViewBuilder
    private var inputBar: some View {
        HStack(spacing: 8) {
            TextField("Ask about your data…", text: $inputText, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(1...5)
                .focused($isInputFocused)
                .onSubmit { sendMessage() }
                .submitLabel(.send)

            Button(action: sendMessage) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.title2)
                    .foregroundStyle(canSend ? Color.accentColor : Color.secondary)
            }
            .disabled(!canSend)
            .keyboardShortcut(.return, modifiers: .command)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    // MARK: - Message Bubble

    @ViewBuilder
    private func messageBubble(for message: ChatMessage) -> some View {
        if message.role == .error {
            MessageBubbleView(
                message: message,
                onRetry: makeRetryAction(for: message)
            )
        } else {
            MessageBubbleView(message: message)
        }
    }

    private func makeRetryAction(for errorMessage: ChatMessage) -> @Sendable () async -> Void {
        let vm = viewModel
        let messageId = errorMessage.id
        return { @MainActor [vm] in
            let allMessages = await MainActor.run { vm.messages }
            if let lastUserMessage = allMessages
                .prefix(while: { $0.id != messageId })
                .last(where: { $0.role == .user }) {
                await vm.send(lastUserMessage.content)
            }
        }
    }

    // MARK: - Helpers

    private var canSend: Bool {
        !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !viewModel.isLoading
    }

    private func sendMessage() {
        guard canSend else { return }
        let text = inputText
        inputText = ""

        Task {
            await viewModel.send(text)
        }
    }
}
