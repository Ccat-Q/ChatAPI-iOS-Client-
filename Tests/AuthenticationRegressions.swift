import Foundation
import LocalAuthentication

@MainActor private final class FakeAuthenticationContext: DeviceAuthenticationContext {
    let method: DeviceAuthenticationMethod = .faceID
    private(set) var started = false
    private(set) var invalidated = false
    private var continuation: CheckedContinuation<Bool, Error>?
    func evaluate(reason: String) async throws -> Bool {
        started = true
        return try await withCheckedThrowingContinuation { continuation = $0 }
    }
    func invalidate() { invalidated = true }
    func finish(_ result: Result<Bool, Error>) {
        let pending = continuation
        continuation = nil
        pending?.resume(with: result)
    }
}

extension CoreRegressions {
    static func authenticationRegressions() async throws {
        var contexts: [FakeAuthenticationContext] = []
        let lock = AppLock(makeContext: {
            let context = FakeAuthenticationContext()
            contexts.append(context)
            return context
        })
        try check(!lock.shouldHideContent(isBackground: false, isInactive: true), "An inactive Face ID prompt must not black out the locked page")
        try check(lock.shouldHideContent(isBackground: true, isInactive: false), "Background content must remain shielded")
        lock.unlockAutomatically(); lock.unlockAutomatically(); lock.unlock()
        try await waitUntil("Authentication did not start") { contexts.first?.started == true }
        try check(contexts.count == 1 && lock.isAuthenticating && lock.method == .faceID, "Duplicate unlocks must share one system prompt and show the real method")
        contexts[0].finish(.failure(NSError(domain: LAError.errorDomain, code: LAError.Code.userCancel.rawValue)))
        try await waitUntil("Cancelled authentication remained busy") { !lock.isAuthenticating }
        try check(lock.phase == .locked && lock.message != nil, "Cancellation must show a retryable locked state")
        lock.unlockAutomatically()
        await Task.yield()
        try check(contexts.count == 1, "Returning active after cancellation must not immediately prompt again")
        lock.unlock()
        try await waitUntil("Manual retry did not start") { contexts.count == 2 && contexts[1].started }
        contexts[1].finish(.success(true))
        try await waitUntil("Successful manual retry did not unlock") { lock.phase == .unlocked }
        try check(lock.message == nil && !lock.isAuthenticating, "Successful authentication must clear error and progress")
        try check(lock.shouldHideContent(isBackground: false, isInactive: true), "Unlocked sensitive content must be shielded when inactive")
        let highRisk = Task { @MainActor in await lock.authenticate(reason: "Fixture sensitive settings") }
        try await waitUntil("Sensitive authentication did not start") { contexts.count == 3 && contexts[2].started }
        lock.lock()
        try check(contexts[2].invalidated, "Lock must invalidate an in-progress authentication context")
        contexts[2].finish(.success(true))
        try check(!(await highRisk.value) && lock.phase == .locked, "Authentication completing after lock must not authorize an action")
        lock.unlockAutomatically()
        try await waitUntil("New foreground session did not get an automatic attempt") { contexts.count == 4 && contexts[3].started }
        lock.lock()
        contexts[3].finish(.success(true))
        await Task.yield()
        try check(lock.phase == .locked && !lock.isAuthenticating, "A stale unlock result must not reopen the app")

        let suiteName = "authentication-regression.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let settings = AppSettings(defaults: defaults)
        try check(settings.requiresAppUnlock, "Existing installs must keep app authentication enabled by default")
        settings.requiresAppUnlock = false
        try check(!AppSettings(defaults: defaults).requiresAppUnlock, "Disabling app authentication must survive settings reload")
        lock.setEnabled(false)
        lock.lock(); lock.unlockAutomatically(); lock.unlock()
        await Task.yield()
        try check(lock.phase == .unlocked && contexts.count == 4, "Disabled app authentication must not prompt at launch or after background lock")
        try check(lock.shouldHideContent(isBackground: true, isInactive: false), "Disabling app authentication must retain the background privacy shield")
        let sensitive = Task { @MainActor in await lock.authenticate(reason: "Sensitive action with app lock disabled") }
        try await waitUntil("Disabling app lock incorrectly bypassed sensitive authentication") { contexts.count == 5 && contexts[4].started }
        contexts[4].finish(.success(true))
        try check(await sensitive.value, "Sensitive actions must still require and accept real device authentication when app lock is disabled")
        lock.setEnabled(true)
        try check(lock.phase == .locked, "Re-enabling app lock must take effect immediately")
        lock.unlockAutomatically()
        try await waitUntil("Re-enabled app lock did not authenticate") { contexts.count == 6 && contexts[5].started }
        lock.setEnabled(false)
        try check(contexts[5].invalidated && lock.phase == .unlocked, "Disabling must invalidate an in-flight unlock")
        lock.setEnabled(true)
        contexts[5].finish(.success(true))
        await Task.yield()
        try check(lock.phase == .locked, "A result from before a settings change must not unlock the re-enabled app")
    }
}
