import Foundation
import os.log
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

struct GitLabRelease: Codable {
    let tagName: String
    let name: String?
    let description: String?
    let links: Links?
    let assets: Assets?

    struct Links: Codable {
        let selfUrl: String?

        enum CodingKeys: String, CodingKey {
            case selfUrl = "self"
        }
    }

    struct Assets: Codable {
        let links: [AssetLink]
    }

    struct AssetLink: Codable {
        let name: String
        let url: String
        let directAssetUrl: String?

        enum CodingKeys: String, CodingKey {
            case name
            case url
            case directAssetUrl = "direct_asset_url"
        }
    }

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case name
        case description
        case links = "_links"
        case assets
    }
}

enum UpdateCheckerError: LocalizedError {
    case networkError(String)
    case decodingError(String)
    case noReleaseFound
    case unauthorized
    case rateLimited

    var errorDescription: String? {
        switch self {
        case .networkError(let message):
            return "네트워크 오류: \(message)"
        case .decodingError(let message):
            return "파싱 오류: \(message)"
        case .noReleaseFound:
            return "릴리즈 버전을 찾을 수 없습니다"
        case .rateLimited:
            return "요청이 너무 많아 잠시 제한되었습니다. 잠시 후 다시 시도하세요. 토큰을 저장하면 제한이 완화됩니다"
        case .unauthorized:
            return "접근 권한이 없습니다. 저장소가 비공개라면 읽기 전용 토큰을 저장하거나 토큰이 만료되지 않았는지 확인하세요"
        }
    }
}

struct AppUpdateInfo: Identifiable {
    let id = UUID()
    let version: String
    let releaseName: String
    let releaseNotes: String
    let releaseUrl: String
    let downloadUrl: String?

    var isNewerThanCurrent: Bool {
        guard let currentVersion = currentAppVersion else { return false }
        return UpdateChecker.compareVersions(new: version, current: currentVersion) > 0
    }

    private var currentAppVersion: String? {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
    }
}

@MainActor
final class UpdateChecker {
    static let shared = UpdateChecker()

    static let repositoryPath = "Yami_Q_Ray/Pixiv-SwiftUI"
    static let repositoryURL = "https://gitlab.com/Yami_Q_Ray/Pixiv-SwiftUI"

    private let session: URLSession
    private let skippedUpdateVersionKey = "skippedUpdateVersion"
    private let keychainService = "com.pixiv.app.update"
    private let keychainAccount = "gitlab-read-token"

    private(set) var lastError: String?

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15
        self.session = URLSession(configuration: config)
    }

    // MARK: - Token

    var savedToken: String {
        (try? KeychainHelper.load(service: keychainService, account: keychainAccount)) ?? ""
    }

    var hasToken: Bool {
        !savedToken.isEmpty
    }

    func saveToken(_ token: String) {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            try? KeychainHelper.delete(service: keychainService, account: keychainAccount)
        } else {
            do {
                try KeychainHelper.save(trimmed, service: keychainService, account: keychainAccount)
            } catch {
                Logger.updater.error("Failed to save update token: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    // MARK: - Skip version

    func skipVersion(_ version: String) {
        UserDefaults.standard.set(
            normalizedVersion(version),
            forKey: skippedUpdateVersionKey
        )
    }

    func isVersionSkipped(_ version: String) -> Bool {
        guard let skippedVersion = UserDefaults.standard.string(forKey: skippedUpdateVersionKey) else {
            return false
        }

        return skippedVersion == normalizedVersion(version)
    }

    private func normalizedVersion(_ version: String) -> String {
        Self.normalizedVersion(version)
    }

    nonisolated static func normalizedVersion(_ version: String) -> String {
        var value = version.trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
        if let index = value.firstIndex(where: { $0 == "-" || $0 == "+" }) {
            value = String(value[..<index])
        }
        return value
    }

    nonisolated static func compareVersions(new: String, current: String) -> Int {
        let newComponents = normalizedVersion(new).split(separator: ".").compactMap { Int($0) }
        let currentComponents = normalizedVersion(current).split(separator: ".").compactMap { Int($0) }

        for index in 0..<max(newComponents.count, currentComponents.count) {
            let newPart = index < newComponents.count ? newComponents[index] : 0
            let currentPart = index < currentComponents.count ? currentComponents[index] : 0
            if newPart != currentPart {
                return newPart > currentPart ? 1 : -1
            }
        }
        return 0
    }

    // MARK: - Check

    func checkForUpdate() async -> AppUpdateInfo? {
        lastError = nil

        let encodedPath = Self.repositoryPath.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? ""
        guard let url = URL(string: "https://gitlab.com/api/v4/projects/\(encodedPath)/releases?per_page=1&order_by=released_at&sort=desc") else {
            return nil
        }

        var request = URLRequest(url: url)
        let token = savedToken
        if !token.isEmpty {
            request.setValue(token, forHTTPHeaderField: "PRIVATE-TOKEN")
        }

        do {
            let (data, response) = try await session.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                lastError = UpdateCheckerError.networkError("no response").errorDescription
                return nil
            }

            if httpResponse.statusCode == 429 {
                lastError = UpdateCheckerError.rateLimited.errorDescription
                return nil
            }

            if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 || httpResponse.statusCode == 404 {
                lastError = UpdateCheckerError.unauthorized.errorDescription
                Logger.updater.debug("Release API status: \(httpResponse.statusCode)")
                return nil
            }

            guard httpResponse.statusCode == 200 else {
                lastError = UpdateCheckerError.networkError("HTTP \(httpResponse.statusCode)").errorDescription
                Logger.updater.debug("Release API status: \(httpResponse.statusCode)")
                return nil
            }

            let releases = try JSONDecoder().decode([GitLabRelease].self, from: data)
            guard let release = releases.first else {
                lastError = UpdateCheckerError.noReleaseFound.errorDescription
                return nil
            }

            return AppUpdateInfo(
                version: Self.normalizedVersion(release.tagName),
                releaseName: release.name ?? release.tagName,
                releaseNotes: release.description ?? "업데이트 내역이 없습니다",
                releaseUrl: release.links?.selfUrl ?? "\(Self.repositoryURL)/-/releases",
                downloadUrl: findDownloadUrl(for: release)
            )
        } catch let error as DecodingError {
            lastError = UpdateCheckerError.decodingError(error.localizedDescription).errorDescription
            Logger.updater.error("Failed to decode release: \(error.localizedDescription, privacy: .public)")
            return nil
        } catch {
            lastError = UpdateCheckerError.networkError(error.localizedDescription).errorDescription
            Logger.updater.error("Failed to check for update: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    private func findDownloadUrl(for release: GitLabRelease) -> String? {
        let links = release.assets?.links ?? []
        let ipa = links.first { $0.name.lowercased().hasSuffix(".ipa") }
        return (ipa ?? links.first)?.url
    }

    // MARK: - Install

    /// Feather 앱으로 IPA를 바로 설치한다. 토큰이 필요한 비공개 저장소의 파일은 Feather가 받을 수 없고,
    /// 토큰을 주소에 넣으면 노출되므로 토큰이 저장돼 있으면 쓰지 않는다.
    var canInstallWithFeather: Bool {
        !hasToken
    }

    func installWithFeather(downloadUrl: String) async -> Bool {
        #if os(iOS)
        guard canInstallWithFeather, let url = URL(string: "feather://install/\(downloadUrl)") else {
            return false
        }
        return await UIApplication.shared.open(url)
        #else
        return false
        #endif
    }

    var currentAppVersion: String? {
        guard let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String,
              let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String else {
            return nil
        }
        return "\(version) (Build \(build))"
    }
}
