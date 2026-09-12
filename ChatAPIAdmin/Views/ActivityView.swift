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
            .overlay { if items.isEmpty { ContentUnavailableView("No Activity", systemImage: "bolt.horizontal.circle") } }
            .navigationTitle("Activity")
            .task { await load() }.refreshable { await load() }
            .alert("Could Not Load Activity", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) { Button("OK", role: .cancel) {} } message: { Text(error ?? "") }
        }
    }
    private func load() async { guard let client = store.client() else { return }; do { items = try await client.get("/api/admin/requests") } catch { self.error = error.localizedDescription } }
}

private struct ActivityDetailView: View {
    let item: ActivityItem
    @State private var showConfirm = false
    var body: some View { Form { Section("Details") { LabeledContent("Kind", value: item.kind); if let detail = item.detail { Text(detail) } }; if item.kind == "pending" { Section { Button("Abort Request", role: .destructive) { showConfirm = true } } } }.navigationTitle(item.title).confirmationDialog("Abort this request?", isPresented: $showConfirm, titleVisibility: .visible) { Button("Abort Request", role: .destructive) {} } message: { Text("This can interrupt an active conversation.") } }
}
