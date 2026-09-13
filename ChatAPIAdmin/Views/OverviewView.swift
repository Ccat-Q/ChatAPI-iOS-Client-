import SwiftUI

// ChatAPI's primary workflow is a human operator completing conversations started by AI clients.
struct OverviewView: View {
    @Environment(InstanceStore.self) private var store
    @State private var conversations: [AdminConversation] = []
    @State private var error: String?

    var body: some View {
        NavigationStack {
            List(conversations) { conversation in
                NavigationLink { ConversationWorkspaceView(conversation: conversation) } label: {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(conversation.title.isEmpty ? localized("Untitled conversation", "未命名会话") : conversation.title)
                            .font(.headline)
                        Text(conversation.lastMessagePreview.isEmpty ? conversation.lastUserText : conversation.lastMessagePreview)
                            .lineLimit(2)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        HStack {
                            Text(localized("\(conversation.messageCount) messages", "\(conversation.messageCount) 条消息"))
                            Spacer()
                            Text(conversation.updatedAt, style: .relative)
                        }
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                    }
                    .padding(.vertical, 4)
                }
            }
            .overlay {
                if conversations.isEmpty && error == nil {
                    ContentUnavailableView(localized("No conversations", "暂无会话"), systemImage: "bubble.left.and.bubble.right")
                }
            }
            .navigationTitle(localized("Workspace", "工作台"))
            .task { await load() }
            .refreshable { await load() }
            .alert(localized("Could Not Load Workspace", "无法加载工作台"), isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                Button(localized("OK", "好"), role: .cancel) {}
            } message: { Text(error ?? "") }
        }
    }

    private func load() async {
        guard let client = store.client() else { return }
        do {
            let response: ConversationListResponse = try await client.get("/api/admin/conversations")
            conversations = response.items.sorted { $0.updatedAt > $1.updatedAt }
        } catch { self.error = error.localizedDescription }
    }
}

private struct ConversationWorkspaceView: View {
    let conversation: AdminConversation
    @Environment(InstanceStore.self) private var store
    @State private var messages: [ConversationMessage] = []
    @State private var reply = ""
    @State private var sending = false
    @State private var error: String?

    var body: some View {
        VStack(spacing: 0) {
            List(messages) { message in
                HStack {
                    if message.role == "assistant" { Spacer(minLength: 42) }
                    VStack(alignment: .leading, spacing: 5) {
                        Text(message.role == "assistant" ? localized("You", "你") : localized("Caller", "调用方"))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Text(message.content)
                    }
                    .padding(10)
                    .background(message.role == "assistant" ? Color.cyan.opacity(0.18) : Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 14))
                    if message.role != "assistant" { Spacer(minLength: 42) }
                }
                .listRowSeparator(.hidden)
            }
            .listStyle(.plain)

            HStack(alignment: .bottom, spacing: 12) {
                TextField(localized("Write the assistant response", "输入助手回复"), text: $reply, axis: .vertical)
                    .lineLimit(1...5)
                    .textFieldStyle(.roundedBorder)
                Button { Task { await complete() } } label: {
                    if sending { ProgressView() } else { Image(systemName: "arrow.up.circle.fill").font(.title2) }
                }
                .disabled(reply.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || sending)
            }
            .padding()
            .background(.bar)
        }
        .navigationTitle(conversation.title.isEmpty ? localized("Conversation", "会话") : conversation.title)
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .alert(localized("Could Not Complete Conversation", "无法完成会话"), isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button(localized("OK", "好"), role: .cancel) {}
        } message: { Text(error ?? "") }
    }

    private func load() async {
        guard let client = store.client() else { return }
        do {
            let response: ConversationMessageListResponse = try await client.get("/api/admin/conversations/\(conversation.id)/messages")
            messages = response.items
        } catch { self.error = error.localizedDescription }
    }

    private func complete() async {
        guard let client = store.client() else { return }
        let text = reply.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        sending = true
        defer { sending = false }
        do {
            let _: SuccessResponse = try await client.post("/api/admin/conversations/\(conversation.id)/complete", body: CompleteConversationInput(text: text))
            reply = ""
            await load()
        } catch { self.error = error.localizedDescription }
    }
}
