import SwiftUI

struct UsersView: View {
    @Environment(InstanceStore.self) private var store
    @State private var users: [AdminUser] = []
    @State private var search = ""
    @State private var error: String?
    @State private var loading = false
    @State private var hasMore = false
    @State private var nextPage = 1
    @State private var loadID = UUID()

    var body: some View {
        NavigationStack {
            List {
                ForEach(users) { user in
                    NavigationLink { UserDetailView(user: user) } label: {
                        Label {
                            VStack(alignment: .leading) {
                                Text(user.username)
                                Text(user.role).font(.caption).foregroundStyle(.secondary)
                            }
                        } icon: { Image(systemName: user.isActive ? "person.fill" : "person.fill.xmark") }
                    }
                }
                if hasMore { Button(localized("Load More Users", "加载更多用户")) { Task { await load(reset: false) } }.disabled(loading) }
            }
            .overlay { if loading && users.isEmpty { ProgressView() } }
            .searchable(text: $search, prompt: localized("Search", "搜索"))
            .navigationTitle(localized("Users", "用户"))
            .task(id: search) {
                do { try await Task.sleep(for: .milliseconds(300)) } catch { return }
                await load(reset: true)
            }
            .refreshable { await load(reset: true) }
            .alert(localized("Could Not Load Users", "无法加载用户"), isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                Button(localized("OK", "好"), role: .cancel) {}
            } message: { Text(error ?? "") }
        }
    }

    private func load(reset: Bool) async {
        guard reset || !loading, let client = store.client() else { return }
        let id = UUID()
        loadID = id
        let query = search
        let page = reset ? 1 : nextPage
        loading = true
        if reset { users = []; hasMore = false }
        defer { if loadID == id { loading = false } }
        var path = URLComponents()
        path.path = "/api/admin/users"
        path.queryItems = [URLQueryItem(name: "q", value: query), URLQueryItem(name: "page", value: String(page)), URLQueryItem(name: "page_size", value: "50")]
        guard let requestPath = path.string else { return }
        do {
            let response: UserListResponse = try await client.get(requestPath)
            guard !Task.isCancelled, loadID == id, search == query else { return }
            let existing = Set(users.map(\.id))
            users += response.items.filter { !existing.contains($0.id) }
            nextPage = (response.page ?? page) + 1
            hasMore = (response.page ?? page) * (response.pageSize ?? 50) < (response.total ?? users.count)
        } catch {
            if !Task.isCancelled, loadID == id, search == query { self.error = error.localizedDescription }
        }
    }
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
