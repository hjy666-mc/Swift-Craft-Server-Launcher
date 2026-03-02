import AppKit
import Foundation

final class AppUpdateService: ObservableObject {
    static let shared = AppUpdateService()

    @Published private(set) var isUpdating = false

    private init() {}

    func installLatestRelease() {
        Task { @MainActor in
            if isUpdating {
                return
            }
            isUpdating = true
            defer { isUpdating = false }

            do {
                try await downloadAndInstallLatestRelease()
            } catch {
                showAlert(
                    title: "更新失败",
                    message: error.localizedDescription
                )
            }
        }
    }

    @MainActor
    private func downloadAndInstallLatestRelease() async throws {
        let arch = Architecture.current.sparkleArch
        guard let downloadURL = URL(
            string: "https://github.com/hjy666-mc/Swift-Craft-Server-Launcher/releases/latest/download/SwiftCraftServerLauncher-\(arch).dmg"
        ) else {
            throw URLError(.badURL)
        }

        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("scsl-update-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)

        let dmgPath = tempRoot.appendingPathComponent("update.dmg")
        let mountPoint = tempRoot.appendingPathComponent("mount")
        let helperScript = tempRoot.appendingPathComponent("update-helper.sh")

        let (downloadedURL, response) = try await URLSession.shared.download(from: downloadURL)
        guard let httpResponse = response as? HTTPURLResponse, 200..<300 ~= httpResponse.statusCode else {
            throw URLError(.badServerResponse)
        }
        try FileManager.default.moveItem(at: downloadedURL, to: dmgPath)
        try writeHelperScript(to: helperScript)

        let appPath = Bundle.main.bundleURL.path
        let pid = String(getpid())

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = [
            helperScript.path,
            appPath,
            dmgPath.path,
            mountPoint.path,
            pid,
            tempRoot.path,
        ]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()

        NSApp.terminate(nil)
    }

    private func writeHelperScript(to scriptURL: URL) throws {
        let script = """
        #!/bin/zsh
        set -e

        APP_PATH="$1"
        DMG_PATH="$2"
        MOUNT_PATH="$3"
        WAIT_PID="$4"
        WORK_DIR="$5"
        APP_NAME="SwiftCraftServerLauncher.app"

        while kill -0 "$WAIT_PID" >/dev/null 2>&1; do
          sleep 1
        done

        mkdir -p "$MOUNT_PATH"
        hdiutil attach "$DMG_PATH" -mountpoint "$MOUNT_PATH" -nobrowse -quiet

        if test -d "$MOUNT_PATH/$APP_NAME"; then
          ditto "$MOUNT_PATH/$APP_NAME" "$APP_PATH"
        fi

        hdiutil detach "$MOUNT_PATH" -quiet || true
        open "$APP_PATH"
        rm -rf "$WORK_DIR"
        """
        try script.write(to: scriptURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)
    }

    @MainActor
    private func showAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: "确定")
        alert.runModal()
    }
}
