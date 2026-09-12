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
    let id: String
    let title: String
    let fields: [SettingsField]
}

struct SettingsField: Codable, Identifiable, Hashable {
    let id: String
    let title: String
    let kind: String
    let required: Bool
    let sensitive: Bool
    let options: [String]?
}

struct Overview: Codable, Hashable {
    let activeRequests: Int
    let pendingTurns: Int
    let totalUsers: Int
    let runtimeStatus: String
}

struct AdminUser: Codable, Identifiable, Hashable {
    let id: String
    let username: String
    let role: String
    let disabled: Bool
}

struct ActivityItem: Codable, Identifiable, Hashable {
    let id: String
    let kind: String
    let title: String
    let timestamp: Date
    let detail: String?
}

struct BarkTarget: Codable, Hashable {
    var key: String
    var health: Bool
    var pendingWork: Bool
    var security: Bool
    var includeFullDetail: Bool
}
