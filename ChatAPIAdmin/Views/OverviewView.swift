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
                        MetricCard(title: localized("Health", "健康状态"), value: overview.ok ? localized("Healthy", "正常") : localized("Unavailable", "不可用"), icon: "heart.text.square")
                        MetricCard(title: localized("Mode", "运行模式"), value: overview.mode, icon: "server.rack")
                        MetricCard(title: localized("Database", "数据库"), value: overview.driver, icon: "cylinder")
                    }.padding()
                } else { ProgressView().padding(.top, 80) }
            }
            .navigationTitle(store.selected?.name ?? localized("Overview", "概览"))
            .task { await load() }
            .refreshable { await load() }
            .alert(localized("Could Not Load Overview", "无法加载概览"), isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) { Button(localized("OK", "好"), role: .cancel) {} } message: { Text(error ?? "") }
        }
    }
    private func load() async { guard let client = store.client() else { return }; do { overview = try await client.get("/api/health") } catch { self.error = error.localizedDescription } }
}

private struct MetricCard<Value: CustomStringConvertible>: View {
    let title: String; let value: Value; let icon: String
    var body: some View { VStack(alignment: .leading, spacing: 10) { Image(systemName: icon); Text("\(value)").font(.title.bold()); Text(title).foregroundStyle(.secondary) }.frame(maxWidth: .infinity, alignment: .leading).padding().glassEffect(in: .rect(cornerRadius: 20)) }
}
