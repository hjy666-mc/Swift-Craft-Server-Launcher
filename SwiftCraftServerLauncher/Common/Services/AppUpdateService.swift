import AppKit
import Foundation
import Sparkle

@MainActor
final class AppUpdateService: NSObject, ObservableObject, SPUUpdaterDelegate {
    static let shared = AppUpdateService()

    @Published private(set) var isUpdating = false

    private lazy var updaterController: SPUStandardUpdaterController = {
        let controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: self,
            userDriverDelegate: nil
        )
        _ = controller.updater.clearFeedURLFromUserDefaults()
        return controller
    }()

    private override init() {}

    /// Menu entry keeps its old name to avoid touching call sites.
    func installLatestRelease() {
        guard !isUpdating else { return }

        guard let feedURLString = architectureFeedURLString, !feedURLString.isEmpty else {
            showAlert(
                title: "更新配置缺失",
                message: "当前架构的 Sparkle Appcast 地址无效。"
            )
            return
        }

        isUpdating = true
        updaterController.checkForUpdates(nil)

        // Sparkle manages the whole cycle; this flag only throttles rapid repeated taps.
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 800_000_000)
            isUpdating = false
        }
    }

    private var architectureFeedURLString: String? {
        let appcastURL = URLConfig.API.GitHub.appcastURL(
            architecture: Architecture.current.sparkleArch
        )
        let feed = appcastURL.absoluteString.trimmingCharacters(in: .whitespacesAndNewlines)
        return feed.isEmpty ? nil : feed
    }

    func feedURLString(for _: SPUUpdater) -> String? {
        architectureFeedURLString
    }

    private func showAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: "确定")
        alert.runModal()
    }
}
