import SwiftUI

struct OverviewView: View {
    @Environment(InstanceStore.self) private var store
    @State private var workspace: WorkspaceConnection?

    var body: some View {
        NavigationStack {
            Group {
                if let workspace {
                    List {
                        ForEach(workspace.conversations) { conversation in
                        NavigationLink { OperatorConversationView(conversation: conversation, workspace: workspace) } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(conversation.title.isEmpty ? localized("Untitled conversation", "未命名会话") : conversation.title).font(.headline)
                                Text(conversation.lastMessagePreview.isEmpty ? conversation.lastUserText : conversation.lastMessagePreview).lineLimit(2).foregroundStyle(.secondary)
                                Text(conversation.status).font(.caption).foregroundStyle(.tertiary)
                            }.padding(.vertical, 4)
                        }
                        }
                        if workspace.hasMore { Button(localized("Load More Conversations", "加载更多会话")) { workspace.loadMore() }.disabled(workspace.loadingMore || workspace.state != .connected) }
                    }
                    .overlay { if workspace.conversations.isEmpty { ContentUnavailableView(localized("No conversations", "暂无会话"), systemImage: "bubble.left.and.bubble.right") } }
                    .safeAreaInset(edge: .bottom) { connectionStatus(workspace) }
                    .alert(localized("Workspace action failed", "工作台操作失败"), isPresented: Binding(get: { workspace.lastError != nil }, set: { if !$0 { workspace.lastError = nil } })) {
                        Button(localized("OK", "好"), role: .cancel) { workspace.lastError = nil }
                    } message: { Text(workspace.lastError ?? "") }
                } else { ProgressView() }
            }
            .navigationTitle(localized("Workspace", "工作台"))
            .task { await startWorkspace() }
            .onDisappear { workspace?.disconnect() }
        }
    }

    @ViewBuilder private func connectionStatus(_ workspace: WorkspaceConnection) -> some View {
        switch workspace.state {
        case .connected: EmptyView()
        case .connecting: Label(localized("Connecting…", "正在连接…"), systemImage: "antenna.radiowaves.left.and.right").font(.caption).padding(8).glassEffect()
        case .failed(let message): Label(message, systemImage: "wifi.exclamationmark").font(.caption).padding(8).glassEffect()
        case .disconnected: EmptyView()
        }
    }

    private func startWorkspace() async {
        if let workspace { workspace.connect(); return }
        guard let client = store.client(), let instance = store.selected, let user = store.sessionUser else { return }
        let connection = WorkspaceConnection(client: client, instance: instance, userID: user.id)
        workspace = connection
        connection.connect()
    }
}

private struct OperatorConversationView: View {
    let conversation: WorkspaceConversation
    let workspace: WorkspaceConnection
    @Environment(InstanceStore.self) private var store
    @Environment(\.scenePhase) private var scenePhase
    @State private var draft = WorkspaceComposerDraft()
    @State private var sending = false
    @State private var ai = AIComposerController()
    @State private var showingAISettings = false
    @State private var skipAutomaticOnce = false

    private var input: AICompletionInput {
        .make(conversation: conversation, items: workspace.timelines[conversation.id] ?? [], mode: draft.mode, draft: draft.text, toolName: draft.toolName, toolCallID: draft.toolCallID, instruction: draft.aiInstruction)
    }
    private var requestIsCurrent: Bool {
        guard let current = workspace.conversations.first(where: { $0.id == conversation.id }) else { return false }
        return current.requestID == conversation.requestID && !current.requestID.isEmpty && ["waiting", "streaming"].contains(current.status)
    }
    private var canSend: Bool {
        guard !sending, requestIsCurrent, workspace.state == .connected,
              !draft.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        if draft.mode == .toolCall { return !draft.toolName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !draft.toolCallID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        if draft.mode == .toolOutput { return !draft.toolCallID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        return true
    }

    var body: some View {
        List(workspace.timelines[conversation.id] ?? []) { item in
            if let message = item.message {
                HStack {
                    if message.role == "assistant" { Spacer(minLength: 36) }
                    VStack(alignment: .leading, spacing: 4) {
                        Text(message.role == "assistant" ? localized("You", "你") : localized("Caller", "调用方")).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        Text(message.content)
                        ForEach(Array((message.contentParts ?? []).enumerated()), id: \.offset) { _, part in
                            if let text = part.text, !text.isEmpty, text != message.content { Text(text) }
                            if let source = part.src { WorkspaceMediaView(source: source, mediaType: part.mediaType, workspace: workspace) }
                        }
                    }.padding(12).background(message.role == "assistant" ? Color.cyan.opacity(0.16) : Color.secondary.opacity(0.10), in: RoundedRectangle(cornerRadius: 18))
                    if message.role != "assistant" { Spacer(minLength: 36) }
                }.listRowSeparator(.hidden).listRowBackground(Color.clear)
            }
        }
        .listStyle(.plain).scrollDismissesKeyboard(.interactively)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            MessageComposerView(mode: $draft.mode, text: Binding(get: { draft.text }, set: { draft.text = $0 }), toolName: $draft.toolName, toolCallID: $draft.toolCallID, instruction: $draft.aiInstruction,
                tools: input.tools, canSend: canSend, sending: sending, isGenerating: ai.isGenerating,
                configured: ai.configuration != nil, automatic: ai.configuration?.automatic ?? false,
                suggestion: ai.suggestion, aiError: ai.error, requestIsCurrent: requestIsCurrent,
                onSend: { Task { await send() } }, onGenerate: generate, onCancel: { ai.cancel() }, onApply: applySuggestion,
                onConfigure: { showingAISettings = true }, onAutomatic: { ai.setAutomatic($0); scheduleAutomatic() })
        }
        .navigationTitle(conversation.title.isEmpty ? localized("Conversation", "会话") : conversation.title)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingAISettings, onDismiss: { reloadAI(); scheduleAutomatic() }) {
            NavigationStack { AIAssistSettingsView() }
        }
        .task {
            draft = workspace.composerDraft(for: conversation)
            workspace.subscribe(to: conversation)
            reloadAI()
            scheduleAutomatic()
        }
        .onChange(of: draft) { _, value in workspace.saveComposerDraft(value, for: conversation) }
        .onChange(of: input) { _, _ in
            ai.cancel()
            if skipAutomaticOnce { skipAutomaticOnce = false }
            else { scheduleAutomatic() }
        }
        .onChange(of: requestIsCurrent) { _, current in if !current { ai.cancel() } }
        .onChange(of: scenePhase) { _, phase in if phase != .active { ai.cancel() } }
        .onDisappear { ai.cancel() }
    }

    private func reloadAI() {
        guard let instance = store.selected, let user = store.sessionUser else { return }
        ai.reload(instance: instance, userID: user.id)
    }
    private func scheduleAutomatic() {
        guard !sending, requestIsCurrent, scenePhase == .active, let instance = store.selected else { ai.cancel(); return }
        ai.schedule(input, instance: instance, automatically: true)
    }
    private func generate() {
        guard ai.configuration != nil else { showingAISettings = true; return }
        guard !sending, requestIsCurrent, let instance = store.selected else { return }
        ai.schedule(input, instance: instance, automatically: false)
    }
    private func applySuggestion() {
        guard !sending, requestIsCurrent, let suggestion = ai.takeSuggestion(for: input) else { return }
        var updated = draft
        updated.text = suggestion.text
        if draft.mode == .toolCall { updated.toolName = suggestion.toolName; updated.toolCallID = suggestion.toolCallID }
        skipAutomaticOnce = updated != draft
        draft = updated
    }
    private func send() async {
        guard canSend else { return }
        ai.cancel()
        sending = true
        defer { sending = false }
        let value = draft.text.trimmingCharacters(in: .whitespacesAndNewlines)
        let sent: Bool
        switch draft.mode {
        case .toolCall: sent = await workspace.sendToolCall(conversation, name: draft.toolName.trimmingCharacters(in: .whitespacesAndNewlines), callID: draft.toolCallID.trimmingCharacters(in: .whitespacesAndNewlines), arguments: value)
        case .toolOutput: sent = await workspace.sendToolOutput(conversation, callID: draft.toolCallID.trimmingCharacters(in: .whitespacesAndNewlines), output: value)
        case .reply: sent = await workspace.complete(conversation, text: value)
        }
        if sent { skipAutomaticOnce = true; draft.text = "" }
    }
}

private struct WorkspaceMediaView: View {
    let source: String
    let mediaType: String?
    let workspace: WorkspaceConnection
    @State private var url: URL?
    var body: some View {
        Group {
            if mediaType?.hasPrefix("image/") == true, let imageURL = url {
                AsyncImage(url: imageURL) { image in
                    image.resizable().scaledToFit()
                } placeholder: {
                    ProgressView()
                }
                .clipShape(RoundedRectangle(cornerRadius: 10))
            } else {
                Label(URL(string: source)?.lastPathComponent ?? localized("Media attachment", "媒体附件"), systemImage: "paperclip")
            }
        }.task { url = await workspace.assetURL(source) }
    }
}
