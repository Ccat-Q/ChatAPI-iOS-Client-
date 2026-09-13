import SwiftUI

struct MoreView: View {
    @Environment(InstanceStore.self) private var store
    @Environment(AppSettings.self) private var settings
    var body: some View {
        @Bindable var settings = settings
        NavigationStack {
            List {
                Section(localized("Administration", "管理")) { NavigationLink(localized("System Settings", "系统设置")) { SettingsCatalogView() }; NavigationLink(localized("Bark Notifications", "Bark 通知")) { BarkSettingsView() }; NavigationLink(localized("Audit Log", "审计日志")) { Text(localized("Audit records are available from the server audit log.", "审计记录可在服务器审计日志中查看。")).navigationTitle(localized("Audit Log", "审计日志")) } }
                Section(localized("Language", "语言")) { Picker(localized("App Language", "应用语言"), selection: $settings.language) { ForEach(AppLanguage.allCases) { Text($0.title).tag($0) } } }
                Section(localized("Instance", "实例")) { if let instance = store.selected { LabeledContent(localized("URL", "地址"), value: instance.baseURL.absoluteString); Button(localized("Remove Instance", "移除实例"), role: .destructive) { store.remove(instance) } } }
            }.navigationTitle(localized("More", "更多"))
        }
    }
}

struct SettingsCatalogView: View {
    @Environment(InstanceStore.self) private var store
    @State private var domains: [SettingsDomain] = []
    @State private var error: String?
    var body: some View { List(domains) { domain in NavigationLink(domain.title) { SettingsDomainView(domain: domain) } }.overlay { if domains.isEmpty && error == nil { ProgressView() } }.navigationTitle(localized("System Settings", "系统设置")).task { await load() }.refreshable { await load() }.alert(localized("Could Not Load Settings", "无法加载设置"), isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) { Button(localized("OK", "好"), role: .cancel) {} } message: { Text(error ?? "") } }
    private func load() async { guard let client = store.client() else { return }; do { let response: SettingsCatalogResponse = try await client.get("/api/admin/settings/catalog"); domains = response.catalog.groups } catch { self.error = error.localizedDescription } }
}

private struct SettingsDomainView: View {
    let domain: SettingsDomain
    @Environment(InstanceStore.self) private var store
    @State private var document: SettingsDocument?
    @State private var values: [String: JSONValue] = [:]
    @State private var error: String?
    @State private var confirm = false
    @State private var saving = false
    var isRisky: Bool { document?.fields.contains { $0.sensitive } ?? false }
    var body: some View { Form { if let document { ForEach(document.fields) { field in if field.editable { editor(for: field) } else { LabeledContent(field.title, value: values[field.key]?.displayValue ?? "") } }; Section { Button(saving ? localized("Saving…", "正在保存…") : localized("Save Changes", "保存更改")) { confirm = true }.disabled(saving) } } else { ProgressView() } }.navigationTitle(document?.title ?? domain.title).task { await load() }.confirmationDialog(localized("Apply settings?", "应用设置？"), isPresented: $confirm) { Button(localized("Apply", "应用"), role: isRisky ? .destructive : nil) { Task { await save() } } } message: { Text(isRisky ? localized("This setting can affect access, security, or stored data.", "此设置可能影响访问、安全性或已存储的数据。") : localized("The server validates all changes.", "服务器会验证全部更改。")) }.alert(localized("Could Not Save Settings", "无法保存设置"), isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) { Button(localized("OK", "好"), role: .cancel) {} } message: { Text(error ?? "") } }
    @ViewBuilder private func editor(for field: SettingsField) -> some View { if field.type == "boolean" { Toggle(field.title, isOn: Binding(get: { if case .bool(let value) = values[field.key] { return value }; return false }, set: { values[field.key] = .bool($0) })) } else if let options = field.options, !options.isEmpty { Picker(field.title, selection: Binding(get: { values[field.key]?.displayValue ?? options[0] }, set: { values[field.key] = .string($0) })) { ForEach(options, id: \.self) { Text($0).tag($0) } } } else { TextField(field.title, text: Binding(get: { values[field.key]?.displayValue ?? "" }, set: { values[field.key] = parsed($0, type: field.type) })).textInputAutocapitalization(.never).keyboardType(field.type == "integer" || field.type == "number" ? .decimalPad : .default) } }
    private func parsed(_ value: String, type: String) -> JSONValue { (type == "integer" || type == "number") && Double(value) != nil ? .number(Double(value)!) : .string(value) }
    private func load() async { guard let client = store.client() else { return }; do { let response: SettingsDocumentResponse = try await client.get("/api/admin/settings/\(domain.domain)"); document = response.document; values = response.document.values } catch { self.error = error.localizedDescription } }
    private func save() async { guard let client = store.client() else { return }; saving = true; defer { saving = false }; do { let _: SuccessResponse = try await client.patch("/api/admin/settings/\(domain.domain)", body: SettingsPatchInput(values: values)) } catch { self.error = error.localizedDescription } }
}

struct BarkSettingsView: View {
    @Environment(InstanceStore.self) private var store
    @State private var key = ""; @State private var enabled = false; @State private var health = true; @State private var pending = true; @State private var security = true; @State private var error: String?
    var body: some View { Form { Section(localized("Bark Target", "Bark 目标")) { SecureField(localized("Device Key", "设备密钥"), text: $key); Toggle(localized("Enable Bark", "启用 Bark"), isOn: $enabled); Text(localized("The key is encrypted by the compatibility server and is never returned to this app.", "密钥由兼容服务加密保存，服务端不会将其返回至本应用。")).font(.caption).foregroundStyle(.secondary) }; Section(localized("Events", "事件")) { Toggle(localized("Health and errors", "健康状态与错误"), isOn: $health); Toggle(localized("Pending human work", "待处理人工工作"), isOn: $pending); Toggle(localized("Security and admin activity", "安全与管理活动"), isOn: $security) }; Button(localized("Save Notification Policy", "保存通知策略")) { Task { await save() } }; Button(localized("Send Test Notification", "发送测试通知")) { Task { await test() } }.disabled(!enabled) }.navigationTitle(localized("Bark Notifications", "Bark 通知")).task { await load() }.alert(localized("Notification Setup Failed", "通知设置失败"), isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) { Button(localized("OK", "好"), role: .cancel) {} } message: { Text(error ?? "") } }
    private func load() async { guard let client = store.client() else { return }; do { let value: BarkSettings = try await client.get("/api/mobile/v1/notifications/bark"); enabled = value.enabled; health = value.health; pending = value.pendingWork; security = value.security } catch { self.error = error.localizedDescription } }
    private func save() async { guard let client = store.client() else { return }; do { let _: SuccessResponse = try await client.put("/api/mobile/v1/notifications/bark", body: BarkSettings(deviceKey: key.isEmpty ? nil : key, enabled: enabled, health: health, pendingWork: pending, security: security, configured: nil)) } catch { self.error = error.localizedDescription } }
    private func test() async { guard let client = store.client() else { return }; do { let _: SuccessResponse = try await client.post("/api/mobile/v1/notifications/bark/test", body: EmptyRequest()) } catch { self.error = error.localizedDescription } }
}
