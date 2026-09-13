import SwiftUI

struct OverviewView: View {
    @Environment(InstanceStore.self) private var store
    @State private var workspace: WorkspaceConnection?

    var body: some View {
        NavigationStack {
            Group {
                if let workspace {
                    List(workspace.conversations) { conversation in
                        NavigationLink { OperatorConversationView(conversation: conversation, workspace: workspace) } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(conversation.title.isEmpty ? localized("Untitled conversation", "未命名会话") : conversation.title).font(.headline)
                                Text(conversation.lastMessagePreview.isEmpty ? conversation.lastUserText : conversation.lastMessagePreview).lineLimit(2).foregroundStyle(.secondary)
                                Text(conversation.status).font(.caption).foregroundStyle(.tertiary)
                            }.padding(.vertical, 4)
                        }
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
        guard workspace == nil, let client = store.client() else { return }
        let connection = WorkspaceConnection(client: client)
        workspace = connection
        connection.connect()
    }
}

private struct OperatorConversationView: View {
    let conversation: WorkspaceConversation
    let workspace: WorkspaceConnection
    @State private var reply = ""
    @State private var composerMode = "reply"
    @State private var toolName = ""
    @State private var toolCallID = ""

    var body: some View {
        VStack(spacing: 0) {
            List(workspace.timelines[conversation.id] ?? []) { item in
                if let message = item.message {
                    HStack {
                        if message.role == "assistant" { Spacer(minLength: 36) }
                        VStack(alignment: .leading, spacing: 4) {
                            Text(message.role == "assistant" ? localized("You", "你") : localized("Caller", "调用方")).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                            Text(message.content)
                            ForEach(message.contentParts ?? []) { part in
                                if let text = part.text, !text.isEmpty, text != message.content { Text(text) }
                                if let source = part.src { WorkspaceMediaView(source: source, mediaType: part.mediaType, workspace: workspace) }
                            }
                        }.padding(10).background(message.role == "assistant" ? Color.cyan.opacity(0.18) : Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 14))
                        if message.role != "assistant" { Spacer(minLength: 36) }
                    }.listRowSeparator(.hidden)
                }
            }.listStyle(.plain)
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 6) {
                    Picker(localized("Action", "动作"), selection: $composerMode) { Text(localized("Reply", "回复")).tag("reply"); Text(localized("Tool call", "工具调用")).tag("call"); Text(localized("Tool output", "工具输出")).tag("output") }.pickerStyle(.segmented)
                    if composerMode == "call" { TextField(localized("Tool name", "工具名称"), text: $toolName); TextField(localized("Tool call ID", "工具调用 ID"), text: $toolCallID) }
                    if composerMode == "output" { TextField(localized("Tool call ID", "工具调用 ID"), text: $toolCallID) }
                    TextField(composerMode == "reply" ? localized("Write the assistant response", "输入助手回复") : (composerMode == "call" ? localized("Tool arguments", "工具参数") : localized("Tool output", "工具输出")), text: $reply, axis: .vertical).lineLimit(1...5).textFieldStyle(.roundedBorder)
                }
                Button { send() } label: { Image(systemName: "arrow.up.circle.fill").font(.title2) }.disabled(!canSend)
            }.padding().background(.bar)
        }
        .navigationTitle(conversation.title.isEmpty ? localized("Conversation", "会话") : conversation.title)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            reply = workspace.draft(for: conversation)
            workspace.subscribe(to: conversation)
        }
        .onChange(of: reply) { _, value in workspace.saveDraft(value, for: conversation) }
    }

    private var canSend: Bool {
        let body = reply.trimmingCharacters(in: .whitespacesAndNewlines)
        if composerMode == "call" { return !body.isEmpty && !toolName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !toolCallID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        if composerMode == "output" { return !body.isEmpty && !toolCallID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        return !body.isEmpty
    }

    private func send() {
        let value = reply.trimmingCharacters(in: .whitespacesAndNewlines)
        guard canSend else { return }
        switch composerMode { case "call": workspace.sendToolCall(conversation, name: toolName, callID: toolCallID, arguments: value); case "output": workspace.sendToolOutput(conversation, callID: toolCallID, output: value); default: workspace.complete(conversation, text: value) }
        reply = ""
    }
}

private struct WorkspaceMediaView: View {
    let source: String
    let mediaType: String?
    let workspace: WorkspaceConnection
    @State private var url: URL?
    var body: some View {
        Group {
            if mediaType?.hasPrefix("image/") == true, let imageURL = url { AsyncImage(url: imageURL) { image in image.resizable().scaledToFit() } placeholder: { ProgressView() } }.clipShape(RoundedRectangle(cornerRadius: 10))
            else { Label(URL(string: source)?.lastPathComponent ?? localized("Media attachment", "媒体附件"), systemImage: "paperclip") }
        }.task { url = await workspace.assetURL(source) }
    }
}
