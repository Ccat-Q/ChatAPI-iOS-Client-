import SwiftUI

struct RootView: View {
    @Environment(InstanceStore.self) private var store
    @Environment(AppLock.self) private var lock

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
            else if let instance = store.selected, !store.hasSession(for: instance) { LoginView(instance: instance) }
            else { AdminTabView().id(store.selectedID) }
        }
        .tint(.cyan)
        .task(id: lock.phase == .unlocked ? store.selectedID : nil) {
            if lock.phase == .unlocked { await store.refreshSession() }
        }
        .alert(localized("Storage Error", "存储错误"), isPresented: Binding(get: { store.storageError != nil }, set: { if !$0 { store.storageError = nil } })) {
            Button(localized("OK", "好"), role: .cancel) {}
        } message: { Text(store.storageError ?? "") }
    }
}

private struct LockView: View {
    @Environment(AppLock.self) private var lock
    var body: some View {
        ContentUnavailableView(localized("ChatAPI Admin Locked", "ChatAPI 管理已锁定"), systemImage: "lock.fill", description: Text(localized("Authenticate to manage your instances.", "验证身份以管理实例。")))
            .glassEffect()
            .onTapGesture { lock.unlock() }
    }
}

struct AdminTabView: View {
    @Environment(InstanceStore.self) private var store
    var body: some View {
        TabView {
            OverviewView().tabItem { Label(localized("Workspace", "工作台"), systemImage: "bubble.left.and.bubble.right.fill") }
            if store.sessionUser?.isAdministrator == true { ActivityView().tabItem { Label(localized("Requests", "请求"), systemImage: "arrow.trianglehead.2.clockwise") } }
            if store.sessionUser?.isAdministrator == true { UsersView().tabItem { Label(localized("Users", "用户"), systemImage: "person.2.fill") } }
            MoreView().tabItem { Label(localized("More", "更多"), systemImage: "ellipsis.circle.fill") }
        }
    }
}
