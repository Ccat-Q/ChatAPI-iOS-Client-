import Foundation

struct Instance: Codable, Identifiable, Hashable {
    let id: UUID
    var name: String
    var baseURL: URL
    var allowsInsecureHTTP: Bool
    var capabilities: Capabilities?
}

struct Capabilities: Codable, Hashable {
    let apiVersion: String
    let features: Set<String>
    let settingsDomains: [SettingsDomain]
}

struct SettingsDomain: Codable, Identifiable, Hashable {
    let domain: String
    var id: String { domain }
    let title: String
    let fields: [SettingsField]
}

struct SettingsField: Codable, Identifiable, Hashable {
    let key: String
    let title: String
    let type: String
    let description: String
    let editable: Bool
    let sensitive: Bool
    let restartRequired: Bool
    let options: [String]?

    var id: String { key }

    enum CodingKeys: String, CodingKey {
        case key, title, type, description, editable, sensitive, restartRequired, options = "enum"
    }
}

struct Overview: Codable, Hashable {
    let ok: Bool
    let mode: String
    let driver: String
}

struct AdminUser: Codable, Identifiable, Hashable {
    let id: String
    let username: String
    let role: String
    let isActive: Bool
}

struct UserListResponse: Codable { let items: [AdminUser] }
struct SettingsCatalogResponse: Codable { let catalog: SettingsCatalog }
struct SettingsCatalog: Codable { let groups: [SettingsDomain] }

struct SettingsDocument: Codable {
    let domain: String
    let title: String
    let values: [String: JSONValue]
    let fields: [SettingsField]
}

struct SettingsDocumentResponse: Codable { let document: SettingsDocument }
struct SuccessResponse: Codable { let ok: Bool }
struct EmptyRequest: Encodable {}

struct SettingsPatchInput: Encodable { let values: [String: JSONValue] }

enum JSONValue: Codable, Hashable {
    case string(String), number(Double), bool(Bool), null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() { self = .null }
        else if let value = try? container.decode(Bool.self) { self = .bool(value) }
        else if let value = try? container.decode(Double.self) { self = .number(value) }
        else { self = .string(try container.decode(String.self)) }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value): try container.encode(value)
        case .number(let value): try container.encode(value)
        case .bool(let value): try container.encode(value)
        case .null: try container.encodeNil()
        }
    }

    var displayValue: String {
        switch self {
        case .string(let value): value
        case .number(let value): value.rounded() == value ? String(Int(value)) : String(value)
        case .bool(let value): value ? "true" : "false"
        case .null: ""
        }
    }
}

struct ActivityItem: Codable, Identifiable, Hashable {
    let requestID: String
    let status: String
    let model: String
    let requestPath: String
    let conversationID: String
    let createdAt: Date

    var id: String { requestID }
    var title: String { model.isEmpty ? requestPath : model }
    var kind: String { status }
    var timestamp: Date { createdAt }
    var detail: String? { requestPath.isEmpty ? nil : requestPath }

    enum CodingKeys: String, CodingKey {
        case requestID = "request_id", status, model, requestPath = "request_path", conversationID = "conversation_id", createdAt = "created_at"
    }
}

struct ActivityListResponse: Codable { let items: [ActivityItem] }

struct BarkTarget: Codable, Hashable {
    var key: String
    var health: Bool
    var pendingWork: Bool
    var security: Bool
    var includeFullDetail: Bool
}
