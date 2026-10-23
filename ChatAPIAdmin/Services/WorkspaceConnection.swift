import Foundation
import Observation

@MainActor @Observable final class WorkspaceConnection {
    enum State: Equatable { case disconnected, connecting, connected, failed(String) }
    private struct PendingCommand {
        let conversationID: String
        let requestID: String
        let continuation: CheckedContinuation<Bool, Never>
        let timeout: Task<Void, Never>
    }

    private let client: APIClient
    private let instance: Instance
    private let userID: String
    private var socket: URLSessionWebSocketTask?
    private var receiver: Task<Void, Never>?
    private var reconnect: Task<Void, Never>?
    private var connectionTimeout: Task<Void, Never>?
    private let snapshotTimeout: Duration
    private var connectionID = UUID()
    private var retryCount = 0
    private var subscription: String?
    private var pending: [String: PendingCommand] = [:]
    private var pageCommandID: String?
    private var pageTimeout: Task<Void, Never>?
    private var cursor: String?
    private var removedIDs: Set<String> = []

    private(set) var state: State = .disconnected
    private(set) var conversations: [WorkspaceConversation] = []
    private(set) var timelines: [String: [WorkspaceTimelineItem]] = [:]
    private(set) var hasMore = false
    private(set) var loadingMore = false
    var lastError: String?

    init(client: APIClient, instance: Instance, userID: String, snapshotTimeout: Duration = .seconds(15)) {
        self.client = client
        self.instance = instance
        self.userID = userID
        self.snapshotTimeout = snapshotTimeout
    }

    func connect() {
        guard receiver == nil, reconnect == nil else { return }
        let id = UUID()
        connectionID = id
        state = .connecting
        connectionTimeout = Task { [weak self, snapshotTimeout] in
            do { try await Task.sleep(for: snapshotTimeout) } catch { return }
            self?.scheduleReconnect(for: id, message: localized("Workspace connection timed out. Reconnecting…", "工作台连接超时，正在重连…"))
        }
        receiver = Task { [weak self] in
            guard let self else { return }
            // RootView already validated the restored session. The WebSocket
            // handshake authenticates its own Cookie; no second REST round trip.
            guard let task = await self.client.workspaceSocket() else {
                self.disconnect()
                self.state = .failed(localized("Invalid server address.", "服务器地址无效。"))
                return
            }
            guard !Task.isCancelled, self.connectionID == id else { task.cancel(); return }
            task.maximumMessageSize = 1_048_576
            self.socket = task
            task.resume()
            do {
                while !Task.isCancelled, self.connectionID == id {
                    let message = try await task.receive()
                    guard self.connectionID == id, !Task.isCancelled else { return }
                    switch message {
                    case .data(let data): self.handle(data)
                    case .string(let string): self.handle(Data(string.utf8))
                    @unknown default: break
                    }
                }
            } catch {
                guard !Task.isCancelled, self.connectionID == id else { return }
                if let status = (task.response as? HTTPURLResponse)?.statusCode, status == 401 || status == 403 {
                    self.disconnect()
                    self.state = .failed(status == 401 ? localized("Please sign in again.", "请重新登录。") : localized("Workspace access was denied. Check account permissions and proxy settings.", "工作台访问被拒绝，请检查账号权限与代理设置。"))
                    if status == 401 { await self.client.workspaceSessionRejected() }
                } else { self.scheduleReconnect(for: id) }
            }
        }
    }

    func disconnect() {
        connectionID = UUID()
        reconnect?.cancel(); reconnect = nil
        connectionTimeout?.cancel(); connectionTimeout = nil
        receiver?.cancel(); receiver = nil
        socket?.cancel(with: .goingAway, reason: nil); socket = nil
        failPending(localized("Connection closed. Your draft is retained.", "连接已关闭，草稿已保留。"))
        resetPageRequest()
        state = .disconnected
    }

    func retryNow() {
        disconnect()
        retryCount = 0
        connect()
    }

    func subscribe(to conversation: WorkspaceConversation) {
        if let previous = subscription, previous != conversation.id { send(["type": "timeline.unsubscribe", "conversation_id": previous]) }
        subscription = conversation.id
        if state == .connected { send(["type": "timeline.subscribe", "conversation_id": conversation.id]) }
    }

    func complete(_ conversation: WorkspaceConversation, text: String) async -> Bool {
        await sendCommand(conversation, text: text, mode: "assistant_message")
    }

    func sendToolCall(_ conversation: WorkspaceConversation, name: String, callID: String, arguments: String) async -> Bool {
        guard let data = arguments.data(using: .utf8),
              (try? JSONSerialization.jsonObject(with: data)) is [String: Any] else {
            lastError = localized("Tool arguments must be a JSON object.", "工具参数必须是 JSON 对象。")
            return false
        }
        return await sendCommand(conversation, text: arguments, mode: "tool_call", toolName: name, toolCallID: callID)
    }

    func sendToolOutput(_ conversation: WorkspaceConversation, callID: String, output: String) async -> Bool {
        await sendCommand(conversation, text: "", mode: "tool_result", toolCallID: callID, output: output)
    }

    func assetURL(_ value: String) async -> URL? { await client.absoluteURL(for: value) }

    private func sendCommand(_ conversation: WorkspaceConversation, text: String, mode: String, toolName: String = "", toolCallID: String = "", output: String = "") async -> Bool {
        guard state == .connected, let socket, !conversation.requestID.isEmpty else {
            lastError = localized("The connection or request is not ready. Your draft is retained.", "连接或请求尚未就绪，草稿已保留。")
            return false
        }
        let id = UUID().uuidString
        let generation = connectionID
        let command = WorkspaceCommand(commandID: id, kind: "stream_complete", conversationID: conversation.id, requestID: conversation.requestID, text: text, mode: mode, toolName: toolName, toolCallID: toolCallID, output: output)
        guard let data = try? JSONEncoder().encode(WorkspaceCommandEnvelope(command: command)) else { return false }
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                guard !Task.isCancelled else { continuation.resume(returning: false); return }
                let timeout = Task { [weak self] in
                    do { try await Task.sleep(for: .seconds(15)) } catch { return }
                    self?.finish(id, error: localized("Server confirmation timed out. Check the timeline before retrying; your draft is retained.", "等待服务器确认超时。重试前请检查时间线，草稿已保留。"))
                }
                pending[id] = PendingCommand(conversationID: conversation.id, requestID: conversation.requestID, continuation: continuation, timeout: timeout)
                Task { [weak self] in
                    do { try await socket.send(.string(String(decoding: data, as: UTF8.self))) }
                    catch { self?.scheduleReconnect(for: generation) }
                }
            }
        } onCancel: {
            Task { @MainActor [weak self] in self?.finish(id, error: localized("Sending cancelled. Your draft is retained.", "发送已取消，草稿已保留。")) }
        }
    }

    func draft(for conversation: WorkspaceConversation) -> String {
        composerDraft(for: conversation).text
    }

    func saveDraft(_ text: String, for conversation: WorkspaceConversation) {
        var draft = composerDraft(for: conversation)
        draft.text = text
        saveComposerDraft(draft, for: conversation)
    }

    func composerDraft(for conversation: WorkspaceConversation) -> WorkspaceComposerDraft {
        guard let data = try? KeychainStore.load(account: draftAccount(for: conversation)) else { return WorkspaceComposerDraft() }
        return WorkspaceComposerDraft.restore(data)
    }

    func saveComposerDraft(_ draft: WorkspaceComposerDraft, for conversation: WorkspaceConversation) {
        let account = draftAccount(for: conversation)
        if draft.isEmpty { KeychainStore.delete(account: account); return }
        do { try KeychainStore.save(try JSONEncoder().encode(draft), account: account) }
        catch { lastError = localized("Could not save the draft: ", "无法保存草稿：") + error.localizedDescription }
    }

    func loadMore() {
        guard state == .connected, hasMore, !loadingMore, let cursor, !cursor.isEmpty else { return }
        let id = UUID().uuidString
        pageCommandID = id
        loadingMore = true
        send(["type": "conversation.page.get", "command_id": id, "cursor": cursor])
        pageTimeout = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(15)) } catch { return }
            guard let self, self.pageCommandID == id else { return }
            self.resetPageRequest()
            self.lastError = localized("Loading conversations timed out. Please retry.", "加载会话超时，请重试。")
        }
    }

    // Internal so the Actions regression runner can exercise actual event handling.
    func handle(_ data: Data) {
        guard let raw = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let type = raw["type"] as? String else { return }
        do {
            switch type {
            case "workspace.snapshot":
                let snapshot = try JSONDecoder.chatAPI.decode(WorkspaceSnapshot.self, from: data)
                conversations = snapshot.conversations.sorted { $0.updatedAt > $1.updatedAt }
                hasMore = snapshot.hasMore ?? false
                cursor = snapshot.nextCursor
                removedIDs.removeAll()
                resetPageRequest()
                state = .connected
                connectionTimeout?.cancel(); connectionTimeout = nil
                retryCount = 0
                if let subscription { send(["type": "timeline.subscribe", "conversation_id": subscription]) }
            case "conversation.page":
                let page = try JSONDecoder.chatAPI.decode(WorkspaceConversationPage.self, from: data)
                guard page.commandID == pageCommandID else { return }
                let existing = Set(conversations.map(\.id)).union(removedIDs)
                conversations += page.conversations.filter { !existing.contains($0.id) }
                conversations.sort { $0.updatedAt > $1.updatedAt }
                hasMore = page.hasMore
                cursor = page.nextCursor
                resetPageRequest()
            case "conversation.page.error":
                guard raw["command_id"] as? String == pageCommandID else { return }
                resetPageRequest()
                lastError = raw["message"] as? String ?? localized("Could not load conversations.", "无法加载会话。")
            case "timeline.reset":
                let reset = try JSONDecoder.chatAPI.decode(WorkspaceTimelineReset.self, from: data)
                timelines[reset.conversationID] = reset.items
            case "timeline.append":
                let append = try JSONDecoder.chatAPI.decode(WorkspaceTimelineAppend.self, from: data)
                if !(timelines[append.conversationID] ?? []).contains(where: { $0.id == append.item.id }) {
                    timelines[append.conversationID, default: []].append(append.item)
                }
            case "conversation.upsert":
                let upsert = try JSONDecoder.chatAPI.decode(WorkspaceConversationUpsert.self, from: data)
                removedIDs.remove(upsert.conversation.id)
                conversations.removeAll { $0.id == upsert.conversation.id }
                conversations.append(upsert.conversation)
                conversations.sort { $0.updatedAt > $1.updatedAt }
            case "conversation.remove":
                if let id = raw["conversation_id"] as? String {
                    removedIDs.insert(id)
                    conversations.removeAll { $0.id == id }
                    timelines.removeValue(forKey: id)
                    if subscription == id { subscription = nil }
                }
            case "workspace.command_ack":
                let ack = try JSONDecoder.chatAPI.decode(WorkspaceCommandAck.self, from: data)
                guard let command = pending[ack.commandID] else { return }
                let matches = command.conversationID == ack.conversationID && command.requestID == ack.requestID
                finish(ack.commandID, error: matches ? nil : localized("Server confirmation refers to a different request. Your draft is retained.", "服务器确认的请求不匹配，草稿已保留。"))
            case "workspace.command_error":
                let failure = try JSONDecoder.chatAPI.decode(WorkspaceCommandError.self, from: data)
                let message = failure.message ?? failure.error ?? localized("The server rejected this action.", "服务器拒绝了该操作。")
                if let id = failure.commandID, pending[id] != nil { finish(id, error: message) }
                else { lastError = message }
            default: break
            }
        } catch {
            lastError = localized("Could not decode a workspace event: ", "无法解析工作台事件：") + error.localizedDescription
            if type == "workspace.snapshot" {
                disconnect()
                state = .failed(lastError ?? "Invalid workspace snapshot")
            }
        }
    }

    private func send(_ value: [String: String]) {
        guard state == .connected, let socket, let data = try? JSONEncoder().encode(value) else { return }
        let id = connectionID
        Task { [weak self] in
            do { try await socket.send(.string(String(decoding: data, as: UTF8.self))) }
            catch { self?.scheduleReconnect(for: id) }
        }
    }

    private func finish(_ id: String, error: String?) {
        guard let command = pending.removeValue(forKey: id) else { return }
        command.timeout.cancel()
        if let error { lastError = error }
        command.continuation.resume(returning: error == nil)
    }

    private func failPending(_ message: String) {
        for id in Array(pending.keys) { finish(id, error: message) }
    }

    private func resetPageRequest() {
        pageTimeout?.cancel(); pageTimeout = nil
        pageCommandID = nil
        loadingMore = false
    }

    private func scheduleReconnect(for id: UUID, message: String? = nil) {
        guard connectionID == id, reconnect == nil else { return }
        connectionID = UUID()
        connectionTimeout?.cancel(); connectionTimeout = nil
        receiver?.cancel(); receiver = nil
        socket?.cancel(with: .goingAway, reason: nil); socket = nil
        failPending(localized("Connection lost. Check the timeline before retrying; your draft is retained.", "连接已断开。重试前请检查时间线，草稿已保留。"))
        resetPageRequest()
        retryCount = min(retryCount + 1, 6)
        let delay = min(pow(2, Double(retryCount - 1)), 30)
        state = .failed(message ?? localized("Realtime connection lost. Reconnecting…", "实时连接已断开，正在重连…"))
        reconnect = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(delay)) } catch { return }
            guard let self else { return }
            self.reconnect = nil
            self.connect()
        }
    }

    private func draftAccount(for conversation: WorkspaceConversation) -> String {
        instance.draftAccount(userID: userID, conversationID: conversation.id, requestID: conversation.requestID)
    }
}
