import Foundation
import LocalAuthentication
import Observation

@MainActor @Observable final class AppLock {
    enum Phase { case locked, unlocked }
    private(set) var phase: Phase = .locked

    func unlock() {
        let context = LAContext()
        context.localizedFallbackTitle = localized("Use Device Passcode", "使用设备密码")
        var error: NSError?
        if context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) {
            context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: localized("Unlock ChatAPI Admin", "解锁 ChatAPI 管理")) { [weak self] success, _ in
                if success { Task { @MainActor [weak self] in self?.phase = .unlocked } }
            }
            return
        }
        context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: localized("Unlock ChatAPI Admin", "解锁 ChatAPI 管理")) { [weak self] success, _ in
            if success { Task { @MainActor [weak self] in self?.phase = .unlocked } }
        }
    }

    func lock() { phase = .locked }

    func authenticate(reason: String) async -> Bool {
        let context = LAContext()
        context.localizedFallbackTitle = localized("Use Device Passcode", "使用设备密码")
        let policy: LAPolicy = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil) ? .deviceOwnerAuthenticationWithBiometrics : .deviceOwnerAuthentication
        return await withCheckedContinuation { continuation in
            context.evaluatePolicy(policy, localizedReason: reason) { success, _ in
                continuation.resume(returning: success)
            }
        }
    }
}
