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

    var body: some View {
        VStack(spacing: 0) {
            List(workspace.timelines[conversation.id] ?? []) { item in
                if let message = item.message {
                    HStack {
                        if message.role == "assistant" { Spacer(minLength: 36) }
                        VStack(alignment: .leading, spacing: 4) {
                            Text(message.role == "assistant" ? localized("You", "你") : localized("Caller", "调用方")).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                            Text(message.content)
                        }.padding(10).background(message.role == "assistant" ? Color.cyan.opacity(0.18) : Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 14))
                        if message.role != "assistant" { Spacer(minLength: 36) }
                    }.listRowSeparator(.hidden)
                }
            }.listStyle(.plain)
            HStack(alignment: .bottom) {
                TextField(localized("Write the assistant response", "输入助手回复"), text: $reply, axis: .vertical).lineLimit(1...5).textFieldStyle(.roundedBorder)
                Button { let text = reply.trimmingCharacters(in: .whitespacesAndNewlines); guard !text.isEmpty else { return }; workspace.complete(conversation, text: text); reply = "" } label: { Image(systemName: "arrow.up.circle.fill").font(.title2) }.disabled(reply.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }.padding().background(.bar)
        }
        .navigationTitle(conversation.title.isEmpty ? localized("Conversation", "会话") : conversation.title)
        .navigationBarTitleDisplayMode(.inline)
        .task { workspace.subscribe(to: conversation) }
    }
}
