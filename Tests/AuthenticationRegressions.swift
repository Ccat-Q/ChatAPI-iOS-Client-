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
    }
}
