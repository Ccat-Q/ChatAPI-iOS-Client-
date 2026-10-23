import SwiftUI

struct AIAssistSettingsView: View {
    @Environment(InstanceStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var configuration = AIAssistConfiguration()
    @State private var error: String?
    @State private var hasSavedConfiguration = false
    var onSaved: () -> Void = {}

    var body: some View {
        Form {
            Section {
                TextField("Base URL", text: $configuration.baseURL, prompt: Text("https://provider.example/v1"))
                    .textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
                Picker(localized("Protocol", "协议"), selection: $configuration.wireProtocol) {
                    ForEach(AIAssistProtocol.allCases) { Text($0.title).tag($0) }
                }
                TextField(localized("Model ID", "模型 ID"), text: $configuration.model).textInputAutocapitalization(.never).autocorrectionDisabled()
                SecureField(localized("API Key", "API 密钥"), text: $configuration.apiKey)
                    .textInputAutocapitalization(.never).autocorrectionDisabled().privacySensitive()
            } header: {
                Text(localized("Assistant Model", "辅助模型"))
            } footer: {
                Text(localized("Use a separate model service. The key stays in this device's Keychain for the current instance and account.", "请使用独立的模型服务。密钥按当前实例与账号保存在此设备的 Keychain。"))
            }
            Section(localized("Completion", "补全")) {
                Toggle(localized("Automatic Suggestions", "自动建议"), isOn: $configuration.automatic)
                Text(localized("When enabled, pausing your input sends the current draft, up to 12 recent text messages, and tool definitions to your model service. Suggestions are reviewed before sending.", "开启后，输入停顿时会将当前草稿、最近最多 12 条文本和工具定义发送至你配置的模型服务。建议经采纳后仍需手动发送。"))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section {
                Toggle(localized("Allow HTTP for development", "允许开发环境使用 HTTP"), isOn: $configuration.allowsHTTP)
                Button(localized("Save Configuration", "保存配置")) { save() }
                if hasSavedConfiguration {
                    Button(localized("Remove AI Configuration", "删除 AI 配置"), role: .destructive) {
                        guard let instance = store.selected, let user = store.sessionUser else { return }
                        AIAssistConfigurationStore.delete(instanceID: instance.id, userID: user.id)
                        onSaved(); dismiss()
                    }
                }
            }
        }
        .navigationTitle(localized("AI Completion", "AI 自动补全"))
        .task {
            guard let instance = store.selected, let user = store.sessionUser else { return }
            do {
                if let saved = try AIAssistConfigurationStore.load(instanceID: instance.id, userID: user.id) {
                    configuration = saved; hasSavedConfiguration = true
                }
            } catch { self.error = error.localizedDescription }
        }
        .alert(localized("AI Configuration Error", "AI 配置错误"), isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button(localized("OK", "好"), role: .cancel) {}
        } message: { Text(error ?? "") }
    }

    private func save() {
        guard let instance = store.selected, let user = store.sessionUser else { return }
        do {
            _ = try configuration.endpoint(currentServer: instance.baseURL)
            try AIAssistConfigurationStore.save(configuration, instanceID: instance.id, userID: user.id)
            onSaved(); dismiss()
        } catch { self.error = error.localizedDescription }
    }
}
