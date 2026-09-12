import SwiftUI

struct OverviewView: View {
    @Environment(InstanceStore.self) private var store
    @State private var overview: Overview?
    @State private var error: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                if let overview {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 14) {
                        MetricCard(title: "Active", value: overview.activeRequests, icon: "waveform.path.ecg")
                        MetricCard(title: "Pending", value: overview.pendingTurns, icon: "hourglass")
                        MetricCard(title: "Users", value: overview.totalUsers, icon: "person.2")
                        MetricCard(title: "Runtime", value: overview.runtimeStatus, icon: "server.rack")
                    }.padding()
                } else { ProgressView().padding(.top, 80) }
            }
            .navigationTitle(store.selected?.name ?? "Overview")
            .task { await load() }
            .refreshable { await load() }
            .alert("Could Not Load Overview", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) { Button("OK", role: .cancel) {} } message: { Text(error ?? "") }
        }
    }
    private func load() async { guard let client = store.client() else { return }; do { overview = try await client.get("/api/admin/settings/overview") } catch { self.error = error.localizedDescription } }
}

private struct MetricCard<Value: CustomStringConvertible>: View {
    let title: String; let value: Value; let icon: String
    var body: some View { VStack(alignment: .leading, spacing: 10) { Image(systemName: icon); Text("\(value)").font(.title.bold()); Text(title).foregroundStyle(.secondary) }.frame(maxWidth: .infinity, alignment: .leading).padding().glassEffect(in: .rect(cornerRadius: 20)) }
}
