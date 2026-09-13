import Foundation
import Observation

@MainActor @Observable final class WorkspaceConnection {
    enum State: Equatable { case disconnected, connecting, connected, failed(String) }

    private let client: APIClient
    private var socket: URLSessionWebSocketTask?
    private var receiver: Task<Void, Never>?
    private var reconnect: Task<Void, Never>?
    private var retryCount = 0

    var state: State = .disconnected
    var conversations: [WorkspaceConversation] = []
    var timelines: [String: [WorkspaceTimelineItem]] = [:]

    init(client: APIClient) { self.client = client }
    deinit { receiver?.cancel(); reconnect?.cancel(); socket?.cancel(with: .goingAway, reason: nil) }

    func connect() {
        guard receiver == nil else { return }
        state = .connecting
        Task {
            guard let request = await client.workspaceRequest() else { state = .failed(localized("Invalid server address.", "服务器地址无效。")); return }
            let task = URLSession.shared.webSocketTask(with: request)
            socket = task
            task.resume()
            state = .connected
            retryCount = 0
            receiver = Task { [weak self] in await self?.receiveLoop() }
        }
    }

    func disconnect() {
        reconnect?.cancel(); reconnect = nil
        receiver?.cancel(); receiver = nil
        socket?.cancel(with: .goingAway, reason: nil); socket = nil
        state = .disconnected
    }

    func subscribe(to conversation: WorkspaceConversation) { send(["type": "timeline.subscribe", "conversation_id": conversation.id]) }

    func complete(_ conversation: WorkspaceConversation, text: String) {
        let command = WorkspaceCommand(commandID: UUID().uuidString, kind: "stream_complete", conversationID: conversation.id, requestID: conversation.requestID, text: text, mode: "assistant_message")
        guard let data = try? JSONEncoder().encode(WorkspaceCommandEnvelope(command: command)) else { return }
        send(data)
    }

    private func receiveLoop() async {
        guard let socket else { return }
        do {
            while !Task.isCancelled {
                let message = try await socket.receive()
                let data: Data
                switch message { case .data(let value): data = value; case .string(let value): data = Data(value.utf8); @unknown default: continue }
                handle(data)
            }
        } catch where !Task.isCancelled { scheduleReconnect() }
    }

    private func handle(_ data: Data) {
        guard let raw = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let type = raw["type"] as? String else { return }
        switch type {
        case "workspace.snapshot":
            if let snapshot = try? JSONDecoder.chatAPI.decode(WorkspaceSnapshot.self, from: data) { conversations = snapshot.conversations }
        case "timeline.reset":
            if let reset = try? JSONDecoder.chatAPI.decode(WorkspaceTimelineReset.self, from: data) { timelines[reset.conversationID] = reset.items }
        case "conversation.remove":
            if let id = raw["conversation_id"] as? String { conversations.removeAll { $0.id == id } }
        default: break
        }
    }

    private func send(_ value: [String: Any]) { guard let data = try? JSONSerialization.data(withJSONObject: value) else { return }; send(data) }
    private func send(_ data: Data) { socket?.send(.data(data)) { [weak self] error in if error != nil { Task { @MainActor in self?.scheduleReconnect() } } } }

    private func scheduleReconnect() {
        guard reconnect == nil else { return }
        receiver = nil; socket = nil
        retryCount += 1
        let delay = min(pow(2, Double(retryCount)), 30)
        state = .failed(localized("Realtime connection lost. Reconnecting…", "实时连接已断开，正在重连…"))
        reconnect = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            self?.reconnect = nil
            self?.connect()
        }
    }
}
