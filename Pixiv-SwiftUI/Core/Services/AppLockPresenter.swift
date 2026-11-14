#if os(iOS)
import SwiftUI
import UIKit

struct AppLockView: View {
    let manager: AppLockManager

    var body: some View {
        ZStack {
            Color(.systemBackground)
                .ignoresSafeArea()

            VStack(spacing: 20) {
                Image(systemName: manager.symbolName)
                    .font(.system(size: 56))
                    .foregroundStyle(.tint)

                Text("앱이 잠겨 있습니다")
                    .font(.title2)
                    .fontWeight(.semibold)

                Text(manager.lastError ?? "\(manager.methodName)로 잠금을 해제하세요")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)

                Button {
                    Task { await manager.unlock(userInitiated: true) }
                } label: {
                    Text("잠금 해제")
                        .frame(minWidth: 140)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(manager.isAuthenticating)
            }
        }
    }
}

/// 잠금 화면을 시트까지 포함해 모든 화면 위에 덮는 별도 창으로 띄운다.
@MainActor
final class AppLockPresenter {
    static let shared = AppLockPresenter()

    private var window: UIWindow?

    private init() {}

    func update(isLocked: Bool) {
        if isLocked {
            show()
        } else {
            hide()
        }
    }

    private func show() {
        guard window == nil else {
            window?.isHidden = false
            return
        }
        guard let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState != .unattached }) else { return }

        let lockWindow = UIWindow(windowScene: scene)
        lockWindow.windowLevel = .alert + 1
        let controller = UIHostingController(rootView: AppLockView(manager: AppLockManager.shared))
        controller.view.backgroundColor = .systemBackground
        lockWindow.rootViewController = controller
        lockWindow.makeKeyAndVisible()
        window = lockWindow
    }

    private func hide() {
        window?.isHidden = true
        window = nil
    }
}
#endif
