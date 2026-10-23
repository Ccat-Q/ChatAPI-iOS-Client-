import SwiftUI

struct MoreView: View {
    @Environment(InstanceStore.self) private var store
    @Environment(AppSettings.self) private var settings
    @State private var capabilities: Capabilities?
    @State private var addingInstance = false
    @State private var error: String?
    var body: some View {
        @Bindable var settings = settings
        NavigationStack {
            List {
                Section(localized("Management", "管理")) {
                    if store.sessionUser?.isAdministrator == true {
                        NavigationLink(localized("System Settings", "系统设置")) { SettingsCatalogView() }
                        NavigationLink(localized("Audit Log", "审计日志")) { AuditLogView() }
                    }
                    NavigationLink(localized("Keys & Models", "密钥与模型")) { KeysAndModelsView() }
                    NavigationLink(localized("AI Completion", "AI 自动补全")) { AIAssistSettingsView() }
                    NavigationLink(localized("Automation Rules", "自动化规则")) { AutomationRulesView() }
                    if capabilities?.features.contains("bark") == true {
                        NavigationLink(localized("Bark Notifications", "Bark 通知")) { BarkSettingsView() }
                    }
                }
                Section(localized("Language", "语言")) {
                    Picker(localized("App Language", "应用语言"), selection: $settings.language) {
                        ForEach(AppLanguage.allCases) { Text($0.title).tag($0) }
                    }
                }
                Section(localized("Instance", "实例")) {
                    Picker(localized("Current Instance", "当前实例"), selection: Binding(get: { store.selectedID }, set: { store.select($0) })) {
                        ForEach(store.instances) { Text($0.name).tag(Optional($0.id)) }
                    }
                    Button(localized("Add Instance", "添加实例")) { addingInstance = true }
                    if let instance = store.selected {
                        LabeledContent(localized("URL", "地址"), value: instance.baseURL.absoluteString)
                        Button(localized("Sign Out", "退出登录")) { store.clearSession(for: instance) }
                        Button(localized("Remove Instance", "移除实例"), role: .destructive) {
                            do { try store.remove(instance) } catch { self.error = error.localizedDescription }
                        }
                    }
                }
            }
            .navigationTitle(localized("More", "更多"))
            .sheet(isPresented: $addingInstance) { InstanceSetupView() }
            .task {
                guard let client = store.client() else { return }
                // The extension is optional; upstream-only servers remain usable.
                capabilities = try? await client.get("/api/mobile/v1/capabilities")
            }
            .alert(localized("Instance Update Failed", "实例更新失败"), isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                Button(localized("OK", "好"), role: .cancel) {}
            } message: { Text(error ?? "") }
        }
    }
}

struct SettingsCatalogView: View {
    @Environment(InstanceStore.self) private var store
    @State private var domains: [SettingsDomain] = []
    @State private var loading = false
    @State private var error: String?
    var body: some View {
        List(domains) { domain in NavigationLink(domain.title) { SettingsDomainView(domain: domain) } }
            .overlay { if loading { ProgressView() } }
            .navigationTitle(localized("System Settings", "系统设置"))
            .task { await load() }.refreshable { await load() }
            .alert(localized("Could Not Load Settings", "无法加载设置"), isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                Button(localized("OK", "好"), role: .cancel) {}
            } message: { Text(error ?? "") }
    }
    private func load() async {
        guard let client = store.client() else { return }
        loading = true
        defer { loading = false }
        do { let response: SettingsCatalogResponse = try await client.get("/api/admin/settings/catalog"); domains = response.catalog.groups }
        catch { self.error = error.localizedDescription }
    }
}

private struct SettingsDomainView: View {
    let domain: SettingsDomain
    @Environment(InstanceStore.self) private var store
    @Environment(AppLock.self) private var lock
    @State private var document: SettingsDocument?
    @State private var values: [String: JSONValue] = [:]
    @State private var textEdits: [String: String] = [:]
    @State private var pendingPatch: [String: JSONValue] = [:]
    @State private var error: String?
    @State private var notice: String?
    @State private var confirm = false
    @State private var saving = false
    @State private var loading = false

    private var isRisky: Bool { document?.fields.contains { pendingPatch[$0.key] != nil && $0.sensitive } ?? false }
    private var hasEdits: Bool { !textEdits.isEmpty || values != document?.values }

    var body: some View {
        Form {
            if let document {
                ForEach(document.fields) { field in
                    if field.supportsEditing { editor(for: field) }
                    else { LabeledContent(field.title, value: field.sensitive ? "••••••" : (values[field.key]?.displayValue ?? "")) }
                }
                Button(saving ? localized("Saving…", "正在保存…") : localized("Save Changes", "保存更改")) { preparePatch() }
                    .disabled(saving || !hasEdits)
            } else if loading { ProgressView() }
            else { Button(localized("Retry Loading", "重新加载")) { Task { await load() } } }
        }
        .disabled(saving)
        .navigationTitle(document?.title ?? domain.title)
        .task { await load() }
        .confirmationDialog(localized("Apply settings?", "应用设置？"), isPresented: $confirm) {
            Button(localized("Apply", "应用"), role: isRisky ? .destructive : nil) { Task { await save() } }
        } message: {
            Text(isRisky ? localized("This change affects sensitive server settings.", "此更改涉及敏感服务器设置。") : localized("The server validates all changes.", "服务器会验证全部更改。"))
        }
        .alert(localized("Settings Error", "设置错误"), isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button(localized("OK", "好"), role: .cancel) {}
        } message: { Text(error ?? "") }
        .alert(localized("Settings Saved", "设置已保存"), isPresented: Binding(get: { notice != nil }, set: { if !$0 { notice = nil } })) {
            Button(localized("OK", "好"), role: .cancel) {}
        } message: { Text(notice ?? "") }
    }

    @ViewBuilder private func editor(for field: SettingsField) -> some View {
        if field.type == "boolean" {
            Toggle(field.title, isOn: Binding(get: { if case .bool(let value) = values[field.key] { return value }; return false }, set: { values[field.key] = .bool($0) }))
        } else if let options = field.options, !options.isEmpty {
            Picker(field.title, selection: textBinding(for: field)) { ForEach(options, id: \.self) { Text($0).tag($0) } }
        } else if field.sensitive {
            SecureField(field.title, text: textBinding(for: field)).textInputAutocapitalization(.never).autocorrectionDisabled()
        } else {
            TextField(field.title, text: textBinding(for: field))
                .textInputAutocapitalization(.never).autocorrectionDisabled()
                .keyboardType(field.type == "integer" || field.type == "number" ? .numbersAndPunctuation : .default)
        }
    }

    private func textBinding(for field: SettingsField) -> Binding<String> {
        Binding(get: { textEdits[field.key] ?? values[field.key]?.displayValue ?? "" }, set: { text in
            if text == document?.values[field.key]?.displayValue { textEdits.removeValue(forKey: field.key) }
            else { textEdits[field.key] = text }
        })
    }

    private func preparePatch() {
        guard let document else { return }
        do {
            pendingPatch = try document.patch(values: values, textEdits: textEdits)
            if !pendingPatch.isEmpty { confirm = true }
        } catch { self.error = error.localizedDescription }
    }

    private func load() async {
        guard let client = store.client() else { return }
        loading = true
        defer { loading = false }
        do {
            let response: SettingsDocumentResponse = try await client.get("/api/admin/settings/\(domain.domain)")
            document = response.document; values = response.document.values; textEdits = [:]
        } catch { self.error = error.localizedDescription }
    }

    private func save() async {
        guard !saving, !pendingPatch.isEmpty, let client = store.client() else { return }
        saving = true
        defer { saving = false }
        if isRisky {
            guard await lock.authenticate(reason: localized("Authenticate to apply sensitive server settings", "验证身份以应用敏感服务器设置")) else { return }
        }
        do {
            let response: SettingsPatchResponse = try await client.patch("/api/admin/settings/\(domain.domain)", body: SettingsPatchInput(values: pendingPatch))
            document = response.result.document; values = response.result.document.values
            textEdits = [:]; pendingPatch = [:]
            var messages = response.result.warnings ?? []
            if let restart = response.result.restartRequired, !restart.isEmpty {
                messages.append(localized("Restart required for: ", "以下设置需要重启：") + restart.joined(separator: ", "))
            }
            notice = messages.isEmpty ? localized("Changes applied.", "更改已应用。") : messages.joined(separator: "\n")
        } catch { self.error = error.localizedDescription }
    }
}

struct BarkSettingsView: View {
    @Environment(InstanceStore.self) private var store
    @State private var key = ""
    @State private var enabled = false
    @State private var health = true
    @State private var pending = true
    @State private var security = true
    @State private var configured = false
    @State private var ready = false
    @State private var busy = false
    @State private var error: String?
    @State private var notice: String?
    var body: some View {
        Form {
            Section(localized("Bark Target", "Bark 目标")) {
                SecureField(localized("Device Key", "设备密钥"), text: $key).textInputAutocapitalization(.never).autocorrectionDisabled()
                Toggle(localized("Enable Bark", "启用 Bark"), isOn: $enabled)
                Text(localized("The key is encrypted by the compatibility server and is never returned to this app.", "密钥由兼容服务加密保存，服务端不会将其返回至本应用。")).font(.caption).foregroundStyle(.secondary)
            }
            Section(localized("Events", "事件")) {
                Toggle(localized("Health and errors", "健康状态与错误"), isOn: $health)
                Toggle(localized("Pending human work", "待处理人工工作"), isOn: $pending)
                Toggle(localized("Security and admin activity", "安全与管理活动"), isOn: $security)
            }
            Button(localized("Save Notification Policy", "保存通知策略")) { Task { await save() } }.disabled(!ready || busy)
            Button(localized("Send Test Notification", "发送测试通知")) { Task { await test() } }.disabled(!ready || !configured || busy)
            if !ready { Button(localized("Retry Loading", "重新加载")) { Task { await load() } } }
        }
        .navigationTitle(localized("Bark Notifications", "Bark 通知"))
        .task { await load() }
        .alert(localized("Notification Setup Failed", "通知设置失败"), isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button(localized("OK", "好"), role: .cancel) {}
        } message: { Text(error ?? "") }
        .alert(localized("Bark", "Bark"), isPresented: Binding(get: { notice != nil }, set: { if !$0 { notice = nil } })) {
            Button(localized("OK", "好"), role: .cancel) {}
        } message: { Text(notice ?? "") }
    }
    private func load() async {
        guard let client = store.client() else { return }
        do {
            let value: BarkSettings = try await client.get("/api/mobile/v1/notifications/bark")
            enabled = value.enabled; health = value.health; pending = value.pendingWork; security = value.security
            configured = value.configured ?? false; ready = true
        } catch { self.error = error.localizedDescription }
    }
    private func save() async {
        guard !busy, let client = store.client() else { return }
        busy = true
        defer { busy = false }
        do {
            let _: SuccessResponse = try await client.put("/api/mobile/v1/notifications/bark", body: BarkSettings(deviceKey: key.isEmpty ? nil : key, enabled: enabled, health: health, pendingWork: pending, security: security, configured: nil))
            key = ""
            await load()
            notice = localized("Notification policy saved.", "通知策略已保存。")
        } catch { self.error = error.localizedDescription }
    }
    private func test() async {
        guard !busy, let client = store.client() else { return }
        busy = true
        defer { busy = false }
        do { let _: SuccessResponse = try await client.post("/api/mobile/v1/notifications/bark/test", body: EmptyRequest()); notice = localized("Test notification sent.", "测试通知已发送。") }
        catch { self.error = error.localizedDescription }
    }
}

private struct AuditLogView: View {
    @Environment(InstanceStore.self) private var store
    @State private var items: [AuditLogItem] = []
    @State private var error: String?
    var body: some View {
        List(items) { item in
            VStack(alignment: .leading, spacing: 4) {
                Text(item.action).font(.headline)
                Text("\(item.eventType) · \(item.outcome)").foregroundStyle(.secondary)
                Text(item.createdAt, style: .date).font(.caption)
            }
        }
        .navigationTitle(localized("Audit Log", "审计日志"))
        .task { await load() }.refreshable { await load() }
        .alert(localized("Could Not Load Audit Log", "无法加载审计日志"), isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button(localized("OK", "好"), role: .cancel) {}
        } message: { Text(error ?? "") }
    }
    private func load() async {
        guard let client = store.client() else { return }
        do { let response: AuditLogResponse = try await client.get("/api/admin/audit/logs?limit=50"); items = response.items }
        catch { self.error = error.localizedDescription }
    }
}
