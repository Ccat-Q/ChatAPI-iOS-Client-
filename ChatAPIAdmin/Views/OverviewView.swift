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
    @State private var reply = ""
    @State private var composerMode = "reply"
    @State private var toolName = ""
    @State private var toolCallID = ""
    @State private var sending = false

    var body: some View {
        VStack(spacing: 0) {
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
                Button { Task { await send() } } label: { if sending { ProgressView() } else { Image(systemName: "arrow.up.circle.fill").font(.title2) } }.disabled(!canSend)
            }.disabled(sending).padding().background(.bar)
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
        guard !sending, workspace.state == .connected,
              let current = workspace.conversations.first(where: { $0.id == conversation.id }),
              current.requestID == conversation.requestID, !current.requestID.isEmpty,
              ["waiting", "streaming"].contains(current.status) else { return false }
        let body = reply.trimmingCharacters(in: .whitespacesAndNewlines)
        if composerMode == "call" { return !body.isEmpty && !toolName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !toolCallID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        if composerMode == "output" { return !body.isEmpty && !toolCallID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        return !body.isEmpty
    }

    private func send() async {
        let value = reply.trimmingCharacters(in: .whitespacesAndNewlines)
        guard canSend else { return }
        sending = true
        defer { sending = false }
        let sent: Bool
        switch composerMode {
        case "call": sent = await workspace.sendToolCall(conversation, name: toolName.trimmingCharacters(in: .whitespacesAndNewlines), callID: toolCallID.trimmingCharacters(in: .whitespacesAndNewlines), arguments: value)
        case "output": sent = await workspace.sendToolOutput(conversation, callID: toolCallID.trimmingCharacters(in: .whitespacesAndNewlines), output: value)
        default: sent = await workspace.complete(conversation, text: value)
        }
        if sent { reply = "" }
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
