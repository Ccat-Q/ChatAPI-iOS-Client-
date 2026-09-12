import SwiftUI

struct RootView: View {
    @Environment(InstanceStore.self) private var store
    @Environment(AppLock.self) private var lock

    var body: some View {
        Group {
            if lock.phase == .locked { LockView() }
            else if store.selected == nil { InstanceSetupView() }
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
            OverviewView().tabItem { Label("Overview", systemImage: "rectangle.3.group.fill") }
            ActivityView().tabItem { Label("Activity", systemImage: "bolt.horizontal.circle.fill") }
            UsersView().tabItem { Label("Users", systemImage: "person.2.fill") }
            MoreView().tabItem { Label("More", systemImage: "ellipsis.circle.fill") }
        }
    }
}
