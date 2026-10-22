import Foundation

struct Instance: Codable, Sendable, Identifiable, Hashable {
    let id: UUID
    var name: String
    var baseURL: URL
    var allowsInsecureHTTP: Bool
    var capabilities: Capabilities?

    static func validatedURL(_ url: URL, allowsInsecureHTTP: Bool) throws -> URL {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let scheme = components.scheme?.lowercased(), ["https", "http"].contains(scheme),
              let host = components.host, !host.isEmpty,
              components.user == nil, components.password == nil,
              components.query == nil, components.fragment == nil,
              components.path.isEmpty || components.path == "/",
              components.port.map({ (1...65535).contains($0) }) ?? true else { throw InstanceError.invalidURL }
        guard scheme == "https" || allowsInsecureHTTP else { throw InstanceError.insecureURL }
        components.scheme = scheme
        components.path = "/"
        guard let normalized = components.url else { throw InstanceError.invalidURL }
        return normalized
    }
}

enum InstanceError: LocalizedError {
    case insecureURL, invalidURL, emptyName
    var errorDescription: String? {
        switch self {
        case .insecureURL: localized("Use HTTPS, or explicitly allow a development HTTP instance.", "请使用 HTTPS，或明确允许开发实例使用 HTTP。")
        case .invalidURL: localized("Enter a server root URL with a host, without credentials, a path, query, or fragment.", "请输入包含主机名的服务器根地址，不要包含凭据、路径、查询参数或片段。")
        case .emptyName: localized("Enter an instance name.", "请输入实例名称。")
        }
    }
}

struct Capabilities: Codable, Sendable, Hashable {
    let version: Int
    let features: Set<String>
}

struct SettingsDomain: Codable, Sendable, Identifiable, Hashable {
    let domain: String
    var id: String { domain }
    let title: String
    let fields: [SettingsField]
}

struct SettingsField: Codable, Sendable, Identifiable, Hashable {
    let key: String
    let title: String
    let type: String
    let description: String
    let editable: Bool
    let sensitive: Bool
    let restartRequired: Bool
    let options: [String]?
    let minimum: Double?
    let maximum: Double?

    var id: String { key }

    enum CodingKeys: String, CodingKey {
        case key, title, type, description, editable, sensitive, restartRequired = "restart_required", options = "enum", minimum, maximum
    }
}

struct Overview: Codable, Sendable, Hashable {
    let ok: Bool
    let mode: String
    let driver: String
}

struct AdminConversation: Codable, Sendable, Identifiable, Hashable {
    let id: String
    let title: String
    let lastUserText: String
    let lastMessagePreview: String
    let messageCount: Int
    let updatedAt: Date
    enum CodingKeys: String, CodingKey { case id, title; case lastUserText = "last_user_text", lastMessagePreview = "last_message_preview", messageCount = "message_count", updatedAt = "updated_at" }
}

struct ConversationListResponse: Codable, Sendable { let items: [AdminConversation] }

struct ConversationMessage: Codable, Sendable, Identifiable, Hashable {
    let id: String
    let role: String
    let content: String
    let createdAt: Date
    enum CodingKeys: String, CodingKey { case id, role, content; case createdAt = "created_at" }
}

struct ConversationMessageListResponse: Codable, Sendable { let items: [ConversationMessage] }
struct CompleteConversationInput: Encodable, Sendable { let text: String; let mode = "assistant_message" }

struct SessionResponse: Codable, Sendable {
    let authenticated: Bool
    let user: SessionUser?
}

struct SessionUser: Codable, Sendable, Hashable {
    let id: String
    let username: String
    let role: String
    var isAdministrator: Bool { role.lowercased() == "admin" || role.lowercased() == "superadmin" }
}

struct WorkspaceConversation: Codable, Sendable, Identifiable, Hashable {
    let id: String
    let title: String
    let lastUserText: String
    let lastMessagePreview: String
    let requestID: String
    let status: String
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id, title, status
        case lastUserText = "last_user_text"
        case lastMessagePreview = "last_message_preview"
        case requestID = "request_id"
        case updatedAt = "updated_at"
    }
}

struct WorkspaceSnapshot: Codable, Sendable {
    let type: String
    let conversations: [WorkspaceConversation]
    let hasMore: Bool?
    let nextCursor: String?
    enum CodingKeys: String, CodingKey { case type, conversations, hasMore = "has_more", nextCursor = "next_cursor" }
}

struct WorkspaceConversationPage: Decodable, Sendable {
    let commandID: String
    let conversations: [WorkspaceConversation]
    let hasMore: Bool
    let nextCursor: String?
    enum CodingKeys: String, CodingKey { case commandID = "command_id", conversations, hasMore = "has_more", nextCursor = "next_cursor" }
}

struct WorkspaceTimelineMessage: Codable, Sendable, Identifiable, Hashable {
    let id: String
    let role: String
    let content: String
    let createdAt: Date
    let contentParts: [WorkspaceContentPart]?

    enum CodingKeys: String, CodingKey {
        case id, role, content
        case createdAt = "created_at"
        case contentParts = "content_parts"
    }
}

struct WorkspaceContentPart: Codable, Sendable, Hashable {
    let type: String
    let text: String?
    let src: String?
    let mediaType: String?
    enum CodingKeys: String, CodingKey { case type, text, src; case mediaType = "media_type" }
}

struct WorkspaceTimelineItem: Codable, Sendable, Identifiable, Hashable {
    let id: String
    let kind: String
    let message: WorkspaceTimelineMessage?
}

struct WorkspaceTimelineReset: Codable, Sendable {
    let type: String
    let conversationID: String
    let items: [WorkspaceTimelineItem]

    enum CodingKeys: String, CodingKey {
        case type, items
        case conversationID = "conversation_id"
    }
}

struct WorkspaceConversationUpsert: Codable, Sendable {
    let type: String
    let conversation: WorkspaceConversation
}

struct WorkspaceTimelineAppend: Codable, Sendable {
    let type: String
    let conversationID: String
    let item: WorkspaceTimelineItem

    enum CodingKeys: String, CodingKey {
        case type, item
        case conversationID = "conversation_id"
    }
}

struct WorkspaceCommandError: Codable, Sendable {
    let type: String
    let message: String?
    let error: String?
    let commandID: String?
    enum CodingKeys: String, CodingKey { case type, message, error, commandID = "command_id" }
}

struct WorkspaceCommandAck: Decodable, Sendable {
    let commandID: String
    let conversationID: String
    let requestID: String
    enum CodingKeys: String, CodingKey { case commandID = "command_id", conversationID = "conversation_id", requestID = "request_id" }
}

struct WorkspaceCommand: Encodable, Sendable {
    let commandID: String
    let kind: String
    let conversationID: String
    let requestID: String
    let text: String
    let mode: String
    let toolName: String
    let toolCallID: String
    let output: String

    enum CodingKeys: String, CodingKey {
        case commandID = "command_id", kind, conversationID = "conversation_id", requestID = "request_id", text, mode, toolName = "tool_name", toolCallID = "tool_call_id", output
    }
}

struct WorkspaceCommandEnvelope: Encodable, Sendable { let type = "workspace.command"; let command: WorkspaceCommand }

struct AdminUser: Codable, Sendable, Identifiable, Hashable {
    let id: String
    let username: String
    let role: String
    let isActive: Bool
    enum CodingKeys: String, CodingKey { case id, username, role; case isActive = "is_active" }
}

struct UserListResponse: Codable, Sendable { let items: [AdminUser] }
struct SettingsCatalogResponse: Codable, Sendable { let catalog: SettingsCatalog }
struct SettingsCatalog: Codable, Sendable { let groups: [SettingsDomain] }

struct SettingsDocument: Codable, Sendable {
    let domain: String
    let title: String
    let values: [String: JSONValue]
    let fields: [SettingsField]
}

struct SettingsDocumentResponse: Codable, Sendable { let document: SettingsDocument }
struct SettingsPatchResponse: Decodable, Sendable { let result: SettingsPatchResult }
struct SettingsPatchResult: Decodable, Sendable {
    let document: SettingsDocument
    let restartRequired: [String]?
    let warnings: [String]?
    enum CodingKeys: String, CodingKey { case document, restartRequired = "restart_required", warnings }
}
struct SuccessResponse: Codable, Sendable { let ok: Bool }
struct EmptyRequest: Encodable, Sendable {}

struct SettingsPatchInput: Encodable, Sendable { let values: [String: JSONValue] }

enum JSONValue: Codable, Sendable, Hashable {
    case string(String), number(Double), bool(Bool), array([JSONValue]), object([String: JSONValue]), null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() { self = .null }
        else if let value = try? container.decode(Bool.self) { self = .bool(value) }
        else if let value = try? container.decode(Double.self) { self = .number(value) }
        else if let value = try? container.decode([JSONValue].self) { self = .array(value) }
        else if let value = try? container.decode([String: JSONValue].self) { self = .object(value) }
        else { self = .string(try container.decode(String.self)) }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value): try container.encode(value)
        case .number(let value): try container.encode(value)
        case .bool(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        case .null: try container.encodeNil()
        }
    }

    var displayValue: String {
        switch self {
        case .string(let value): value
        case .number(let value): Int(exactly: value).map(String.init) ?? String(value)
        case .bool(let value): value ? "true" : "false"
        case .null: ""
        case .array, .object: (try? String(data: JSONEncoder().encode(self), encoding: .utf8)) ?? ""
        }
    }
}

struct ActivityItem: Codable, Sendable, Identifiable, Hashable {
    let requestID: String
    let status: String?
    let model: String?
    let requestPath: String?
    let conversationID: String?
    let createdAt: Date?

    var id: String { requestID }
    var title: String { let model = model ?? ""; let path = requestPath ?? ""; return model.isEmpty ? (path.isEmpty ? requestID : path) : model }
    var kind: String { status ?? "unknown" }
    var detail: String? { let path = requestPath ?? ""; return path.isEmpty ? nil : path }

    enum CodingKeys: String, CodingKey {
        case requestID = "request_id", status, model, requestPath = "request_path", conversationID = "conversation_id", createdAt = "created_at"
    }
}

struct ActivityListResponse: Codable, Sendable { let items: [ActivityItem] }

struct BarkTarget: Codable, Sendable, Hashable {
    var key: String
    var health: Bool
    var pendingWork: Bool
    var security: Bool
    var includeFullDetail: Bool
    enum CodingKeys: String, CodingKey { case key, health, security; case pendingWork = "pending_work", includeFullDetail = "include_full_detail" }
}

struct BarkSettings: Codable, Sendable, Hashable {
    var deviceKey: String?
    var enabled: Bool
    var health: Bool
    var pendingWork: Bool
    var security: Bool
    var configured: Bool?
    enum CodingKeys: String, CodingKey { case deviceKey = "device_key", enabled, health, pendingWork = "pending_work", security, configured }
}

struct AutomationRuleListResponse: Codable, Sendable { let rules: [AutomationRule] }

struct AutomationRuleSaveResponse: Codable, Sendable { let rule: AutomationRule }

struct AutomationRule: Codable, Sendable, Identifiable, Hashable {
    var schemaVersion: Int
    var id: String
    var name: String
    var enabled: Bool
    var priority: Int
    var match: AutomationMatch
    var playback: AutomationPlayback
    var steps: [AutomationStep]

    enum CodingKeys: String, CodingKey {
        case id, name, enabled, priority, match, playback, steps
        case schemaVersion = "schema_version"
    }

    static var empty: AutomationRule {
        AutomationRule(schemaVersion: 3, id: "", name: "", enabled: true, priority: 0,
                       match: .init(pattern: "", modelPattern: "", modelKeyID: "", target: ""),
                       playback: .init(mode: "recorded", initialDelayMS: 0, fixedIntervalMS: 1000, loop: false, loopIntervalMS: 1000),
                       steps: [.init(id: UUID().uuidString, delayBeforeMS: 0, action: .init(kind: "stream_complete", text: "", mode: "assistant_message", toolName: "", toolCallID: "", output: ""))])
    }
}

struct AutomationMatch: Codable, Sendable, Hashable {
    var pattern: String; var modelPattern: String; var modelKeyID: String; var target: String
    enum CodingKeys: String, CodingKey { case pattern, target; case modelPattern = "model_pattern"; case modelKeyID = "model_key_id" }
}

struct AutomationPlayback: Codable, Sendable, Hashable {
    var mode: String; var initialDelayMS: Int; var fixedIntervalMS: Int; var loop: Bool; var loopIntervalMS: Int
    enum CodingKeys: String, CodingKey { case mode, loop; case initialDelayMS = "initial_delay_ms"; case fixedIntervalMS = "fixed_interval_ms"; case loopIntervalMS = "loop_interval_ms" }
}

struct AutomationStep: Codable, Sendable, Identifiable, Hashable {
    var id: String; var delayBeforeMS: Int; var action: AutomationAction
    enum CodingKeys: String, CodingKey { case id, action; case delayBeforeMS = "delay_before_ms" }
}

struct AutomationAction: Codable, Sendable, Hashable {
    var kind: String; var text: String; var mode: String; var toolName: String; var toolCallID: String; var output: String
    var builtinToolKind: String? = nil
    var builtinToolQuery: String? = nil
    var builtinToolAssetID: String? = nil
    var reasoningStreamMode: String? = nil
    var error: String? = nil
    enum CodingKeys: String, CodingKey { case kind, text, mode, output, error; case toolName = "tool_name", toolCallID = "tool_call_id", builtinToolKind = "builtin_tool_kind", builtinToolQuery = "builtin_tool_query", builtinToolAssetID = "builtin_tool_asset_id", reasoningStreamMode = "reasoning_stream_mode" }
}

struct APIKey: Codable, Sendable, Identifiable, Hashable {
    let id: String; let name: String; let keyPrefix: String?; let scopes: [String]?; let createdAt: Date
    enum CodingKeys: String, CodingKey { case id, name, scopes; case keyPrefix = "key_prefix"; case createdAt = "created_at" }
}
struct APIKeyListResponse: Codable, Sendable { let items: [APIKey]; enum CodingKeys: String, CodingKey { case items = "api_keys" } }
struct APIKeyCreateResponse: Codable, Sendable { let apiKey: APIKeySecret; enum CodingKeys: String, CodingKey { case apiKey = "api_key" } }
struct APIKeySecret: Codable, Sendable { let id: String; let name: String; let apiKey: String; enum CodingKeys: String, CodingKey { case id, name; case apiKey = "api_key" } }
struct APIKeyRevealResponse: Codable, Sendable { let apiKey: String; enum CodingKeys: String, CodingKey { case apiKey = "api_key" } }
struct ModelKey: Codable, Sendable, Identifiable, Hashable { let id: String; let name: String; let keyPrefix: String?; let createdAt: Date; enum CodingKeys: String, CodingKey { case id, name; case keyPrefix = "key_prefix"; case createdAt = "created_at" } }
struct ModelKeyListResponse: Codable, Sendable { let items: [ModelKey] }
struct ModelKeyCreateResponse: Codable, Sendable { let modelKey: APIKeySecret; enum CodingKeys: String, CodingKey { case modelKey = "model_key" } }
struct VirtualModel: Codable, Sendable, Identifiable, Hashable { let id: String; let name: String; let createdAt: Date; enum CodingKeys: String, CodingKey { case id, name; case createdAt = "created_at" } }
struct VirtualModelListResponse: Codable, Sendable { let items: [VirtualModel] }
struct VirtualModelCreateResponse: Codable, Sendable { let item: VirtualModel }
struct CreateAppKeyInput: Encodable, Sendable { let name: String; let scopes: [String]; let resourceLimits: [String: String]; enum CodingKeys: String, CodingKey { case name, scopes; case resourceLimits = "resource_limits" } }
struct CreateModelKeyInput: Encodable, Sendable { let name: String; let key: String }
struct CreateVirtualModelInput: Encodable, Sendable { let name: String }

extension WorkspaceConversation {
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        lastUserText = try container.decode(String.self, forKey: .lastUserText)
        lastMessagePreview = try container.decode(String.self, forKey: .lastMessagePreview)
        requestID = try container.decodeIfPresent(String.self, forKey: .requestID) ?? ""
        status = try container.decodeIfPresent(String.self, forKey: .status) ?? ""
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
    }
}

extension AutomationMatch {
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        pattern = try container.decodeIfPresent(String.self, forKey: .pattern) ?? ""
        modelPattern = try container.decodeIfPresent(String.self, forKey: .modelPattern) ?? ""
        modelKeyID = try container.decodeIfPresent(String.self, forKey: .modelKeyID) ?? ""
        target = try container.decodeIfPresent(String.self, forKey: .target) ?? ""
    }
}

extension AutomationAction {
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        kind = try container.decode(String.self, forKey: .kind)
        text = try container.decodeIfPresent(String.self, forKey: .text) ?? ""
        mode = try container.decodeIfPresent(String.self, forKey: .mode) ?? ""
        toolName = try container.decodeIfPresent(String.self, forKey: .toolName) ?? ""
        toolCallID = try container.decodeIfPresent(String.self, forKey: .toolCallID) ?? ""
        output = try container.decodeIfPresent(String.self, forKey: .output) ?? ""
        builtinToolKind = try container.decodeIfPresent(String.self, forKey: .builtinToolKind)
        builtinToolQuery = try container.decodeIfPresent(String.self, forKey: .builtinToolQuery)
        builtinToolAssetID = try container.decodeIfPresent(String.self, forKey: .builtinToolAssetID)
        reasoningStreamMode = try container.decodeIfPresent(String.self, forKey: .reasoningStreamMode)
        error = try container.decodeIfPresent(String.self, forKey: .error)
    }
}

extension Instance {
    func draftAccount(userID: String, conversationID: String, requestID: String) -> String {
        // Encode components together to avoid delimiter collisions in server IDs.
        let components = [userID, conversationID, requestID]
        let suffix = (try? JSONEncoder().encode(components).base64EncodedString()) ?? ""
        return "workspace-draft.\(id.uuidString).\(suffix)"
    }
}

extension SettingsField {
    var supportsEditing: Bool { editable && ["boolean", "string", "integer", "number"].contains(type) }

    func parsed(_ text: String) throws -> JSONValue {
        let value: JSONValue
        if type == "integer" || type == "number" {
            guard let number = Double(text), number.isFinite,
                  type != "integer" || number.rounded() == number,
                  minimum.map({ number >= $0 }) ?? true,
                  maximum.map({ number <= $0 }) ?? true else {
                throw APIError.server(localized("Enter a valid number for", "请输入有效数字：") + " \(title)")
            }
            value = .number(number)
        } else { value = .string(text) }
        if let options, !options.isEmpty, !options.contains(text) {
            throw APIError.server(localized("Choose an allowed value for", "请选择允许的值：") + " \(title)")
        }
        return value
    }
}

extension SettingsDocument {
    func patch(values edited: [String: JSONValue], textEdits: [String: String]) throws -> [String: JSONValue] {
        var changes: [String: JSONValue] = [:]
        for field in fields where field.supportsEditing {
            let value: JSONValue?
            if let text = textEdits[field.key] { value = try field.parsed(text) }
            else { value = edited[field.key] }
            if let value, value != values[field.key] { changes[field.key] = value }
        }
        return changes
    }
}

struct AuditLogItem: Decodable, Sendable, Identifiable {
    let id: String
    let eventType: String
    let action: String
    let outcome: String
    let createdAt: Date
    enum CodingKeys: String, CodingKey { case id, eventType = "event_type", action, outcome, createdAt = "created_at" }
}
struct AuditLogResponse: Decodable, Sendable { let items: [AuditLogItem] }
