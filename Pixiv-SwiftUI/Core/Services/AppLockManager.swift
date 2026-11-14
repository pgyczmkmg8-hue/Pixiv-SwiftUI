import Foundation
import LocalAuthentication
import Observation
import os.log

@MainActor
@Observable
final class AppLockManager {
    static let shared = AppLockManager()

    private let enabledKey = "appLockEnabled"

    private(set) var isEnabled: Bool
    private(set) var isLocked: Bool
    private(set) var isAuthenticating = false
    private(set) var lastError: String?
    private var lastAuthFinishedAt: Date?

    private init() {
        let enabled = UserDefaults.standard.bool(forKey: enabledKey)
        self.isEnabled = enabled
        self.isLocked = enabled
    }

    var methodName: String {
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
            return "기기 암호"
        }
        switch context.biometryType {
        case .faceID: return "Face ID"
        case .touchID: return "Touch ID"
        case .opticID: return "Optic ID"
        default: return "생체인식"
        }
    }

    var symbolName: String {
        switch methodName {
        case "Face ID": return "faceid"
        case "Touch ID": return "touchid"
        case "Optic ID": return "opticid"
        default: return "lock.fill"
        }
    }

    var canAuthenticate: Bool {
        var error: NSError?
        return LAContext().canEvaluatePolicy(.deviceOwnerAuthentication, error: &error)
    }

    func lockIfNeeded() {
        guard isEnabled, !isAuthenticating else { return }
        isLocked = true
    }

    /// 인증 창이 닫히면서 앱이 다시 활성화될 때 자동으로 또 묻지 않도록, 방금 끝난 인증 직후의 자동 요청은 건너뛴다.
    func unlock(userInitiated: Bool = false) async {
        guard isLocked, !isAuthenticating else { return }
        if !userInitiated, let finished = lastAuthFinishedAt, Date().timeIntervalSince(finished) < 2 {
            return
        }
        if await authenticate(reason: "앱 잠금을 해제합니다") {
            isLocked = false
        }
    }

    /// 설정을 바꾸기 전에 한 번 인증한다. 켤 때는 인증이 실제로 되는지 확인하는 역할도 한다.
    func setEnabled(_ enabled: Bool) async -> Bool {
        guard enabled != isEnabled else { return true }

        if enabled && !canAuthenticate {
            lastError = "이 기기에 암호나 생체인식이 설정되어 있지 않습니다. 설정에서 먼저 기기 암호를 만드세요"
            return false
        }

        let reason = enabled ? "앱 잠금을 켭니다" : "앱 잠금을 끕니다"
        guard await authenticate(reason: reason) else { return false }

        UserDefaults.standard.set(enabled, forKey: enabledKey)
        isEnabled = enabled
        isLocked = false
        return true
    }

    private func authenticate(reason: String) async -> Bool {
        isAuthenticating = true
        lastError = nil
        defer {
            isAuthenticating = false
            lastAuthFinishedAt = Date()
        }

        let context = LAContext()
        context.localizedCancelTitle = "취소"

        do {
            return try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)
        } catch {
            let code = (error as? LAError)?.code
            if code != .userCancel && code != .appCancel && code != .systemCancel {
                lastError = error.localizedDescription
                Logger.auth.error("App lock authentication failed: \(error.localizedDescription, privacy: .public)")
            }
            return false
        }
    }
}
