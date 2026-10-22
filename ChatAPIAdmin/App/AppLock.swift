import Foundation
import LocalAuthentication
import Observation

@MainActor @Observable final class AppLock {
    enum Phase { case locked, unlocked }
    private(set) var phase: Phase = .locked
    private var unlockContext: LAContext?
    private var attemptID = UUID()

    func unlock() {
        guard phase == .locked, unlockContext == nil else { return }
        let context = LAContext()
        let attempt = UUID()
        attemptID = attempt
        unlockContext = context
        context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: localized("Unlock ChatAPI Admin", "解锁 ChatAPI 管理")) { [weak self] success, _ in
            Task { @MainActor [weak self] in
                guard let self, self.attemptID == attempt else { return }
                self.unlockContext = nil
                if success { self.phase = .unlocked }
            }
        }
    }

    func lock() {
        attemptID = UUID()
        unlockContext?.invalidate()
        unlockContext = nil
        phase = .locked
    }

    func authenticate(reason: String) async -> Bool {
        guard phase == .unlocked else { return false }
        let attempt = attemptID
        let context = LAContext()
        let success = await withCheckedContinuation { continuation in
            context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason) { success, _ in
                continuation.resume(returning: success)
            }
        }
        return success && phase == .unlocked && attemptID == attempt
    }
}
