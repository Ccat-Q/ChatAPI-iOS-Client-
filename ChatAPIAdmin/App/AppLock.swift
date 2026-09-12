import Foundation
import LocalAuthentication
import Observation

@Observable final class AppLock {
    enum Phase { case locked, unlocked }
    private(set) var phase: Phase = .locked

    func unlock() {
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            phase = .unlocked
            return
        }
        context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "Unlock ChatAPI Admin") { [weak self] success, _ in
            if success { DispatchQueue.main.async { self?.phase = .unlocked } }
        }
    }

    func lock() { phase = .locked }
}
