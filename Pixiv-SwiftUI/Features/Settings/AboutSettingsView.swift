import SwiftUI
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

struct AboutSettingsView: View {
    @Environment(UserSettingStore.self) var userSettingStore
    @State private var showingResetAlert = false

    @State private var isCheckingUpdate = false
    @State private var updateInfo: AppUpdateInfo?
    @State private var showingUpdateAlert = false
    @State private var showingNoUpdateAlert = false
    @State private var checkError: String?
    @State private var showingCheckErrorAlert = false
    @State private var tokenInput = ""
    @State private var tokenSaved = UpdateChecker.shared.hasToken

    var body: some View {
        VStack {
            Image("launch")
                .resizable()
                .frame(width: iconSize, height: iconSize)
                .padding(.top, topPadding)

            Text("Pixiv-SwiftUI")
                .font(.title2)
                .fontWeight(.semibold)
                .padding(.bottom, bottomPadding)

            Form {
                appInfoSection
                updateSection
                guideSection
                linksSection
            }
            .formStyle(.grouped)
        }
        #if os(iOS)
        .background(Color(.systemGroupedBackground))
        #endif
        #if os(macOS)
        .alert("确认重置", isPresented: $showingResetAlert) {
            Button("取消", role: .cancel) { }
            Button("重置", role: .destructive) {
            }
        } message: {
            Text("确定要重置所有设置为默认值吗？")
        }
        .safeAreaInset(edge: .bottom) {
            resetButton
        }
        #endif
        .sheet(isPresented: $showingUpdateAlert) {
            if let info = updateInfo {
                UpdateAvailableSheet(
                    updateInfo: info,
                    isPresented: $showingUpdateAlert,
                    onSkip: { UpdateChecker.shared.skipVersion(info.version) }
                )
            }
        }
        .alert("업데이트 확인 실패", isPresented: $showingCheckErrorAlert) {
            Button("확인", role: .cancel) { }
        } message: {
            Text(checkError ?? "")
        }
        .alert("已是最新版本", isPresented: $showingNoUpdateAlert) {
            Button("确定", role: .cancel) { }
        } message: {
            Text("当前已是最新版本")
        }
    }

    private var iconSize: CGFloat {
        #if os(macOS)
        80
        #else
        64
        #endif
    }

    private var topPadding: CGFloat {
        #if os(macOS)
        20
        #else
        16
        #endif
    }

    private var bottomPadding: CGFloat {
        #if os(macOS)
        10
        #else
        8
        #endif
    }

    #if os(macOS)
    private var resetButton: some View {
        Button("重置所有设置") {
            showingResetAlert = true
        }
        .buttonStyle(.link)
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    #endif

    private var appInfoSection: some View {
        Section("应用信息") {
            HStack {
                Text("版本")
                Spacer()
                if let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String,
                   let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String {
                    Text("\(version) (Build \(build))")
                        .foregroundColor(.secondary)
                } else if let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String {
                    Text(version)
                        .foregroundColor(.secondary)
                } else {
                    Text("Unknown")
                        .foregroundColor(.secondary)
                }
            }
        }
    }

    private var guideSection: some View {
        Section(String(localized: "向导")) {
            NavigationLink {
                OnboardingLandingView(
                    isCompleted: .constant(true),
                    isEmbeddedInNavigation: true
                )
            } label: {
                Text(String(localized: "常用设置向导"))
            }
        }
    }

    private var updateSection: some View {
        Section {
            Button {
                checkForUpdate()
            } label: {
                HStack {
                    Text(String(localized: "检查更新"))
                    Spacer()
                    if isCheckingUpdate {
                        ProgressView()
                            .scaleEffect(0.8)
                    }
                }
            }
            .buttonStyle(.plain)
            .tint(nil)
            .disabled(isCheckingUpdate)

            Toggle(String(localized: "启动时检查更新"), isOn: Binding(
                get: { userSettingStore.userSetting.checkUpdateOnLaunch },
                set: { newValue in
                    try? userSettingStore.setCheckUpdateOnLaunch(newValue)
                }
            ))

            SecureField("GitLab 읽기 전용 토큰 (비공개 저장소용)", text: $tokenInput)
                .textContentType(.password)
                #if os(iOS)
                .textInputAutocapitalization(.never)
                #endif
                .autocorrectionDisabled()

            HStack {
                Text(tokenSaved ? "토큰이 저장되어 있습니다" : "저장된 토큰 없음")
                    .foregroundColor(.secondary)
                Spacer()
                Button("저장") {
                    UpdateChecker.shared.saveToken(tokenInput)
                    tokenInput = ""
                    tokenSaved = UpdateChecker.shared.hasToken
                }
                .disabled(tokenInput.trimmingCharacters(in: .whitespaces).isEmpty)
                if tokenSaved {
                    Button("삭제", role: .destructive) {
                        UpdateChecker.shared.saveToken("")
                        tokenSaved = UpdateChecker.shared.hasToken
                    }
                }
            }
        } header: {
            Text("업데이트")
        } footer: {
            Text("비공개 저장소는 읽기 전용 토큰(read_api)이 필요합니다. 새 버전 알림에서 \"Feather로 설치\"를 누르면 토큰이 포함된 주소가 Feather로 전달됩니다.")
        }
    }

    private var linksSection: some View {
        Section("链接") {
            if let githubURL = URL(string: UpdateChecker.repositoryURL) {
                Link(destination: githubURL) {
                    HStack {
                        Text("GitLab")
                        Spacer()
                        Image(systemName: "arrow.up.right.square")
                            .foregroundColor(.secondary)
                    }
                }
            }

            if let pixivURL = URL(string: "https://www.pixiv.net") {
                Link(destination: pixivURL) {
                    HStack {
                        Text("Pixiv 官网")
                        Spacer()
                        Image(systemName: "arrow.up.right.square")
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
    }

    private func checkForUpdate() {
        isCheckingUpdate = true
        checkError = nil

        Task {
            let result = await UpdateChecker.shared.checkForUpdate()
            await MainActor.run {
                isCheckingUpdate = false

                if let info = result {
                    updateInfo = info
                    if info.isNewerThanCurrent {
                        showingUpdateAlert = true
                    } else {
                        showingNoUpdateAlert = true
                    }
                } else {
                    checkError = UpdateChecker.shared.lastError ?? "업데이트 확인 실패"
                    showingCheckErrorAlert = true
                }
            }
        }
    }
}

#Preview {
    NavigationStack {
        AboutSettingsView()
    }
}
