import SwiftUI

struct ActivityView: View {
    @Environment(InstanceStore.self) private var store
    @State private var items: [ActivityItem] = []
    @State private var error: String?

    var body: some View {
        NavigationStack {
            List(items) { item in
                NavigationLink { ActivityDetailView(item: item) } label: { VStack(alignment: .leading) { Label(item.title, systemImage: item.kind == "security" ? "exclamationmark.shield.fill" : "bolt.fill"); if let detail = item.detail { Text(detail).font(.caption).foregroundStyle(.secondary) }; Text(item.timestamp, style: .relative).font(.caption2).foregroundStyle(.tertiary) } }
            }
            .overlay { if items.isEmpty { ContentUnavailableView(localized("No Activity", "暂无活动"), systemImage: "bolt.horizontal.circle") } }
            .navigationTitle(localized("Activity", "活动"))
            .task { await load() }.refreshable { await load() }
            .alert(localized("Could Not Load Activity", "无法加载活动记录"), isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) { Button(localized("OK", "好"), role: .cancel) {} } message: { Text(error ?? "") }
        }
    }
    private func load() async { guard let client = store.client() else { return }; do { let response: ActivityListResponse = try await client.get("/api/admin/requests"); items = response.items } catch { self.error = error.localizedDescription } }
}

private struct ActivityDetailView: View {
    let item: ActivityItem
    @Environment(InstanceStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var showConfirm = false
    @State private var error: String?
    var body: some View {
        Form {
            Section(localized("Details", "详情")) {
                LabeledContent(localized("Status", "状态"), value: item.kind)
                if let detail = item.detail { Text(detail) }
            }
            if item.kind == "pending" {
                Section {
                    Button(localized("Abort Request", "中止请求"), role: .destructive) { showConfirm = true }
                }
            }
        }
        .navigationTitle(item.title)
        .confirmationDialog(localized("Abort this request?", "中止此请求？"), isPresented: $showConfirm, titleVisibility: .visible) {
            Button(localized("Abort Request", "中止请求"), role: .destructive) { Task { await abort() } }
        } message: {
            Text(localized("This can interrupt an active conversation.", "这可能会中断正在进行的对话。"))
        }
        .alert(localized("Could Not Abort Request", "无法中止请求"), isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button(localized("OK", "好"), role: .cancel) {}
        } message: { Text(error ?? "") }
    }
    private func abort() async { guard let client = store.client(), !item.conversationID.isEmpty else { return }; do { let _: SuccessResponse = try await client.post("/api/admin/conversations/\(item.conversationID)/abort", body: EmptyRequest()); dismiss() } catch { self.error = error.localizedDescription } }
}
