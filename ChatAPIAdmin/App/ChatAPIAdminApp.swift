import SwiftUI

@main
struct ChatAPIAdminApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @State private var store = InstanceStore()
    @State private var lock = AppLock()
    @State private var settings = AppSettings()

    init() {
        #if DEBUG
        if ProcessInfo.processInfo.environment["CHATAPI_UI_PREVIEW"] != nil {
            UserDefaults.standard.set("chinese", forKey: "app-language")
        }
        #endif
    }

    var body: some Scene {
        WindowGroup {
            applicationContent
                .environment(store)
                .environment(lock)
                .environment(settings)
                .environment(\.locale, Locale(identifier: settings.language.localeIdentifier ?? Locale.current.identifier))
                .overlay {
                    if lock.shouldHideContent(isBackground: scenePhase == .background, isInactive: scenePhase == .inactive) {
                        Color(.systemGroupedBackground).ignoresSafeArea()
                            .overlay { Image(systemName: "lock.shield").font(.largeTitle).foregroundStyle(.secondary) }
                    }
                }
                .task { if !isUIPreview { store.restore(); if scenePhase == .active { lock.unlockAutomatically() } } }
                .onChange(of: scenePhase) { _, phase in
                    guard !isUIPreview else { return }
                    if phase == .background { lock.lock(); store.invalidateValidation() }
                    if phase == .active { lock.unlockAutomatically() }
                }
        }
    }

    private var isUIPreview: Bool {
        #if DEBUG
        ProcessInfo.processInfo.environment["CHATAPI_UI_PREVIEW"] != nil
        #else
        false
        #endif
    }

    @ViewBuilder private var applicationContent: some View {
        #if DEBUG
        if let preview = ProcessInfo.processInfo.environment["CHATAPI_UI_PREVIEW"] {
            if preview == "lock" { LockPreviewView() }
            else { ComposerPreviewView(mode: AICompletionMode(rawValue: preview) ?? .reply) }
        } else { RootView() }
        #else
        RootView()
        #endif
    }
}
