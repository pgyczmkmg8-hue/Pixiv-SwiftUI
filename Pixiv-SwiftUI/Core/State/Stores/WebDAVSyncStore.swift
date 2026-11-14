import Foundation
import Observation

@MainActor
@Observable
final class WebDAVSyncStore {
    static let shared = WebDAVSyncStore()

    var serverURLString = ""
    var username = ""
    var remoteDirectory = "Pixiv-SwiftUI"
    var password = ""

    var isBusy = false
    var busyMessage = ""
    var statusMessage = ""
    var error: AppError?
    var showError: Bool { error != nil }
    var successMessage = ""
    var showSuccessToast = false
    var lastOperationDescription = "동기화한 적 없음"

    @ObservationIgnored
    private let service = WebDAVSyncService.shared
    private let authSession: AuthSessionProtocol

    private init(
        authSession: AuthSessionProtocol = AccountStore.shared
    ) {
        self.authSession = authSession
        reloadConfiguration()
        NotificationCenter.default.addObserver(
            forName: .accountDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.invalidateForAccountChange()
            }
        }
    }

    var accountScopeDescription: String {
        let basePath = remoteDirectory.trimmingCharacters(in: .whitespacesAndNewlines)
        if basePath.isEmpty {
            return authSession.currentUserId
        }
        return basePath + "/" + authSession.currentUserId
    }

    var hasConfiguration: Bool {
        !serverURLString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            !username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            !password.isEmpty
    }

    func reloadConfiguration() {
        let configuration = WebDAVSyncPreferences.loadConfiguration()
        serverURLString = configuration.serverURLString
        username = configuration.username
        remoteDirectory = configuration.remoteDirectory
        password = (try? WebDAVSyncPreferences.loadPassword()) ?? ""
        updateLastOperationDescription()
    }

    func saveConfiguration() {
        do {
            let configuration = WebDAVSyncConfiguration(
                serverURLString: serverURLString,
                username: username,
                remoteDirectory: remoteDirectory
            )
            try WebDAVSyncPreferences.saveConfiguration(configuration)
            try WebDAVSyncPreferences.savePassword(password)
            statusMessage = "WebDAV 설정 저장됨"
            showSuccess(message: statusMessage)
        } catch {
            present(error)
        }
    }

    func testConnection() async {
        let generation = authSession.accountGeneration
        let ownerId = authSession.currentUserId
        await perform("연결 테스트 중…", generation: generation, ownerId: ownerId) {
            let credentials = try persistAndBuildCredentials()
            let items = try await service.testConnection(
                using: credentials,
                ownerId: ownerId,
                accountGeneration: generation
            )
            if items.isEmpty {
                statusMessage = "연결 성공, 원격 디렉터리가 준비되었습니다"
            } else {
                statusMessage = "연결 성공, 원격에 백업 파일이 \(items.count)개 있습니다"
            }
            showSuccess(message: statusMessage)
        }
    }

    func uploadBackup() async {
        let generation = authSession.accountGeneration
        let ownerId = authSession.currentUserId
        await perform("백업 업로드 중…", generation: generation, ownerId: ownerId) {
            let credentials = try persistAndBuildCredentials()
            let manifest = try await service.uploadBackup(
                using: credentials,
                ownerId: ownerId,
                accountGeneration: generation
            )
            statusMessage = "동기화 데이터 \(manifest.datasets.count)건을 업로드했습니다"
            updateLastOperationDescription()
            showSuccess(message: statusMessage)
        }
    }

    func restoreBackup() async {
        let generation = authSession.accountGeneration
        let ownerId = authSession.currentUserId
        await perform("원격 데이터 복원 중…", generation: generation, ownerId: ownerId) {
            let credentials = try persistAndBuildCredentials()
            let manifest = try await service.restoreBackup(
                using: credentials,
                ownerId: ownerId,
                accountGeneration: generation
            )
            statusMessage = "원격에서 동기화 데이터 \(manifest.datasets.count)건을 복원했습니다"
            updateLastOperationDescription()
            showSuccess(message: statusMessage)
        }
    }

    private func perform(
        _ message: String,
        generation: UInt,
        ownerId: String,
        action: () async throws -> Void
    ) async {
        guard isCurrentOperation(generation: generation, ownerId: ownerId) else { return }
        guard !isBusy else { return }
        isBusy = true
        busyMessage = message
        defer {
            isBusy = false
            busyMessage = ""
        }

        do {
            try await action()
        } catch {
            guard isCurrentOperation(generation: generation, ownerId: ownerId) else { return }
            present(error)
        }
    }

    private func invalidateForAccountChange() {
        error = nil
        statusMessage = ""
        successMessage = ""
        showSuccessToast = false
    }

    private func isCurrentOperation(generation: UInt, ownerId: String) -> Bool {
        authSession.isCurrentAccount(generation: generation, userId: ownerId)
    }

    private func persistAndBuildCredentials() throws -> WebDAVSyncCredentials {
        let configuration = WebDAVSyncConfiguration(
            serverURLString: serverURLString,
            username: username,
            remoteDirectory: remoteDirectory
        )
        let credentials = try configuration.makeCredentials(password: password)
        try WebDAVSyncPreferences.saveConfiguration(configuration)
        try WebDAVSyncPreferences.savePassword(password)
        return credentials
    }

    private func updateLastOperationDescription() {
        if let operation = WebDAVSyncPreferences.loadLastOperation(ownerId: authSession.currentUserId) {
            let operationText = switch operation.kind {
            case .upload:
                "최근 업로드"
            case .restore:
                "최근 복원"
            }
            lastOperationDescription = operationText + "：" + operation.date.formatted(date: .abbreviated, time: .shortened)
        } else {
            lastOperationDescription = "동기화한 적 없음"
        }
    }

    private func present(_ error: Error) {
        self.error = AppError.unknown(error)
    }

    private func showSuccess(message: String) {
        successMessage = message
        showSuccessToast = true
    }
}
