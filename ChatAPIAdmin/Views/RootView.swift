import SwiftUI
import UIKit

struct RootView: View {
    @Environment(InstanceStore.self) private var store
    @Environment(AppLock.self) private var lock
    @Environment(\.scenePhase) private var scenePhase

    private struct SessionCheck: Equatable {
        let instanceID: UUID?
        let unlocked: Bool
        let active: Bool
    }

    var body: some View {
        Group {
            if lock.phase == .locked { LockView() }
            else if store.selected == nil { InstanceSetupView() }
            else if let instance = store.selected, store.hasStoredSession(for: instance), !store.hasSession(for: instance) {
                VStack(spacing: 16) {
                    if store.isCheckingSession { ProgressView(localized("Validating session…", "正在验证会话…")) }
                    else {
                        Text(store.sessionError ?? localized("Validate your saved session to continue.", "验证已保存的会话后继续。"))
                        Button(localized("Retry", "重试")) { Task { await store.refreshSession() } }
                        Button(localized("Sign In Again", "重新登录")) { store.clearSession(for: instance) }
                        Button(localized("Remove Instance", "移除实例"), role: .destructive) { do { try store.remove(instance) } catch { store.storageError = error.localizedDescription } }
                    }
                }.padding()
            }
            else if let instance = store.selected, !store.hasSession(for: instance) { LoginView(instance: instance).id(instance.id) }
            else { AdminTabView().id(store.selectedID) }
        }
        .tint(.cyan)
        .task(id: SessionCheck(instanceID: store.selectedID, unlocked: lock.phase == .unlocked, active: scenePhase == .active)) {
            if lock.phase == .unlocked, scenePhase == .active { await store.refreshSession() }
        }
        .alert(localized("Storage Error", "存储错误"), isPresented: Binding(get: { store.storageError != nil }, set: { if !$0 { store.storageError = nil } })) {
            Button(localized("OK", "好"), role: .cancel) {}
        } message: { Text(store.storageError ?? "") }
    }
}

struct LockView: View {
    @Environment(AppLock.self) private var lock
    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(spacing: 24) {
                    Image(systemName: lock.method.symbol)
                        .font(.system(size: 64, weight: .light))
                        .foregroundStyle(.cyan)
                        .accessibilityHidden(true)
                    VStack(spacing: 10) {
                        Text(localized("Unlock Workspace", "解锁工作台")).font(.largeTitle.bold())
                        Text(localized("Your conversations and server settings are protected on this device.", "此设备上的会话与服务器设置已受保护。"))
                            .foregroundStyle(.secondary)
                    }
                    if lock.isAuthenticating {
                        ProgressView(localized("Waiting for device authentication…", "正在等待设备验证…"))
                    } else {
                        Button { lock.unlock() } label: {
                            Label(localized("Unlock with ", "使用 ") + lock.method.title + localized("", " 解锁"), systemImage: lock.method.symbol)
                                .frame(maxWidth: .infinity).padding(.vertical, 4)
                        }
                        .buttonStyle(.glassProminent).controlSize(.large)
                    }
                    if let message = lock.message {
                        Text(message).font(.callout).foregroundStyle(.secondary)
                    }
                }
                .multilineTextAlignment(.center)
                .frame(maxWidth: 380)
                .padding(32)
                .frame(maxWidth: .infinity, minHeight: geometry.size.height)
            }
            .background(Color(.systemGroupedBackground).ignoresSafeArea())
        }
        .onChange(of: lock.message) { _, message in
            if let message { UIAccessibility.post(notification: .announcement, argument: message) }
        }
    }
}

struct AdminTabView: View {
    @Environment(InstanceStore.self) private var store
    @State private var workspace: WorkspaceConnection?
    var body: some View {
        TabView {
            Group {
                if let workspace { OverviewView(workspace: workspace) }
                else { ProgressView() }
            }.tabItem { Label(localized("Workspace", "工作台"), systemImage: "bubble.left.and.bubble.right.fill") }
            if store.sessionUser?.isAdministrator == true { ActivityView().tabItem { Label(localized("Requests", "请求"), systemImage: "arrow.trianglehead.2.clockwise") } }
            if store.sessionUser?.isAdministrator == true { UsersView().tabItem { Label(localized("Users", "用户"), systemImage: "person.2.fill") } }
            MoreView().tabItem { Label(localized("More", "更多"), systemImage: "ellipsis.circle.fill") }
        }
        .task {
            if let workspace { workspace.connect(); return }
            guard let client = store.client(), let instance = store.selected, let user = store.sessionUser else { return }
            let connection = WorkspaceConnection(client: client, instance: instance, userID: user.id)
            workspace = connection
            connection.connect()
        }
        .onDisappear { workspace?.disconnect() }
    }
}
