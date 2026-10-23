import SwiftUI

struct KeysAndModelsView: View {
    @Environment(InstanceStore.self) private var store
    @Environment(AppLock.self) private var lock
    @Environment(\.scenePhase) private var scenePhase
    @State private var appKeys: [APIKey] = []
    @State private var modelKeys: [ModelKey] = []
    @State private var models: [VirtualModel] = []
    @State private var sheet: KeySheet?
    @State private var secret: String?
    @State private var error: String?
    @State private var working = false
    @State private var loadID = UUID()
    enum KeySheet: Identifiable {
        case app, model, virtual
        var id: Int { switch self { case .app: 1; case .model: 2; case .virtual: 3 } }
    }

    var body: some View {
        List {
            Section(localized("Application API Keys", "应用 API 密钥")) {
                ForEach(appKeys) { key in
                    keyRow(key.name, subtitle: key.keyPrefix ?? "") {
                        await reveal(path: "/api/user/api-keys/\(key.id)/secret", reason: localized("Authenticate to reveal an API key", "验证身份以显示 API 密钥"))
                    }
                }.onDelete { offsets in
                    let ids = offsets.map { appKeys[$0].id }
                    Task { await delete(ids, path: "/api/user/api-keys", reason: localized("Authenticate to revoke API keys", "验证身份以撤销 API 密钥")) }
                }
                Button(localized("Create Application Key", "创建应用密钥")) { sheet = .app }
            }
            Section(localized("Model API Keys", "模型 API 密钥")) {
                ForEach(modelKeys) { key in
                    keyRow(key.name, subtitle: key.keyPrefix ?? "") {
                        await reveal(path: "/api/user/model-keys/\(key.id)/secret", reason: localized("Authenticate to reveal a model key", "验证身份以显示模型密钥"))
                    }
                }.onDelete { offsets in
                    let ids = offsets.map { modelKeys[$0].id }
                    Task { await delete(ids, path: "/api/user/model-keys", reason: localized("Authenticate to revoke model keys", "验证身份以撤销模型密钥")) }
                }
                Button(localized("Add Model Key", "添加模型密钥")) { sheet = .model }
            }
            Section(localized("Virtual Models", "虚拟模型")) {
                ForEach(models) { Text($0.name) }.onDelete { offsets in
                    let ids = offsets.map { models[$0].id }
                    Task { await delete(ids, path: "/api/user/virtual-models", reason: localized("Authenticate to delete virtual models", "验证身份以删除虚拟模型")) }
                }
                Button(localized("Create Virtual Model", "创建虚拟模型")) { sheet = .virtual }
            }
        }
        .disabled(working)
        .navigationTitle(localized("Keys & Models", "密钥与模型"))
        .task { await load() }.refreshable { await load() }
        .sheet(item: $sheet) { sheet in KeyCreateSheet(kind: sheet) { await load() } }
        .onChange(of: scenePhase) { _, phase in if phase != .active { secret = nil } }
        .alert(localized("Secret Key", "密钥明文"), isPresented: Binding(get: { secret != nil }, set: { if !$0 { secret = nil } })) {
            Button(localized("OK", "好"), role: .cancel) { secret = nil }
        } message: { Text(secret ?? "") }
        .alert(localized("Key Management Failed", "密钥管理失败"), isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button(localized("OK", "好"), role: .cancel) {}
        } message: { Text(error ?? "") }
    }

    private func keyRow(_ title: String, subtitle: String, reveal: @escaping () async -> Void) -> some View {
        HStack {
            VStack(alignment: .leading) { Text(title); Text(subtitle).font(.caption).foregroundStyle(.secondary) }
            Spacer()
            Button(localized("Reveal", "显示")) { Task { await reveal() } }.buttonStyle(.borderless)
        }
    }

    private func load() async {
        guard let access = store.authenticatedAccess() else { return }
        let id = UUID()
        loadID = id
        do {
            async let apps: APIKeyListResponse = access.client.get("/api/user/api-keys")
            async let keys: ModelKeyListResponse = access.client.get("/api/user/model-keys")
            async let virtual: VirtualModelListResponse = access.client.get("/api/user/virtual-models")
            let values = try await (apps, keys, virtual)
            guard store.isCurrent(access), loadID == id else { return }
            appKeys = values.0.items; modelKeys = values.1.items; models = values.2.items
        } catch { if store.isCurrent(access), loadID == id { self.error = error.localizedDescription } }
    }

    private func reveal(path: String, reason: String) async {
        guard !working else { return }
        working = true
        defer { working = false }
        guard let access = await store.authorizeSession(using: { await lock.authenticate(reason: reason) }) else { return }
        do {
            let result: APIKeyRevealResponse = try await access.client.get(path)
            guard store.isCurrent(access) else { return }
            secret = result.apiKey
        } catch { if store.isCurrent(access) { self.error = error.localizedDescription } }
    }

    private func delete(_ ids: [String], path: String, reason: String) async {
        guard !working else { return }
        working = true
        defer { working = false }
        guard let access = await store.authorizeSession(using: { await lock.authenticate(reason: reason) }) else { return }
        for id in ids {
            guard store.isCurrent(access) else { return }
            do { let _: SuccessResponse = try await access.client.delete("\(path)/\(id)") }
            catch { if store.isCurrent(access) { self.error = error.localizedDescription }; return }
        }
        if store.isCurrent(access) { await load() }
    }
}

private struct KeyCreateSheet: View {
    let kind: KeysAndModelsView.KeySheet
    let completed: () async -> Void
    @Environment(InstanceStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var rawKey = ""
    @State private var saving = false
    @State private var secret: String?
    @State private var error: String?
    var body: some View {
        NavigationStack {
            Form {
                TextField(localized("Name", "名称"), text: $name)
                if kind == .model { SecureField(localized("Model key value", "模型密钥值"), text: $rawKey) }
                if kind == .app { Text(localized("Application keys are created with conversation read/write scopes.", "应用密钥将创建为会话读写权限。")).font(.caption) }
            }.disabled(saving)
            .navigationTitle(title)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(localized("Create", "创建")) { Task { await create() } }
                        .disabled(saving || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || (kind == .model && rawKey.isEmpty))
                }
            }
            .alert(localized("New Secret", "新密钥"), isPresented: Binding(get: { secret != nil }, set: { if !$0 { secret = nil; dismiss() } })) {
                Button(localized("Done", "完成"), role: .cancel) { secret = nil; dismiss() }
            } message: { Text(secret ?? "") }
            .alert(localized("Creation Failed", "创建失败"), isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                Button(localized("OK", "好"), role: .cancel) {}
            } message: { Text(error ?? "") }
        }
    }
    private var title: String {
        switch kind {
        case .app: localized("New Application Key", "新应用密钥")
        case .model: localized("New Model Key", "新模型密钥")
        case .virtual: localized("New Virtual Model", "新虚拟模型")
        }
    }
    private func create() async {
        guard !saving, let access = store.authenticatedAccess() else { return }
        saving = true
        defer { saving = false }
        do {
            let createdSecret: String?
            switch kind {
            case .app:
                let result: APIKeyCreateResponse = try await access.client.post("/api/user/api-keys", body: CreateAppKeyInput.operatorKey(name: name))
                createdSecret = result.apiKey.apiKey
            case .model:
                let result: ModelKeyCreateResponse = try await access.client.post("/api/user/model-keys", body: CreateModelKeyInput(name: name, key: rawKey))
                createdSecret = result.modelKey.apiKey
                rawKey = ""
            case .virtual:
                let _: VirtualModelCreateResponse = try await access.client.post("/api/user/virtual-models", body: CreateVirtualModelInput(name: name))
                createdSecret = nil
            }
            guard store.isCurrent(access) else { return }
            await completed()
            guard store.isCurrent(access) else { return }
            if kind == .virtual { dismiss() }
            else { secret = createdSecret }
        } catch { if store.isCurrent(access) { self.error = error.localizedDescription } }
    }
}
