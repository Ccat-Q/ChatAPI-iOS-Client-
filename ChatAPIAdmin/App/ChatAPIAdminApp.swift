import SwiftUI

@main
struct ChatAPIAdminApp: App {
    @Environment(\.scenePhase) private var scenePhase
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
                .overlay {
                    if scenePhase != .active {
                        Color.black.ignoresSafeArea().overlay { Image(systemName: "lock.fill").foregroundStyle(.white) }
                    }
                }
                .task { store.restore(); if scenePhase == .active { lock.unlock() } }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .background { lock.lock(); store.invalidateValidation() }
                    if phase == .active { lock.unlock() }
                }
        }
    }
}
