import SwiftUI

@main
struct ChatAPIAdminApp: App {
    @State private var store = InstanceStore()
    @State private var lock = AppLock()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                .environment(lock)
                .task { store.restore() }
                .onChange(of: lock.phase) { _, phase in
                    if phase == .locked { lock.unlock() }
                }
        }
    }
}
