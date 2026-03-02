import Foundation
import AppKit

class SparkleUpdateService: ObservableObject {
    static let shared = SparkleUpdateService()

    @Published var isCheckingForUpdates = false
    @Published var updateAvailable = false
    @Published var currentVersion = ""
    @Published var latestVersion = ""
    @Published var updateDescription = ""
    @Published var latestReleaseURL: URL?

    private init() {
        currentVersion = Bundle.main.appVersion
    }

    func updateSparkleLanguage(_ language: String) {
        UserDefaults.standard.set([language], forKey: "AppleLanguages")
    }

    func getCurrentArchitecture() -> String {
        Architecture.current.sparkleArch
    }

    func getUpdaterStatus() -> (isInitialized: Bool, sessionInProgress: Bool, isChecking: Bool) {
        (isInitialized: false, sessionInProgress: false, isChecking: isCheckingForUpdates)
    }

    func checkForUpdatesWithUI() {
        Task {
            await checkForUpdates(showUI: true)
        }
    }

    func checkForUpdatesSilently() {
        Task {
            await checkForUpdates(showUI: false)
        }
    }

    @MainActor
    private func checkForUpdates(showUI: Bool) async {
        if isCheckingForUpdates {
            return
        }
        isCheckingForUpdates = true
        defer { isCheckingForUpdates = false }

        do {
            let release = try await fetchLatestRelease()
            latestVersion = release.tagName
            updateDescription = release.body
            latestReleaseURL = release.htmlURL

            if isRemoteVersionNewer(release.tagName, than: currentVersion) {
                updateAvailable = true
                if showUI {
                    openReleasePageIfPossible()
                }
            } else if showUI {
                showInfoAlert(
                    title: "已是最新版本",
                    message: "当前版本 \(currentVersion)"
                )
            }
        } catch {
            updateAvailable = false
            if showUI {
                showInfoAlert(
                    title: "检查更新失败",
                    message: error.localizedDescription
                )
            }
        }
    }

    @MainActor
    private func openReleasePageIfPossible() {
        guard let url = latestReleaseURL else {
            return
        }
        NSWorkspace.shared.open(url)
    }

    private func fetchLatestRelease() async throws -> LatestReleaseResponse {
        let url = URLConfig.API.GitHub.latestRelease()
        let (data, response) = try await URLSession.shared.data(from: url)
        guard let httpResponse = response as? HTTPURLResponse, 200..<300 ~= httpResponse.statusCode else {
            throw URLError(.badServerResponse)
        }
        let decoder = JSONDecoder()
        return try decoder.decode(LatestReleaseResponse.self, from: data)
    }

    private func isRemoteVersionNewer(_ remote: String, than local: String) -> Bool {
        let remoteParts = normalizeVersion(remote)
        let localParts = normalizeVersion(local)
        let count = max(remoteParts.count, localParts.count)
        for index in 0..<count {
            let lhs = index < remoteParts.count ? remoteParts[index] : 0
            let rhs = index < localParts.count ? localParts[index] : 0
            if lhs != rhs {
                return lhs > rhs
            }
        }
        return false
    }

    private func normalizeVersion(_ value: String) -> [Int] {
        let cleaned = value.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "v", with: "", options: .caseInsensitive)
        let segments = cleaned.split(separator: ".")
        return segments.map { segment in
            let number = segment.prefix { $0.isNumber }
            return Int(number) ?? 0
        }
    }

    @MainActor
    private func showInfoAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .informational
        alert.addButton(withTitle: "确定")
        alert.runModal()
    }
}

private struct LatestReleaseResponse: Decodable {
    let tagName: String
    let htmlURL: URL
    let body: String

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case htmlURL = "html_url"
        case body
    }
}
