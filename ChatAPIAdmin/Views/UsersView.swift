import SwiftUI

struct UsersView: View {
    @Environment(InstanceStore.self) private var store
    @State private var users: [AdminUser] = []
    @State private var search = ""
    @State private var error: String?
    var filtered: [AdminUser] { search.isEmpty ? users : users.filter { $0.username.localizedCaseInsensitiveContains(search) } }
    var body: some View { NavigationStack { List(filtered) { user in NavigationLink { UserDetailView(user: user) } label: { Label { VStack(alignment: .leading) { Text(user.username); Text(user.role).font(.caption).foregroundStyle(.secondary) } } icon: { Image(systemName: user.isActive ? "person.fill" : "person.fill.xmark") } } }.searchable(text: $search, prompt: localized("Search", "搜索")).navigationTitle(localized("Users", "用户")).task { await load() }.refreshable { await load() }.alert(localized("Could Not Load Users", "无法加载用户"), isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) { Button(localized("OK", "好"), role: .cancel) {} } message: { Text(error ?? "") } } }
    private func load() async { guard let client = store.client() else { return }; do { let response: UserListResponse = try await client.get("/api/admin/users"); users = response.items } catch { self.error = error.localizedDescription } }
}

private struct UserDetailView: View {
    let user: AdminUser
    @Environment(InstanceStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var confirmDisable = false
    @State private var error: String?
    var body: some View { Form { Section(localized("Account", "账户")) { LabeledContent(localized("Username", "用户名"), value: user.username); LabeledContent(localized("Role", "角色"), value: user.role); LabeledContent(localized("Status", "状态"), value: user.isActive ? localized("Active", "已启用") : localized("Disabled", "已禁用")) }; Section { Button(user.isActive ? localized("Disable User", "禁用用户") : localized("Enable User", "启用用户"), role: user.isActive ? .destructive : nil) { confirmDisable = true } } }.navigationTitle(user.username).confirmationDialog(localized("Change user access?", "更改用户访问权限？"), isPresented: $confirmDisable) { Button(user.isActive ? localized("Disable", "禁用") : localized("Enable", "启用"), role: user.isActive ? .destructive : nil) { Task { await setUserState() } } } message: { Text(localized("This immediately changes the user's ability to access the instance.", "这会立即更改用户访问实例的权限。")) }.alert(localized("Could Not Update User", "无法更新用户"), isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) { Button(localized("OK", "好"), role: .cancel) {} } message: { Text(error ?? "") } }
    private func setUserState() async { guard let client = store.client() else { return }; do { let _: SuccessResponse = try await client.post("/api/admin/users/\(user.id)/\(user.isActive ? "disable" : "enable")", body: EmptyRequest()); dismiss() } catch { self.error = error.localizedDescription } }
}
