import SwiftUI

struct MoreView: View {
    @Environment(InstanceStore.self) private var store
    @Environment(AppSettings.self) private var settings
    var body: some View {
        @Bindable var settings = settings
        NavigationStack {
            List {
                Section("Administration") { NavigationLink("System Settings") { SettingsCatalogView() }; NavigationLink("Bark Notifications") { BarkSettingsView() }; NavigationLink("Audit Log") { Text("Audit records load from /api/admin/audit/logs.").navigationTitle("Audit Log") } }
                Section("Language") { Picker("App Language", selection: $settings.language) { ForEach(AppLanguage.allCases) { Text($0.title).tag($0) } } }
                Section("Instance") { if let instance = store.selected { LabeledContent("URL", value: instance.baseURL.absoluteString); Button("Remove Instance", role: .destructive) { store.remove(instance) } } }
            }.navigationTitle("More")
        }
    }
}

struct SettingsCatalogView: View {
    @Environment(InstanceStore.self) private var store
    @State private var domains: [SettingsDomain] = []
    var body: some View { List(domains) { domain in NavigationLink(domain.title) { SettingsDomainView(domain: domain) } }.navigationTitle("System Settings").task { guard let client = store.client() else { return }; let response: SettingsCatalogResponse? = try? await client.get("/api/admin/settings/catalog"); domains = response?.catalog.groups ?? [] } }
}

private struct SettingsDomainView: View {
    let domain: SettingsDomain
    @State private var values: [String: String] = [:]
    @State private var confirm = false
    var isRisky: Bool { domain.fields.contains { $0.sensitive || $0.kind == "destructive" } }
    var body: some View { Form { ForEach(domain.fields) { field in TextField(field.title, text: Binding(get: { values[field.id, default: ""] }, set: { values[field.id] = $0 })).textInputAutocapitalization(.never) }; Section { Button("Save Changes") { confirm = true } } }.navigationTitle(domain.title).confirmationDialog("Apply settings?", isPresented: $confirm) { Button("Apply", role: isRisky ? .destructive : nil) {} } message: { Text(isRisky ? "This setting can affect access, security, or stored data." : "The server validates all changes.") } }
}

struct BarkSettingsView: View {
    @State private var key = ""; @State private var health = true; @State private var pending = true; @State private var security = true; @State private var details = true
    var body: some View { Form { Section("Bark Target") { SecureField("Device Key", text: $key); Text("The key is encrypted by the compatibility server and never shown again.").font(.caption).foregroundStyle(.secondary) }; Section("Events") { Toggle("Health and errors", isOn: $health); Toggle("Pending human work", isOn: $pending); Toggle("Security and admin activity", isOn: $security) }; Section("Privacy") { Toggle("Include full details", isOn: $details); Text("Details can appear on the lock screen and in Bark history.").font(.caption).foregroundStyle(.orange) }; Button("Save Notification Policy") {} }.navigationTitle("Bark Notifications") }
}
