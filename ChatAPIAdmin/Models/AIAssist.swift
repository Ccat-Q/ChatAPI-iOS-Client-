import Foundation

enum AICompletionMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case reply, toolCall, toolOutput
    var id: String { rawValue }
    var title: String { switch self { case .reply: localized("Reply", "回复"); case .toolCall: localized("Tool Call", "工具调用"); case .toolOutput: localized("Tool Result", "工具结果") } }
    var symbol: String { switch self { case .reply: "text.bubble"; case .toolCall: "function"; case .toolOutput: "arrow.turn.down.left" } }
    var placeholder: String { switch self { case .reply: localized("Write a reply…", "输入回复…"); case .toolCall: localized("JSON arguments or an instruction for AI…", "输入 JSON 参数，或描述希望 AI 填写的内容…"); case .toolOutput: localized("Enter the actual tool result…", "输入实际工具执行结果…") } }
}

enum AIAssistProtocol: String, Codable, CaseIterable, Identifiable, Sendable {
    case chatCompletions, responses
    var id: String { rawValue }
    var title: String { switch self { case .chatCompletions: "Chat Completions"; case .responses: "Responses" } }
}

struct AIAssistConfiguration: Codable, Equatable, Sendable {
    var baseURL = ""
    var model = ""
    var apiKey = ""
    var wireProtocol: AIAssistProtocol = .chatCompletions
    var automatic = true
    var allowsHTTP = false

    func endpoint(currentServer: URL) throws -> URL {
        guard var components = URLComponents(string: baseURL.trimmingCharacters(in: .whitespacesAndNewlines)),
              let scheme = components.scheme?.lowercased(),
              scheme == "https" || (scheme == "http" && allowsHTTP),
              let host = components.host, !host.isEmpty,
              components.user == nil, components.password == nil,
              components.query == nil, components.fragment == nil,
              components.port.map({ (1...65535).contains($0) }) ?? true,
              !model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AIAssistError.invalidConfiguration(localized("Enter a valid HTTPS Base URL, model, and API key.", "请填写有效的 HTTPS Base URL、模型和 API 密钥。"))
        }
        func port(_ url: URL) -> Int { url.port ?? (url.scheme?.lowercased() == "https" ? 443 : 80) }
        components.scheme = scheme
        guard let base = components.url,
              !(base.scheme == currentServer.scheme?.lowercased() && base.host?.lowercased() == currentServer.host?.lowercased() && port(base) == port(currentServer)) else {
            throw AIAssistError.invalidConfiguration(localized("The assistant model must be separate from this ChatAPI server to avoid recursive human requests.", "辅助模型不能指向当前 ChatAPI 服务，以免循环创建人工请求。"))
        }
        switch wireProtocol {
        case .chatCompletions: return base.appendingPathComponent("chat").appendingPathComponent("completions")
        case .responses: return base.appendingPathComponent("responses")
        }
    }
}

struct AIToolDefinition: Hashable, Sendable, Identifiable {
    let name: String
    let description: String
    let parameters: JSONValue
    var id: String { name }

    static func read(from messages: [WorkspaceTimelineItem], requestID: String? = nil) -> [AIToolDefinition] {
        for item in messages.reversed() {
            guard let debug = item.message?.metadata?["request_debug"]?.object else { continue }
            if let requestID, let declaredID = debug["request_id"]?.string, requestID != declaredID { return [] }
            let schemas = debug["tool_schemas"]?.array ?? []
            var names: Set<String> = []
            return schemas.prefix(32).compactMap { schema in
                guard let record = schema.object,
                      let function = record["function"]?.object ?? schema.object,
                      let name = function["name"]?.string, !name.isEmpty,
                      let parameters = function["parameters"], names.insert(name).inserted else { return nil }
                return AIToolDefinition(name: name, description: String((function["description"]?.string ?? "").prefix(500)), parameters: parameters)
            }
        }
        return []
    }
}

struct AIContextMessage: Hashable, Sendable {
    let role: String
    let text: String
}

struct AICompletionInput: Hashable, Sendable {
    let conversationID: String
    let requestID: String
    let mode: AICompletionMode
    let draft: String
    let toolName: String
    let toolCallID: String
    let instruction: String
    let messages: [AIContextMessage]
    let tools: [AIToolDefinition]

    var hasContext: Bool { !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !instruction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || messages.contains { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } }

    static func make(conversation: WorkspaceConversation, items: [WorkspaceTimelineItem], mode: AICompletionMode, draft: String, toolName: String, toolCallID: String, instruction: String) -> AICompletionInput {
        let messages = items.compactMap(\.message).suffix(12).map {
            AIContextMessage(role: $0.role, text: String($0.content.prefix(2000)))
        }
        return AICompletionInput(conversationID: conversation.id, requestID: conversation.requestID, mode: mode, draft: draft, toolName: toolName.trimmingCharacters(in: .whitespacesAndNewlines), toolCallID: toolCallID.trimmingCharacters(in: .whitespacesAndNewlines), instruction: instruction, messages: messages, tools: AIToolDefinition.read(from: items, requestID: conversation.requestID))
    }

    var payload: JSONValue {
        .object([
            "mode": .string(mode.rawValue), "draft": .string(draft), "operator_instruction": .string(instruction),
            "selected_tool": .string(toolName), "tool_call_id": .string(toolCallID),
            "recent_messages": .array(messages.map { .object(["role": .string($0.role), "text": .string($0.text)]) }),
            "available_tools": .array(tools.map { .object(["name": .string($0.name), "description": .string($0.description), "parameters": $0.parameters]) })
        ])
    }
}

struct AICompletionSuggestion: Equatable, Sendable {
    let text: String
    let toolName: String
    let toolCallID: String

    static func parse(_ text: String, for input: AICompletionInput) throws -> AICompletionSuggestion {
        guard let data = text.data(using: .utf8),
              let value = try? JSONDecoder().decode(JSONValue.self, from: data), let object = value.object else {
            throw AIAssistError.invalidSuggestion(localized("The model did not return a valid suggestion object.", "模型未返回有效的 JSON 建议。"))
        }
        if input.mode == .toolCall {
            guard let name = object["tool_name"]?.string, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  let arguments = object["arguments"], arguments.object != nil else {
                throw AIAssistError.invalidSuggestion(localized("Tool suggestions require a name and JSON object arguments.", "工具建议必须包含名称和 JSON 对象参数。"))
            }
            if !input.toolName.isEmpty, name != input.toolName {
                throw AIAssistError.invalidSuggestion(localized("The suggestion changed the selected tool.", "建议更改了已选择的工具，请重新生成。"))
            }
            if !input.tools.isEmpty {
                guard let tool = input.tools.first(where: { $0.name == name }) else {
                    throw AIAssistError.invalidSuggestion(localized("The model selected a tool outside this request.", "模型选择了当前请求未声明的工具。"))
                }
                try ToolArgumentValidator.validate(arguments, schema: tool.parameters)
            }
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let json = String(decoding: try encoder.encode(arguments), as: UTF8.self)
            guard json.count <= 32_000 else { throw AIAssistError.tooLarge }
            return AICompletionSuggestion(text: json, toolName: name, toolCallID: input.toolCallID.isEmpty ? "call_\(UUID().uuidString)" : input.toolCallID)
        }
        guard let content = object["text"]?.string, !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              content.count <= 32_000 else {
            throw AIAssistError.invalidSuggestion(localized("The model returned empty or oversized text.", "模型返回了空文本或过长文本。"))
        }
        // Existing correlation IDs are operator-owned; never replace them with model output.
        return AICompletionSuggestion(text: content, toolName: input.toolName, toolCallID: input.toolCallID)
    }
}

enum AIAssistError: LocalizedError {
    case invalidConfiguration(String), invalidSuggestion(String), invalidResponse, tooLarge, http(Int)
    var errorDescription: String? {
        switch self {
        case .invalidConfiguration(let message), .invalidSuggestion(let message): message
        case .invalidResponse: localized("The assistant model returned an invalid response.", "辅助模型返回了无效响应。")
        case .tooLarge: localized("The assistant model request or response exceeded its size limit.", "辅助模型请求或响应超过大小限制。")
        case .http(let status): localized("Assistant model request failed (HTTP \(status)). Check your provider configuration.", "辅助模型请求失败（HTTP \(status)），请检查服务配置。")
        }
    }
}

extension JSONValue {
    var object: [String: JSONValue]? { if case .object(let value) = self { value } else { nil } }
    var array: [JSONValue]? { if case .array(let value) = self { value } else { nil } }
    var string: String? { if case .string(let value) = self { value } else { nil } }
    var number: Double? { if case .number(let value) = self { value } else { nil } }
}

// A bounded, common subset of JSON Schema. The server remains the final validator.
enum ToolArgumentValidator {
    static func validate(_ value: JSONValue, schema: JSONValue, path: String = "$", depth: Int = 0) throws {
        guard depth <= 32 else { throw AIAssistError.invalidSuggestion(localized("Tool schema is too deeply nested.", "工具 schema 嵌套过深。")) }
        if schema == .bool(false) { throw AIAssistError.invalidSuggestion(localized("The tool schema does not permit these arguments.", "工具 schema 不允许这些参数。")) }
        guard let schema = schema.object else { return }
        func invalid() -> AIAssistError { .invalidSuggestion(localized("Tool arguments do not match the schema at ", "工具参数不符合 schema：") + path) }
        if let options = schema["enum"]?.array, !options.contains(value) { throw invalid() }
        let types: [String]
        if let type = schema["type"]?.string { types = [type] }
        else { types = schema["type"]?.array?.compactMap(\.string) ?? [] }
        if !types.isEmpty {
            let matches = types.contains { type in
                switch (type, value) {
                case ("object", .object), ("array", .array), ("string", .string), ("boolean", .bool), ("null", .null), ("number", .number): true
                case ("integer", .number(let number)): number.isFinite && number.rounded() == number
                default: false
                }
            }
            guard matches else { throw invalid() }
        }
        if let object = value.object {
            let properties = schema["properties"]?.object ?? [:]
            for required in schema["required"]?.array?.compactMap(\.string) ?? [] where object[required] == nil { throw invalid() }
            for (key, child) in object {
                if let childSchema = properties[key] { try validate(child, schema: childSchema, path: "\(path).\(key)", depth: depth + 1) }
                else if schema["additionalProperties"] == .bool(false) { throw invalid() }
                else if let additional = schema["additionalProperties"], additional.object != nil { try validate(child, schema: additional, path: "\(path).\(key)", depth: depth + 1) }
            }
        }
        if let array = value.array {
            if let min = schema["minItems"]?.number, Double(array.count) < min { throw invalid() }
            if let max = schema["maxItems"]?.number, Double(array.count) > max { throw invalid() }
            if let items = schema["items"] { for (index, item) in array.enumerated() { try validate(item, schema: items, path: "\(path)[\(index)]", depth: depth + 1) } }
        }
        if let number = value.number {
            if let min = schema["minimum"]?.number, number < min { throw invalid() }
            if let max = schema["maximum"]?.number, number > max { throw invalid() }
        }
        if let string = value.string {
            if let min = schema["minLength"]?.number, Double(string.unicodeScalars.count) < min { throw invalid() }
            if let max = schema["maxLength"]?.number, Double(string.unicodeScalars.count) > max { throw invalid() }
        }
    }
}

struct WorkspaceComposerDraft: Codable, Equatable, Sendable {
    var version = 1
    var mode: AICompletionMode = .reply
    var reply = ""
    var toolArguments = ""
    var toolOutput = ""
    var toolName = ""
    var toolCallID = ""
    var aiInstruction = ""

    var text: String {
        get { switch mode { case .reply: reply; case .toolCall: toolArguments; case .toolOutput: toolOutput } }
        set { switch mode { case .reply: reply = newValue; case .toolCall: toolArguments = newValue; case .toolOutput: toolOutput = newValue } }
    }
    var isEmpty: Bool { [reply, toolArguments, toolOutput, toolName, toolCallID, aiInstruction].allSatisfy(\.isEmpty) }
    static func restore(_ data: Data) -> WorkspaceComposerDraft {
        if let draft = try? JSONDecoder().decode(Self.self, from: data), draft.version == 1 { return draft }
        var draft = Self()
        draft.reply = String(decoding: data, as: UTF8.self)
        return draft
    }
}
