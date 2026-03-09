import Foundation

@MainActor
final class BackupService: ObservableObject {
    static let shared = BackupService()

    private var timer: Timer?
    private let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter
    }()

    private init() {}

    func startAutoBackupScheduler() {
        reloadAutoBackupScheduler()
    }

    func reloadAutoBackupScheduler() {
        timer?.invalidate()
        timer = nil

        let settings = GeneralSettingsManager.shared
        guard settings.backupAutoEnabled else { return }

        let interval = TimeInterval(max(5, settings.backupIntervalMinutes) * 60)
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { _ in
            Task { @MainActor in
                do {
                    _ = try await self.createBackup(reason: "auto")
                } catch {
                    Logger.shared.error("自动备份失败: \(error.localizedDescription)")
                }
            }
        }
    }

    func createBackup(reason: String) async throws -> URL {
        let settings = GeneralSettingsManager.shared
        let fileManager = FileManager.default

        // 仅备份 servers 目录，避免把整个工作目录都打包进去。
        let sourceRoot = AppPaths.serverRootDirectory
        if !fileManager.fileExists(atPath: sourceRoot.path) {
            try fileManager.createDirectory(at: sourceRoot, withIntermediateDirectories: true)
        }

        let backupRoot = resolvedBackupDirectory()
        try fileManager.createDirectory(at: backupRoot, withIntermediateDirectories: true)

        let timestamp = formatter.string(from: Date())
        let outputURL = backupRoot.appendingPathComponent(
            "swiftcraft-backup-\(reason)-\(timestamp).zip",
            isDirectory: false
        )

        if fileManager.fileExists(atPath: outputURL.path) {
            try fileManager.removeItem(at: outputURL)
        }

        try await archiveDirectory(sourceRoot: sourceRoot, outputURL: outputURL)
        try pruneBackups(keepCount: settings.backupKeepCount, backupRoot: backupRoot)

        settings.backupLastTimestamp = Date().timeIntervalSince1970
        Logger.shared.info("创建 servers 备份成功: \(outputURL.path)")
        return outputURL
    }

    func createBackupBeforeUpdateIfNeeded() async throws -> URL? {
        let settings = GeneralSettingsManager.shared
        guard settings.backupBeforeUpdate else { return nil }
        return try await createBackup(reason: "before-update")
    }

    private func resolvedBackupDirectory() -> URL {
        let settings = GeneralSettingsManager.shared
        let rawPath = settings.backupDirectoryPath.trimmingCharacters(in: .whitespacesAndNewlines)
        if rawPath.isEmpty {
            return AppPaths.launcherSupportDirectory.appendingPathComponent("backups", isDirectory: true)
        }
        return URL(fileURLWithPath: rawPath, isDirectory: true)
    }

    private func archiveDirectory(sourceRoot: URL, outputURL: URL) async throws {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            let stderrPipe = Pipe()

            process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
            process.arguments = [
                "-c",
                "-k",
                "--keepParent",
                sourceRoot.path,
                outputURL.path,
            ]
            process.standardError = stderrPipe

            process.terminationHandler = { process in
                let errorData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
                let errorOutput = String(data: errorData, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

                if process.terminationStatus == 0 {
                    continuation.resume()
                } else {
                    let message = errorOutput.isEmpty
                        ? "ditto 备份失败，退出码: \(process.terminationStatus)"
                        : errorOutput
                    continuation.resume(
                        throwing: NSError(
                            domain: "BackupService",
                            code: Int(process.terminationStatus),
                            userInfo: [NSLocalizedDescriptionKey: message]
                        )
                    )
                }
            }

            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    private func pruneBackups(keepCount: Int, backupRoot: URL) throws {
        let fileManager = FileManager.default
        let files = try fileManager.contentsOfDirectory(
            at: backupRoot,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )
        .filter { $0.pathExtension.lowercased() == "zip" }
        .sorted { lhs, rhs in
            let lDate = (try? lhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            let rDate = (try? rhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            return lDate > rDate
        }

        if files.count <= keepCount { return }
        for oldFile in files.dropFirst(keepCount) {
            try? fileManager.removeItem(at: oldFile)
        }
    }
}
