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
                Section("Instance") { LabeledContent(instance.name, value: instance.baseURL.host() ?? instance.baseURL.absoluteString) }
                Section("Administrator Login") {
                    TextField("Username", text: $username).textInputAutocapitalization(.never).autocorrectionDisabled()
                    SecureField("Password", text: $password)
                }
                Section { Button { Task { await login() } } label: { if isLoading { ProgressView().frame(maxWidth: .infinity) } else { Text("Sign In").frame(maxWidth: .infinity) } }.disabled(isLoading || username.isEmpty || password.isEmpty) }
            }
            .navigationTitle("Sign In")
            .alert("Sign In Failed", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) { Button("OK", role: .cancel) {} } message: { Text(error ?? "") }
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
