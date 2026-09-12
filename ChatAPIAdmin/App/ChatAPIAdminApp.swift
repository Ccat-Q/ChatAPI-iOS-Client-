import SwiftUI

@main
struct ChatAPIAdminApp: App {
    @State private var store = InstanceStore()
    @State private var lock = AppLock()
    @State private var settings = AppSettings()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                .environment(lock)
                .environment(settings)
                .environment(\.locale, Locale(identifier: settings.language.localeIdentifier ?? Locale.current.identifier))
                .task { store.restore() }
                .onChange(of: lock.phase) { _, phase in
                    if phase == .locked { lock.unlock() }
                }
        }
    }
}
