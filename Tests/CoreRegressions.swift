import Foundation

private struct RegressionFailure: Error, CustomStringConvertible {
    let description: String
}
private actor UnauthorizedCounter {
    var count = 0
    func increment() { count += 1 }
}

@main @MainActor struct CoreRegressions {
    private static var assertions = 0
    static func check(_ condition: Bool, _ message: String) throws {
        assertions += 1
        if !condition { throw RegressionFailure(description: message) }
    }
    static func decode<T: Decodable>(_ type: T.Type, _ text: String) throws -> T {
        try JSONDecoder.chatAPI.decode(type, from: Data(text.utf8))
    }
    static func waitUntil(_ message: String, _ predicate: () -> Bool) async throws {
        for _ in 0..<160 {
            if predicate() { return }
            try await Task.sleep(for: .milliseconds(50))
        }
        throw RegressionFailure(description: message)
    }
    static func main() async throws {
        try protocolModels()
        try settingsAndURLs()
        try keychainUpdates()
        try await networkAndWorkspace()
        try await connectionSpeedAndRecovery()
        try await boundedResponsesAndHeartbeat()
        try await sessionRecovery()
        try await authenticationRegressions()
        try await aiRegressions()
        print("PASS: \(assertions) regression assertions")
    }

    static func protocolModels() throws {
        let conversation = #"{"id":"c1","title":"Fixture","last_user_text":"Hello","last_message_preview":"Hello","request_id":"r1","status":"waiting","updated_at":"2026-10-22T12:00:00.123456789Z"}"#
        let snapshot = try decode(WorkspaceSnapshot.self, "{\"type\":\"workspace.snapshot\",\"conversations\":[\(conversation)],\"has_more\":true,\"next_cursor\":\"page-1\"}")
        try check(snapshot.conversations.first?.requestID == "r1", "Snake-case acronym keys must decode")
        try check(snapshot.hasMore == true && snapshot.nextCursor == "page-1", "Snapshot pagination must decode")
        // Omitted request/status are valid for historical conversations.
        let history = try decode(WorkspaceConversation.self, #"{"id":"old","title":"History","last_user_text":"","last_message_preview":"","updated_at":"2026-10-22T12:00:00Z"}"#)
        try check(history.requestID.isEmpty && history.status.isEmpty, "Historical summaries must tolerate omitted active request fields")
        let activity = try decode(ActivityListResponse.self, #"{"items":[{"request_id":"r1","conversation_id":"c1","request_path":"/v1/responses","created_at":"2026-10-22T12:00:00.1Z"}]}"#)
        try check(activity.items[0].conversationID == "c1", "Request identifiers must decode")
        let users = try decode(UserListResponse.self, #"{"items":[{"id":"u1","username":"Operator","role":"user","is_active":true}],"page":2,"page_size":50,"total":70}"#)
        try check(users.page == 2 && users.total == 70 && users.items[0].isActive, "User pagination and state must decode")
        let keys = try decode(APIKeyListResponse.self, #"{"api_keys":[{"id":"k1","name":"Key","created_at":"2026-10-22T12:00:00Z"}]}"#)
        try check(keys.items.count == 1 && keys.items[0].keyPrefix == nil, "API key list uses api_keys and optional prefixes")
        let secret = try decode(APIKeyCreateResponse.self, #"{"api_key":{"id":"k1","name":"Key","api_key":"secret"}}"#)
        try check(secret.apiKey.apiKey == "secret", "Nested key creation response must decode")
        let bark = BarkSettings(deviceKey: "device", enabled: true, health: true, pendingWork: true, security: false, configured: nil)
        let barkJSON = try JSONSerialization.jsonObject(with: JSONEncoder().encode(bark)) as? [String: Any]
        try check(barkJSON?["device_key"] as? String == "device" && barkJSON?["pending_work"] as? Bool == true && barkJSON?["deviceKey"] == nil, "Bark requests must use server wire keys")
        let rule = try decode(AutomationRule.self, #"{"schema_version":3,"id":"a1","name":"Rule","enabled":false,"priority":0,"match":{"pattern":"x","model_pattern":".*","model_key_id":"k1"},"playback":{"mode":"recorded","initial_delay_ms":0,"fixed_interval_ms":0,"loop":false,"loop_interval_ms":0},"steps":[{"id":"s1","delay_before_ms":0,"action":{"kind":"stream_complete","text":"Done"}}]}"#)
        try check(rule.steps[0].action.toolName.isEmpty && rule.match.target.isEmpty, "Omitted automation action fields must decode")
        let builtin = try decode(AutomationAction.self, #"{"kind":"builtin_tool","builtin_tool_kind":"web_search","builtin_tool_query":"example","reasoning_stream_mode":"reasoning"}"#)
        let restored = try decode(AutomationAction.self, String(decoding: JSONEncoder().encode(builtin), as: UTF8.self))
        try check(restored == builtin, "Advanced automation fields must survive round trips")
        try check(AutomationRule.empty.playback.mode == "recorded", "New rules must use supported playback modes")
        try check(CreateAppKeyInput.operatorKey(name: "Operator").scopes == ["conversations:read", "requests:respond"], "Operator keys must grant scopes actually enforced by server routes")
        let value = try decode(JSONValue.self, #"{"nested":[1,true,null,{"value":"ok"}]}"#)
        try check(try decode(JSONValue.self, String(decoding: JSONEncoder().encode(value), as: UTF8.self)) == value, "Structured settings must round-trip")
        try check(!JSONValue.number(1e100).displayValue.isEmpty, "Large server numbers must not trap when displayed")
    }

    static func settingsAndURLs() throws {
        try check(URL(string: "https://EXAMPLE.com:443/x")!.hasSameOrigin(as: URL(string: "https://example.com/")!), "HTTPS default port redirects must stay same-origin")
        try check(URL(string: "http://example.com:80/x")!.hasSameOrigin(as: URL(string: "http://example.com/")!), "HTTP default port redirects must stay same-origin")
        try check(!URL(string: "https://example.com:444/")!.hasSameOrigin(as: URL(string: "https://example.com/")!), "Non-default ports must remain different origins")
        try check(!URL(string: "http://example.com:443/")!.hasSameOrigin(as: URL(string: "https://example.com/")!), "Default-port normalization must not permit TLS downgrades")
        let document = try decode(SettingsDocument.self, #"{"domain":"test","title":"Test","values":{"count":2,"readonly":"safe","secret":"old","structured":{"x":1}},"fields":[{"key":"count","title":"Count","type":"integer","description":"","editable":true,"sensitive":false,"restart_required":false,"minimum":0,"maximum":10},{"key":"readonly","title":"Read only","type":"string","description":"","editable":false,"sensitive":false,"restart_required":false},{"key":"secret","title":"Secret","type":"string","description":"","editable":true,"sensitive":true,"restart_required":false},{"key":"structured","title":"Structured","type":"object","description":"","editable":true,"sensitive":false,"restart_required":false}]}"#)
        var edits = document.values
        edits["readonly"] = .string("overwrite")
        edits["structured"] = .string("overwrite")
        let patch = try document.patch(values: edits, textEdits: ["count": "3", "unknown": "overwrite"])
        try check(patch == ["count": .number(3)], "Patch must exclude unchanged, read-only, unknown, and unsupported fields")
        for invalid in ["", "abc", "2.5", "-1", "11", "nan", "inf"] {
            do { _ = try document.patch(values: document.values, textEdits: ["count": invalid]); throw RegressionFailure(description: "Invalid integer accepted: \(invalid)") }
            catch is RegressionFailure { throw RegressionFailure(description: "Invalid integer accepted: \(invalid)") }
            catch { assertions += 1 }
        }
        try check(try document.patch(values: document.values, textEdits: [:]).isEmpty, "Unchanged form must generate an empty patch")
        try check(try Instance.validatedURL(URL(string: "https://example.com")!, allowsInsecureHTTP: false).absoluteString == "https://example.com/", "Server URLs must normalize to a root")
        for address in ["relative", "ftp://example.com", "https://user:pass@example.com", "https://example.com/base", "https://example.com?x=1", "https://example.com#x", "http://example.com"] {
            do { _ = try Instance.validatedURL(URL(string: address)!, allowsInsecureHTTP: false); throw RegressionFailure(description: "Invalid URL accepted: \(address)") }
            catch is RegressionFailure { throw RegressionFailure(description: "Invalid URL accepted: \(address)") }
            catch { assertions += 1 }
        }
        let instance = Instance(id: UUID(), name: "Test", baseURL: URL(string: "https://example.com/")!, allowsInsecureHTTP: false, capabilities: nil)
        let other = Instance(id: UUID(), name: "Other", baseURL: instance.baseURL, allowsInsecureHTTP: false, capabilities: nil)
        let account = instance.draftAccount(userID: "u", conversationID: "c", requestID: "r")
        try check(account != other.draftAccount(userID: "u", conversationID: "c", requestID: "r"), "Drafts must be isolated by instance")
        try check(account != instance.draftAccount(userID: "other", conversationID: "c", requestID: "r"), "Drafts must be isolated by owner")
        try check(account != instance.draftAccount(userID: "u", conversationID: "c", requestID: "other"), "Drafts must be isolated by request")
    }

    static func keychainUpdates() throws {
        let account = "regression.\(UUID().uuidString)"
        defer { KeychainStore.delete(account: account) }
        try KeychainStore.save(Data("original".utf8), account: account)
        try KeychainStore.save(Data("updated".utf8), account: account)
        try check(try KeychainStore.load(account: account) == Data("updated".utf8), "Keychain updates must replace existing values")
    }

    static func networkAndWorkspace() async throws {
        let port = CommandLine.arguments[1]
        let instance = Instance(id: UUID(), name: "Fixture", baseURL: URL(string: "http://127.0.0.1:\(port)/")!, allowsInsecureHTTP: true, capabilities: nil)
        let counter = UnauthorizedCounter()
        let client = APIClient(instance: instance) { await counter.increment() }
        do { try await client.login(username: "bad", password: "bad"); throw RegressionFailure(description: "Login ok:false must fail") }
        catch APIError.unauthorized { assertions += 1 }
        try await client.login(username: "operator", password: "password", totp: "123456")
        try check(try await client.sessionInfo().authenticated, "Cookie login must authenticate REST requests")
        struct Headers: Decodable, Sendable { let origin: String; let authorization: String }
        let headers: Headers = try await client.get("/fixture/headers")
        try check(headers.origin == "http://127.0.0.1:\(port)" && headers.authorization.isEmpty, "REST must send Origin and must not send a fabricated bearer token")
        let redirected: Headers = try await client.get("/fixture/redirect-local")
        try check(redirected.origin == headers.origin, "Same-origin REST redirects must work")
        do { let _: Headers = try await client.get("/fixture/redirect-external"); throw RegressionFailure(description: "Cross-origin redirect accepted") }
        catch APIError.server { assertions += 1 }
        let empty: SuccessResponse = try await client.delete("/fixture/delete")
        try check(empty.ok, "204 DELETE must succeed without JSON")
        let aborted: SuccessResponse = try await client.post("/api/admin/conversations/c1/abort", body: AbortConversationInput(reason: "Operator cancelled"))
        try check(aborted.ok, "Abort must include the server-required reason")
        do { let _: SuccessResponse = try await client.get("/fixture/oversize"); throw RegressionFailure(description: "Oversized response accepted") }
        catch APIError.server { assertions += 1 }
        do { let _: SuccessResponse = try await client.get("/fixture/forbidden"); throw RegressionFailure(description: "403 accepted") }
        catch APIError.server { assertions += 1 }
        try check(await counter.count == 0, "403 must not expire a valid session")
        do { let _: SuccessResponse = try await client.get("/fixture/unauthorized"); throw RegressionFailure(description: "401 accepted") }
        catch APIError.unauthorized { assertions += 1 }
        try check(await counter.count == 1, "401 must notify the session owner")
        try check(await client.absoluteURL(for: "javascript:alert(1)") == nil, "Unsafe attachment schemes must be rejected")
        try check(await client.absoluteURL(for: "http://other.example/file") == nil, "HTTP opt-in must not apply to external attachments")

        let workspace = WorkspaceConnection(client: client, instance: instance, userID: "u1")
        let conversation = try decode(WorkspaceConversation.self, #"{"id":"c1","title":"Fixture","last_user_text":"Hello","last_message_preview":"Hello","request_id":"r1","status":"waiting","updated_at":"2026-10-22T12:00:00Z"}"#)
        workspace.subscribe(to: conversation)
        workspace.connect(); workspace.connect()
        defer { workspace.disconnect() }
        try await waitUntil("WebSocket did not authenticate or subscribe") { workspace.state == .connected && workspace.timelines["c1"]?.count == 1 }
        try check(await workspace.complete(conversation, text: "Hello"), "Reply must wait for and accept matching ack")
        try check(await workspace.sendToolCall(conversation, name: "tool", callID: "call", arguments: "{}"), "Tool call must use stream_complete/tool_call")
        try check(await workspace.sendToolOutput(conversation, callID: "call", output: "Done"), "Tool result must use stream_complete/tool_result")
        try check(!(await workspace.sendToolCall(conversation, name: "tool", callID: "call", arguments: "[]")), "Tool arguments must be objects")
        try check(!(await workspace.complete(conversation, text: "__reject__")), "Server rejection must fail the send")
        try check(!(await workspace.complete(conversation, text: "__mismatch__")), "Ack for another request must not clear the composer")
        workspace.loadMore()
        try await waitUntil("Conversation pagination failed") { workspace.conversations.count == 2 && !workspace.loadingMore }
        try check(!workspace.hasMore, "Final page must clear hasMore")
        let waiting = Task { @MainActor in await workspace.complete(conversation, text: "__noack__") }
        try await Task.sleep(for: .milliseconds(100))
        workspace.disconnect()
        try check(!(await waiting.value), "Disconnect must resolve pending commands as failures")
        workspace.connect()
        try await waitUntil("Manual reconnect failed") { workspace.state == .connected }
        try check(await workspace.complete(conversation, text: "After reconnect"), "Reconnected socket must send successfully")
        try check(!(await workspace.complete(conversation, text: "__disconnect__")), "Connection loss must preserve unsent input")
        try await waitUntil("Automatic reconnect or subscription restore failed") { workspace.state == .connected && workspace.timelines["c1"]?.count == 1 }
        workspace.handle(Data(#"{"type":"conversation.remove","conversation_id":"c1"}"#.utf8))
        try check(workspace.timelines["c1"] == nil && !workspace.conversations.contains(where: { $0.id == "c1" }), "Removed conversations must clear cached timelines")
        workspace.disconnect()
        workspace.connect(); workspace.disconnect()
        try await Task.sleep(for: .milliseconds(150))
        try check(workspace.state == .disconnected, "Cancelled connect must not resurrect a socket")
    }

    static func connectionSpeedAndRecovery() async throws {
        struct Mode: Encodable, Sendable { let mode: String }
        struct Stats: Decodable, Sendable { let sessions: Int; let sockets: Int }
        let instance = Instance(id: UUID(), name: "Connection fixture", baseURL: URL(string: "http://127.0.0.1:\(CommandLine.arguments[1])/")!, allowsInsecureHTTP: true, capabilities: nil)
        let counter = UnauthorizedCounter()
        let client = APIClient(instance: instance) { await counter.increment() }
        try await client.login(username: "operator", password: "password", totp: "123456")
        let workspace = WorkspaceConnection(client: client, instance: instance, userID: "u1", snapshotTimeout: .milliseconds(500))
        defer { workspace.disconnect() }
        let before: Stats = try await client.get("/fixture/connection-stats")
        let _: SuccessResponse = try await client.post("/fixture/session-mode", body: Mode(mode: "server-error"))
        workspace.connect(); workspace.connect()
        try await waitUntil("Workspace unnecessarily waited for a second REST session validation") { workspace.state == .connected }
        let after: Stats = try await client.get("/fixture/connection-stats")
        try check(after.sessions == before.sessions && after.sockets == before.sockets + 1, "Connecting must authenticate directly over one WebSocket without an extra REST round trip")
        try await Task.sleep(for: .milliseconds(650))
        try check(workspace.state == .connected, "A successful snapshot must cancel its connection deadline")
        workspace.disconnect()
        let _: SuccessResponse = try await client.post("/fixture/workspace-mode", body: Mode(mode: "no-snapshot"))
        workspace.connect()
        try await waitUntil("A missing first snapshot must fail within the configured deadline") { if case .failed = workspace.state { return true }; return false }
        let _: SuccessResponse = try await client.post("/fixture/workspace-mode", body: Mode(mode: "normal"))
        workspace.retryNow()
        try await waitUntil("Manual retry did not bypass reconnect backoff") { workspace.state == .connected }
        try await Task.sleep(for: .milliseconds(1100))
        let retried: Stats = try await client.get("/fixture/connection-stats")
        try check(retried.sockets == after.sockets + 2 && workspace.state == .connected, "Manual retry must cancel both the old timeout and scheduled reconnect")
        workspace.disconnect()
        let _: SuccessResponse = try await client.post("/fixture/workspace-mode", body: Mode(mode: "unauthorized"))
        workspace.connect()
        try await waitUntil("WebSocket 401 must invalidate the owning session") { if case .failed = workspace.state { return true }; return false }
        try await Task.sleep(for: .milliseconds(100))
        try check(await counter.count == 1, "WebSocket handshake 401 must notify the owning session once")
        workspace.disconnect()
        let _: SuccessResponse = try await client.post("/fixture/workspace-mode", body: Mode(mode: "forbidden"))
        workspace.connect()
        try await waitUntil("WebSocket 403 must fail promptly") { if case .failed = workspace.state { return true }; return false }
        try await Task.sleep(for: .milliseconds(1100))
        let denied: Stats = try await client.get("/fixture/connection-stats")
        try check(await counter.count == 1 && denied.sockets == retried.sockets + 2, "403 must preserve the session and must not enter an automatic reconnect loop")
        workspace.disconnect()
        let _: SuccessResponse = try await client.post("/fixture/workspace-mode", body: Mode(mode: "normal"))
        let _: SuccessResponse = try await client.post("/fixture/session-mode", body: Mode(mode: "normal"))
    }

    static func boundedResponsesAndHeartbeat() async throws {
        struct Mode: Encodable, Sendable { let mode: String }
        struct Stats: Decodable, Sendable { let pings: Int; let chunkedBytes: Int
            enum CodingKeys: String, CodingKey { case pings; case chunkedBytes = "chunked_bytes" }
        }
        let instance = Instance(id: UUID(), name: "Bounded fixture", baseURL: URL(string: "http://127.0.0.1:\(CommandLine.arguments[1])/")!, allowsInsecureHTTP: true, capabilities: nil)
        let client = APIClient(instance: instance)
        var headerRequestFinished = false
        let declared = Task { @MainActor in
            defer { headerRequestFinished = true }
            do { let _: SuccessResponse = try await client.get("/fixture/oversize-headers"); return false }
            catch APIError.server { return true }
            catch { return false }
        }
        defer { declared.cancel() }
        try await waitUntil("Declared oversized responses must fail before the body arrives") { headerRequestFinished }
        let _: SuccessResponse = try await client.post("/fixture/release-large-body", body: EmptyRequest())
        try check(await declared.value, "An oversized Content-Length must be rejected before downloading its body")
        do { let _: SuccessResponse = try await client.get("/fixture/oversize-chunked"); try check(false, "Chunked oversized response was accepted") }
        catch APIError.server { try check(true, "Unknown-size responses must be bounded while streaming") }
        let stats: Stats = try await client.get("/fixture/connection-stats")
        try check(stats.chunkedBytes < 8 * 1_048_576, "The client must stop the chunked transfer before the full oversized body is sent")

        try await client.login(username: "operator", password: "password", totp: "123456")
        let workspace = WorkspaceConnection(client: client, instance: instance, userID: "u1", heartbeatInterval: .milliseconds(100), heartbeatTimeout: .milliseconds(500))
        defer { workspace.disconnect() }
        workspace.connect()
        try await waitUntil("Heartbeat fixture did not connect") { workspace.state == .connected }
        try await Task.sleep(for: .milliseconds(700))
        let healthy: Stats = try await client.get("/fixture/connection-stats")
        try check(healthy.pings > stats.pings && workspace.state == .connected, "A responsive socket must receive pings and remain connected")
        let _: SuccessResponse = try await client.post("/fixture/workspace-mode", body: Mode(mode: "no-pong"))
        try await waitUntil("A silently unresponsive socket must leave connected state") { if case .failed = workspace.state { return true }; return false }
        try check(workspace.state != .connected, "Missing pong must trigger reconnect rather than leave a false connected state")
        let _: SuccessResponse = try await client.post("/fixture/workspace-mode", body: Mode(mode: "normal"))
        workspace.retryNow()
        try await waitUntil("Heartbeat recovery did not reconnect") { workspace.state == .connected }
        try await Task.sleep(for: .milliseconds(700))
        try check(workspace.state == .connected, "Old heartbeat callbacks must not disconnect the replacement socket")
        workspace.disconnect()
        try await Task.sleep(for: .milliseconds(650))
        try check(workspace.state == .disconnected, "Disconnect must cancel heartbeat deadlines and prevent reconnect")
    }

    static func sessionRecovery() async throws {
        // The runner is disposable, but restore shared storage even if an assertion fails.
        let previousInstances = try KeychainStore.load(account: "instances")
        let previousSelection = UserDefaults.standard.object(forKey: "selected-instance")
        let store = InstanceStore()
        var added: [Instance] = []
        defer {
            for instance in added { try? store.remove(instance) }
            if let previousInstances { try? KeychainStore.save(previousInstances, account: "instances") }
            else { KeychainStore.delete(account: "instances") }
            UserDefaults.standard.set(previousSelection, forKey: "selected-instance")
        }
        let url = URL(string: "http://127.0.0.1:\(CommandLine.arguments[1])/")!
        try store.add(name: "Fixture One", url: url, allowsInsecureHTTP: true)
        let first = store.selected!
        added.append(first)
        try await store.signIn(username: "operator", password: "password", totp: "123456", to: first)
        try check(store.hasSession(for: first) && store.sessionUser?.id == "u1", "Sign-in must establish a verified user")
        let originalClient = store.client()!
        try check(originalClient === store.client()!, "Views must reuse the selected instance's HTTP session")
        struct Stats: Decodable, Sendable { let sessions: Int; let sockets: Int }
        let signedInStats: Stats = try await originalClient.get("/fixture/connection-stats")
        await store.refreshSession()
        let refreshedStats: Stats = try await originalClient.get("/fixture/connection-stats")
        try check(signedInStats.sessions == refreshedStats.sessions, "An already verified foreground session must not be revalidated")
        store.select(first.id)
        try check(store.hasSession(for: first), "Selecting the current instance must not restart authentication and connections")
        store.invalidateValidation()
        try check(originalClient !== store.client()!, "Invalidation must isolate the next session from old client callbacks")
        try check(!store.hasSession(for: first) && store.hasStoredSession(for: first), "A saved marker must not grant access")
        struct Mode: Encodable, Sendable { let mode: String }
        let client = APIClient(instance: first)
        let _: SuccessResponse = try await client.post("/fixture/session-mode", body: Mode(mode: "server-error"))
        await store.refreshSession()
        try check(store.hasStoredSession(for: first) && !store.hasSession(for: first) && store.sessionError != nil, "Temporary server errors must preserve the marker and require retry")
        let _: SuccessResponse = try await client.post("/fixture/session-mode", body: Mode(mode: "normal"))
        await store.refreshSession()
        try check(store.hasSession(for: first), "Retry must restore a valid Cookie session")
        do { let _: SuccessResponse = try await originalClient.get("/fixture/unauthorized") } catch APIError.unauthorized {}
        try check(store.hasSession(for: first), "An old client's late 401 must not revoke the newly validated session")
        let _: SuccessResponse = try await client.post("/fixture/session-mode", body: Mode(mode: "expired"))
        store.invalidateValidation()
        await store.refreshSession()
        try check(!store.hasStoredSession(for: first) && store.sessionUser == nil, "Explicitly unauthenticated sessions must clear the marker")
        let _: SuccessResponse = try await client.post("/fixture/session-mode", body: Mode(mode: "normal"))
        try await store.signIn(username: "operator", password: "password", totp: "123456", to: first)
        let originalAccess = store.authenticatedAccess()!
        try check(store.isCurrent(originalAccess), "A verified session must provide bound operation access")
        try store.add(name: "Fixture Two", url: url, allowsInsecureHTTP: true)
        let second = store.selected!
        added.append(second)
        try check(!store.isCurrent(originalAccess) && store.authenticatedAccess() == nil, "Switching instances must invalidate pending actions and must not grant access before validation")
        store.select(first.id)
        await store.refreshSession()
        var authentication: CheckedContinuation<Bool, Never>?
        let protected = Task { @MainActor in
            await store.authorizeSession(using: { await withCheckedContinuation { authentication = $0 } })
        }
        try await waitUntil("Protected operation did not await authentication") { authentication != nil }
        store.select(second.id)
        authentication?.resume(returning: true)
        let abandoned = await protected.value
        try check(abandoned == nil, "Authentication finishing after an instance switch must not obtain the new instance's client")
        store.select(first.id)
        await store.refreshSession()
        let access = await store.authorizeSession(using: { true })
        try check(access != nil && store.isCurrent(access!), "Successful authorization must preserve the original verified session")
        store.invalidateValidation()
        await store.refreshSession()
        try check(!store.isCurrent(access!), "Revalidating the same instance and user must reject old operation generations")
        let denied = await store.authorizeSession(using: { false })
        try check(denied == nil, "Cancelled device authentication must not grant operation access")
        authentication = nil
        let cancelled = Task { @MainActor in
            await store.authorizeSession(using: { await withCheckedContinuation { authentication = $0 } })
        }
        try await waitUntil("Cancellation fixture did not authenticate") { authentication != nil }
        cancelled.cancel()
        authentication?.resume(returning: true)
        try check(await cancelled.value == nil, "A cancelled operation must not become authorized later")
        store.invalidateValidation()
        let _: SuccessResponse = try await client.post("/fixture/session-mode", body: Mode(mode: "slow"))
        let refreshing = Task { @MainActor in await store.refreshSession() }
        try await Task.sleep(for: .milliseconds(50))
        store.select(second.id)
        await refreshing.value
        try check(store.selectedID == second.id && store.sessionUser == nil && !store.hasSession(for: second), "A stale session response must not authenticate a newly selected instance")
        let restored = InstanceStore()
        restored.restore()
        try check(restored.selectedID == second.id && restored.sessionUser == nil, "Restore must preserve the selected instance without granting access")
        restored.select(first.id)
        try check(restored.hasStoredSession(for: first) && !restored.hasSession(for: first), "Restored markers must still require server validation")
        let _: SuccessResponse = try await client.post("/fixture/session-mode", body: Mode(mode: "normal"))
    }
}
