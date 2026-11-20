import SwiftUI

#if os(iOS)
    import UIKit

    @MainActor
    final class AppPreviewPrivacyManager {
        static let shared = AppPreviewPrivacyManager()

        private let overlayTag = 0x507658

        private init() {}

        func updateProtection(isEnabled: Bool, scenePhase: ScenePhase) {
            let shouldProtect = isEnabled && scenePhase != .active

            for window in appWindows {
                if shouldProtect {
                    if !window.isHidden && window.windowLevel == .normal {
                        installOverlay(on: window)
                    }
                } else {
                    removeOverlay(from: window)
                }
            }
        }

        func removeAllOverlays() {
            for window in appWindows {
                removeOverlay(from: window)
            }
        }

        private var appWindows: [UIWindow] {
            UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .flatMap(\.windows)
        }

        /// 백그라운드 전환 또는 앱 전환 화면에서 창 전체를 불투명한 배경으로 가려 화면 내용이 노출되지 않게 한다.
        private func installOverlay(on window: UIWindow) {
            if let overlay = window.viewWithTag(overlayTag) {
                window.bringSubviewToFront(overlay)
                return
            }

            let view = UIView(frame: window.bounds)
            view.tag = overlayTag
            view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            view.backgroundColor = .systemBackground
            view.isUserInteractionEnabled = false
            window.addSubview(view)
            window.bringSubviewToFront(view)
        }

        private func removeOverlay(from window: UIWindow) {
            window.viewWithTag(overlayTag)?.removeFromSuperview()
        }
    }
#else
    @MainActor
    final class AppPreviewPrivacyManager {
        static let shared = AppPreviewPrivacyManager()

        private init() {}

        func updateProtection(isEnabled: Bool, scenePhase: ScenePhase) {}

        func removeAllOverlays() {}
    }
#endif
