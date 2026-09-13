import SwiftUI

struct RootView: View {
    @Environment(InstanceStore.self) private var store
    @Environment(AppLock.self) private var lock

    var body: some View {
        Group {
            if lock.phase == .locked { LockView() }
            else if store.selected == nil { InstanceSetupView() }
            else if let instance = store.selected, !store.hasSession(for: instance) { LoginView(instance: instance) }
            else { AdminTabView() }
        }
        .tint(.cyan)
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
            ActivityView().tabItem { Label(localized("Requests", "请求"), systemImage: "arrow.trianglehead.2.clockwise") }
            if store.sessionUser?.isAdministrator == true { UsersView().tabItem { Label(localized("Users", "用户"), systemImage: "person.2.fill") } }
            MoreView().tabItem { Label(localized("More", "更多"), systemImage: "ellipsis.circle.fill") }
        }
        .task { await store.refreshSession() }
    }
}
