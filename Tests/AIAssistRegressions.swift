import Foundation

private actor CompletionRecorder {
    var calls = 0
    func complete(_ input: AICompletionInput) async -> AICompletionSuggestion {
        calls += 1
        // Ignore cancellation deliberately: the controller must also reject late results.
        if input.draft == "old" { try? await Task.sleep(for: .milliseconds(250)) }
        return AICompletionSuggestion(text: input.draft, toolName: "", toolCallID: input.toolCallID)
    }
}

extension CoreRegressions {
    static func aiInput(mode: AICompletionMode = .reply, text: String = "Continue", toolName: String = "", toolCallID: String = "", tools: [AIToolDefinition] = []) -> AICompletionInput {
        AICompletionInput(conversationID: "c1", requestID: "r1", mode: mode, draft: text, toolName: toolName, toolCallID: toolCallID, instruction: "", messages: [], tools: tools)
    }

    static func aiRegressions() async throws {
        let currentServer = URL(string: "https://workspace.example/")!
        var configuration = AIAssistConfiguration(baseURL: "https://model.example/v1/", model: "fixture", apiKey: "ai-fixture")
        try check(try configuration.endpoint(currentServer: currentServer).absoluteString == "https://model.example/v1/chat/completions", "Assistant endpoint must preserve the provider's base path")
        configuration.wireProtocol = .responses
        try check(try configuration.endpoint(currentServer: currentServer).path == "/v1/responses", "Responses endpoint must be supported")
        for address in ["https://workspace.example:443/v1", "https://user:pass@model.example/v1", "http://model.example/v1", "ftp://model.example/v1", "https://model.example/v1?q=1"] {
            var invalid = configuration; invalid.baseURL = address
            do { _ = try invalid.endpoint(currentServer: currentServer); try check(false, "Unsafe or recursive AI endpoint accepted") }
            catch is AIAssistError { try check(true, "Unsafe endpoint rejected") }
        }
        let schema = try decode(JSONValue.self, #"{"type":"object","required":["city"],"additionalProperties":false,"properties":{"city":{"type":"string","minLength":1},"unit":{"type":"string","enum":["celsius","fahrenheit"]}}}"#)
        let tool = AIToolDefinition(name: "get_weather", description: "Weather", parameters: schema)
        let toolInput = aiInput(mode: .toolCall, text: "Shanghai weather", toolName: "get_weather", toolCallID: "operator-call", tools: [tool])
        let candidate = try AICompletionSuggestion.parse(#"{"tool_name":"get_weather","arguments":{"city":"上海","unit":"celsius"},"tool_call_id":"untrusted"}"#, for: toolInput)
        try check(candidate.toolName == "get_weather" && candidate.toolCallID == "operator-call", "AI must preserve the operator's tool association")
        try check(try decode(JSONValue.self, candidate.text).object?["city"] == .string("上海"), "Validated arguments must become an editable JSON draft")
        for invalid in [#"{"tool_name":"other","arguments":{"city":"上海"}}"#, #"{"tool_name":"get_weather","arguments":[]}"#, #"{"tool_name":"get_weather","arguments":{}}"#, #"{"tool_name":"get_weather","arguments":{"city":42}}"#, #"{"tool_name":"get_weather","arguments":{"city":"上海","unit":"invalid"}}"#, #"{"tool_name":"get_weather","arguments":{"city":"上海","extra":true}}"#] {
            do { _ = try AICompletionSuggestion.parse(invalid, for: toolInput); try check(false, "Invalid tool suggestion accepted") }
            catch is AIAssistError { try check(true, "Invalid tool suggestion rejected") }
        }
        let output = try AICompletionSuggestion.parse(#"{"text":"Actual result","tool_call_id":"untrusted"}"#, for: aiInput(mode: .toolOutput, toolCallID: "original"))
        try check(output.toolCallID == "original", "Tool result suggestions must not invent correlation IDs")
        let timeline = try decode(WorkspaceTimelineReset.self, #"{"type":"timeline.reset","conversation_id":"c1","items":[{"id":"m1","kind":"message","message":{"id":"m1","role":"user","content":"Weather","created_at":"2026-10-22T12:00:00Z","metadata":{"request_debug":{"tool_schemas":[{"type":"function","function":{"name":"get_weather","description":"Weather","parameters":{"type":"object"}}}]}}}}]}"#)
        try check(AIToolDefinition.read(from: timeline.items).first?.name == "get_weather", "Tools must come from actual request metadata")
        let oldDraft = WorkspaceComposerDraft.restore(Data("legacy reply".utf8))
        try check(oldDraft.reply == "legacy reply" && oldDraft.mode == .reply, "Existing text drafts must migrate without data loss")
        var draft = oldDraft
        draft.mode = .toolCall; draft.text = "{}"; draft.toolName = "get_weather"
        draft.mode = .toolOutput; draft.text = "result"
        draft.mode = .reply
        try check(draft.text == "legacy reply" && draft.toolArguments == "{}" && draft.toolOutput == "result", "Composer modes must keep independent drafts")
        try check(WorkspaceComposerDraft.restore(try JSONEncoder().encode(draft)) == draft, "Structured composer drafts must round-trip")
        configuration.wireProtocol = .chatCompletions
        let chatBody = try decode(JSONValue.self, String(decoding: AIAssistClient.body(configuration: configuration, input: toolInput), as: UTF8.self))
        try check(chatBody.object?["messages"]?.array?.count == 2 && chatBody.object?["stream"] == .bool(false), "Chat completions must include instructions and context without streaming")
        configuration.wireProtocol = .responses
        let responsesBody = try decode(JSONValue.self, String(decoding: AIAssistClient.body(configuration: configuration, input: toolInput), as: UTF8.self))
        try check(responsesBody.object?["store"] == .bool(false) && responsesBody.object?["instructions"]?.string != nil, "Responses requests must disable storage and include instructions")
        try await aiNetwork(configuration: configuration, toolInput: toolInput)
        try await aiController(configuration: configuration)
    }

    static func aiNetwork(configuration: AIAssistConfiguration, toolInput: AICompletionInput) async throws {
        var configuration = configuration
        configuration.baseURL = "http://127.0.0.1:\(CommandLine.arguments[1])/ai"
        configuration.allowsHTTP = true
        let server = URL(string: "https://workspace.example/")!
        let client = AIAssistClient()
        let cookie = HTTPCookie(properties: [.domain: "127.0.0.1", .path: "/", .name: "fixture_session", .value: "must-not-leak"])!
        HTTPCookieStorage.shared.setCookie(cookie)
        defer { HTTPCookieStorage.shared.deleteCookie(cookie) }
        configuration.wireProtocol = .chatCompletions
        let reply = try await client.complete(configuration: configuration, input: aiInput(), currentServer: server)
        try check(reply.text == "Suggested reply", "AI requests must authenticate with only the separate key, never the ChatAPI Cookie")
        configuration.wireProtocol = .responses
        let responsesReply = try await client.complete(configuration: configuration, input: aiInput(), currentServer: server)
        try check(responsesReply.text == "Suggested reply", "Responses output content must be extracted")
        configuration.model = "tool"
        let tool = try await client.complete(configuration: configuration, input: toolInput, currentServer: server)
        try check(tool.toolName == "get_weather", "Network tool suggestions must pass schema validation")
        configuration.model = "bad-tool"
        do { _ = try await client.complete(configuration: configuration, input: toolInput, currentServer: server); try check(false, "Network schema mismatch accepted") }
        catch is AIAssistError { try check(true, "Network schema mismatch rejected") }
        configuration.model = "redirect"
        do { _ = try await client.complete(configuration: configuration, input: aiInput(), currentServer: server); try check(false, "AI redirect accepted") }
        catch AIAssistError.http(let code) { try check(code == 307, "All AI redirects must be rejected") }
        configuration.model = "oversize"
        do { _ = try await client.complete(configuration: configuration, input: aiInput(), currentServer: server); try check(false, "Oversized AI response accepted") }
        catch AIAssistError.tooLarge { try check(true, "AI response limit enforced") }
        configuration.model = "slow"
        let slowConfiguration = configuration
        let pending = Task { () -> Bool in
            do { _ = try await client.complete(configuration: slowConfiguration, input: aiInput(), currentServer: server); return false }
            catch { return Task.isCancelled }
        }
        try await Task.sleep(for: .milliseconds(50))
        pending.cancel()
        try check(await pending.value, "AI network requests must support cancellation")
    }

    static func aiController(configuration: AIAssistConfiguration) async throws {
        let instance = Instance(id: UUID(), name: "AI Fixture", baseURL: URL(string: "https://workspace.example/")!, allowsInsecureHTTP: false, capabilities: nil)
        defer { AIAssistConfigurationStore.delete(instanceID: instance.id, userID: "fixture-owner") }
        try AIAssistConfigurationStore.save(configuration, instanceID: instance.id, userID: "fixture-owner")
        try check(try AIAssistConfigurationStore.load(instanceID: instance.id, userID: "other-owner") == nil, "Assistant keys must be scoped to the signed-in owner")
        let recorder = CompletionRecorder()
        let controller = AIComposerController { _, input, _ in await recorder.complete(input) }
        controller.reload(instance: instance, userID: "fixture-owner")
        controller.schedule(aiInput(text: "old"), instance: instance, automatically: false)
        try await Task.sleep(for: .milliseconds(50))
        controller.schedule(aiInput(text: "new"), instance: instance, automatically: false)
        try await waitUntil("New AI suggestion did not arrive") { controller.suggestion?.text == "new" }
        try await Task.sleep(for: .milliseconds(300))
        try check(controller.suggestion?.text == "new", "Late cancelled generations must not replace a newer suggestion")
        try check(controller.takeSuggestion(for: aiInput(text: "different")) == nil, "A suggestion for an old input must not be applied")
        let calls = await recorder.calls
        controller.schedule(aiInput(text: "first"), instance: instance, automatically: true)
        try await Task.sleep(for: .milliseconds(100))
        controller.schedule(aiInput(text: "last"), instance: instance, automatically: true)
        try await waitUntil("Debounced completion did not arrive") { controller.suggestion?.text == "last" }
        try check(await recorder.calls == calls + 1, "Automatic typing must debounce into one request")
        try check(controller.takeSuggestion(for: aiInput(text: "last"))?.text == "last" && controller.suggestion == nil, "Applying must consume only the matching suggestion")
        controller.setAutomatic(false)
        controller.schedule(aiInput(text: "disabled"), instance: instance, automatically: true)
        try check(!controller.isGenerating, "Disabled automatic mode must not send requests")
        let other = Instance(id: UUID(), name: "Other", baseURL: instance.baseURL, allowsInsecureHTTP: false, capabilities: nil)
        controller.schedule(aiInput(), instance: other, automatically: false)
        try check(!controller.isGenerating, "A configuration must never be reused for a different instance")
    }
}
