import Foundation
import LocalAuthentication
import Observation

enum DeviceAuthenticationMethod: Sendable {
    case faceID, touchID, passcode

    var symbol: String { switch self { case .faceID: "faceid"; case .touchID: "touchid"; case .passcode: "lock.shield" } }
    var title: String { switch self { case .faceID: "Face ID"; case .touchID: "Touch ID"; case .passcode: localized("Device Passcode", "设备密码") } }
}

@MainActor protocol DeviceAuthenticationContext: AnyObject {
    var method: DeviceAuthenticationMethod { get }
    func evaluate(reason: String) async throws -> Bool
    func invalidate()
}

@MainActor private final class SystemAuthenticationContext: DeviceAuthenticationContext {
    private let context = LAContext()
    var method: DeviceAuthenticationMethod {
        _ = context.canEvaluatePolicy(.deviceOwnerAuthentication, error: nil)
        switch context.biometryType {
        case .faceID: return .faceID
        case .touchID: return .touchID
        default: return .passcode
        }
    }
    func evaluate(reason: String) async throws -> Bool {
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            throw error ?? NSError(domain: LAError.errorDomain, code: LAError.Code.passcodeNotSet.rawValue)
        }
        return try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)
    }
    func invalidate() { context.invalidate() }
}

@MainActor @Observable final class AppLock {
    enum Phase { case locked, unlocked }
    private(set) var phase: Phase = .locked
    private(set) var isAuthenticating = false
    private(set) var method: DeviceAuthenticationMethod = .passcode
    private(set) var message: String?
    @ObservationIgnored private var activeContext: (any DeviceAuthenticationContext)?
    @ObservationIgnored private var unlockTask: Task<Void, Never>?
    private let makeContext: @MainActor () -> any DeviceAuthenticationContext
    private var attemptID = UUID()
    private var attemptedAutomaticUnlock = false

    init(makeContext: (@MainActor () -> any DeviceAuthenticationContext)? = nil) {
        self.makeContext = makeContext ?? { SystemAuthenticationContext() }
    }

    func shouldHideContent(isBackground: Bool, isInactive: Bool) -> Bool {
        isBackground || (isInactive && phase == .unlocked)
    }

    func unlockAutomatically() {
        guard !attemptedAutomaticUnlock else { return }
        unlock()
    }

    func unlock() {
        guard phase == .locked, !isAuthenticating else { return }
        attemptedAutomaticUnlock = true
        let context = makeContext()
        let attempt = UUID()
        attemptID = attempt
        activeContext = context
        method = context.method
        message = nil
        isAuthenticating = true
        unlockTask = Task { [weak self] in
            let success: Bool
            let failure: String?
            do {
                success = try await context.evaluate(reason: localized("Unlock your ChatAPI workspace", "解锁 ChatAPI 工作台"))
                failure = success ? nil : localized("Authentication was not completed. Try again.", "验证未完成，请重试。")
            } catch {
                success = false
                failure = Self.authenticationMessage(error)
            }
            guard let self, self.attemptID == attempt, !Task.isCancelled else { return }
            self.activeContext = nil
            self.unlockTask = nil
            self.isAuthenticating = false
            self.message = failure
            if success { self.phase = .unlocked }
        }
    }

    func lock() {
        attemptID = UUID()
        activeContext?.invalidate()
        activeContext = nil
        unlockTask?.cancel()
        unlockTask = nil
        isAuthenticating = false
        attemptedAutomaticUnlock = false
        message = nil
        phase = .locked
    }

    func authenticate(reason: String) async -> Bool {
        guard phase == .unlocked, !isAuthenticating else { return false }
        let attempt = UUID()
        attemptID = attempt
        let context = makeContext()
        activeContext = context
        isAuthenticating = true
        defer {
            if attemptID == attempt { activeContext = nil; isAuthenticating = false }
        }
        let success = (try? await context.evaluate(reason: reason)) ?? false
        return success && phase == .unlocked && attemptID == attempt && !Task.isCancelled
    }

    private static func authenticationMessage(_ error: Error) -> String {
        guard let error = error as? LAError else { return error.localizedDescription }
        switch error.code {
        case .userCancel, .userFallback:
            return localized("Authentication cancelled. Tap Unlock to try again.", "已取消验证。点击解锁可重试。")
        case .systemCancel, .appCancel:
            return localized("Authentication was interrupted. Tap Unlock when ready.", "验证已中断，请点击解锁重试。")
        case .passcodeNotSet:
            return localized("Set a device passcode in Settings to unlock this app.", "请先在系统设置中配置设备密码，再解锁此应用。")
        default:
            return error.localizedDescription
        }
    }
}
