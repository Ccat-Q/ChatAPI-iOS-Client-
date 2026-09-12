import SwiftUI

struct UsersView: View {
    @Environment(InstanceStore.self) private var store
    @State private var users: [AdminUser] = []
    @State private var search = ""
    @State private var error: String?
    var filtered: [AdminUser] { search.isEmpty ? users : users.filter { $0.username.localizedCaseInsensitiveContains(search) } }
    var body: some View { NavigationStack { List(filtered) { user in NavigationLink { UserDetailView(user: user) } label: { Label { VStack(alignment: .leading) { Text(user.username); Text(user.role).font(.caption).foregroundStyle(.secondary) } } icon: { Image(systemName: user.disabled ? "person.fill.xmark" : "person.fill") } } }.searchable(text: $search).navigationTitle("Users").task { await load() }.refreshable { await load() }.alert("Could Not Load Users", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) { Button("OK", role: .cancel) {} } message: { Text(error ?? "") } } }
    private func load() async { guard let client = store.client() else { return }; do { users = try await client.get("/api/admin/users") } catch { self.error = error.localizedDescription } }
}

private struct UserDetailView: View {
    let user: AdminUser
    @State private var confirmDisable = false
    var body: some View { Form { Section("Account") { LabeledContent("Username", value: user.username); LabeledContent("Role", value: user.role); LabeledContent("Status", value: user.disabled ? "Disabled" : "Active") }; Section { Button(user.disabled ? "Enable User" : "Disable User", role: user.disabled ? nil : .destructive) { confirmDisable = true } } }.navigationTitle(user.username).confirmationDialog("Change user access?", isPresented: $confirmDisable) { Button(user.disabled ? "Enable" : "Disable", role: user.disabled ? nil : .destructive) {} } message: { Text("This immediately changes the user's ability to access the instance.") } }
}
