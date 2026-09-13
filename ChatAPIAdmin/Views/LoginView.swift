import SwiftUI

struct LoginView: View {
    let instance: Instance
    @Environment(InstanceStore.self) private var store
    @State private var username = ""
    @State private var password = ""
    @State private var isLoading = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Section(localized("Instance", "实例")) { LabeledContent(instance.name, value: instance.baseURL.host() ?? instance.baseURL.absoluteString) }
                Section(localized("Administrator Login", "管理员登录")) {
                    TextField(localized("Username", "用户名"), text: $username).textInputAutocapitalization(.never).autocorrectionDisabled()
                    SecureField(localized("Password", "密码"), text: $password)
                }
                Section { Button { Task { await login() } } label: { if isLoading { ProgressView().frame(maxWidth: .infinity) } else { Text(localized("Sign In", "登录")).frame(maxWidth: .infinity) } }.disabled(isLoading || username.isEmpty || password.isEmpty) }
            }
            .navigationTitle(localized("Sign In", "登录"))
            .alert(localized("Sign In Failed", "登录失败"), isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) { Button(localized("OK", "好"), role: .cancel) {} } message: { Text(error ?? "") }
        }
    }

    private func login() async {
        guard let client = store.client() else { return }
        isLoading = true
        defer { isLoading = false }
        do { try await client.login(username: username, password: password); try store.markSession(for: instance) }
        catch { self.error = error.localizedDescription }
    }
}
