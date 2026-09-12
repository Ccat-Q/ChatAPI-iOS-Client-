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
        ContentUnavailableView("ChatAPI Admin Locked", systemImage: "lock.fill", description: Text("Authenticate to manage your instances."))
            .glassEffect()
            .onTapGesture { lock.unlock() }
    }
}

struct AdminTabView: View {
    var body: some View {
        TabView {
            OverviewView().tabItem { Label(localized("Overview", "概览"), systemImage: "rectangle.3.group.fill") }
            ActivityView().tabItem { Label(localized("Activity", "活动"), systemImage: "bolt.horizontal.circle.fill") }
            UsersView().tabItem { Label(localized("Users", "用户"), systemImage: "person.2.fill") }
            MoreView().tabItem { Label(localized("More", "更多"), systemImage: "ellipsis.circle.fill") }
        }
    }
}
