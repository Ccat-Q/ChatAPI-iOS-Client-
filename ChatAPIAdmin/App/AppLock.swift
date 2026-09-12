import Foundation
import LocalAuthentication
import Observation

@MainActor @Observable final class AppLock {
    enum Phase { case locked, unlocked }
    private(set) var phase: Phase = .locked

    func unlock() {
        let context = LAContext()
        context.localizedFallbackTitle = "Use Device Passcode"
        var error: NSError?
        if context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) {
            context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: "Unlock ChatAPI Admin") { [weak self] success, _ in
                if success { Task { @MainActor [weak self] in self?.phase = .unlocked } }
            }
            return
        }
        context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "Unlock ChatAPI Admin") { [weak self] success, _ in
            if success { Task { @MainActor [weak self] in self?.phase = .unlocked } }
        }
    }

    func lock() { phase = .locked }
}
