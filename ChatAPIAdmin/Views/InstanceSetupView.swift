import SwiftUI

struct InstanceSetupView: View {
    @Environment(InstanceStore.self) private var store
    @State private var name = ""
    @State private var address = "https://"
    @State private var allowsHTTP = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Section(localized("Add Instance", "添加实例")) {
                    TextField(localized("Name", "名称"), text: $name)
                    TextField(localized("HTTPS URL", "HTTPS 地址"), text: $address).textInputAutocapitalization(.never).keyboardType(.URL)
                    Toggle(localized("Allow HTTP for development", "允许开发环境使用 HTTP"), isOn: $allowsHTTP)
                }
                Section { Button(localized("Save Instance", "保存实例")) { save() }.frame(maxWidth: .infinity) }
                footer: { Text(localized("QR import can populate this form with a non-secret instance URL.", "二维码导入可填入不含密钥的实例地址。")) }
            }
            .navigationTitle(localized("ChatAPI Admin", "ChatAPI 管理"))
            .alert(localized("Cannot Add Instance", "无法添加实例"), isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) { Button(localized("OK", "好"), role: .cancel) {} } message: { Text(error ?? "") }
        }
    }

    private func save() {
        guard let url = URL(string: address), !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { error = localized("Enter an instance name and valid URL.", "请输入实例名称和有效地址。"); return }
        do { try store.add(name: name, url: url, allowsInsecureHTTP: allowsHTTP) } catch { self.error = error.localizedDescription }
    }
}
