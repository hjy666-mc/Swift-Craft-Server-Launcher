import SwiftUI
import AppKit

struct ServerLogManagerView: View {
    let server: ServerInstance
    @State private var crashReports: [URL] = []
    @State private var logArchives: [URL] = []
    @State private var loadError: String?

    private var isRemoteServer: Bool {
        server.nodeId != ServerNode.local.id
    }

    var body: some View {
        ServerDetailPage(title: "server.logs.title".localized()) {
            VStack(alignment: .leading, spacing: 12) {
                if isRemoteServer {
                    ServerDetailEmptyState(text: "server.logs.remote_hint".localized())
                } else if let loadError {
                    ServerDetailEmptyState(text: loadError)
                } else if crashReports.isEmpty && logArchives.isEmpty {
                    ServerDetailEmptyState(text: "server.logs.empty".localized())
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            logSection(
                                titleKey: "server.logs.section.crash_reports",
                                files: crashReports,
                                emptyKey: "server.logs.empty.crash_reports"
                            )
                            logSection(
                                titleKey: "server.logs.section.archives",
                                files: logArchives,
                                emptyKey: "server.logs.empty.archives"
                            )
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
        }
        .onAppear { loadLogs() }
        .onChange(of: server.id) { _, _ in
            loadLogs()
        }
    }

    private func logRow(_ url: URL) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "doc.text")
                .foregroundStyle(.secondary)
            Text(url.lastPathComponent)
                .lineLimit(1)
            Spacer()
            Button("server.logs.open_folder".localized()) {
                NSWorkspace.shared.activateFileViewerSelecting([url])
            }
            .buttonStyle(.borderless)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .contentShape(Rectangle())
    }

    private func logSection(
        titleKey: String,
        files: [URL],
        emptyKey: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(titleKey.localized())
                .font(.headline)
            if files.isEmpty {
                Text(emptyKey.localized())
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                LazyVStack(spacing: 0) {
                    ForEach(files, id: \.path) { url in
                        logRow(url)
                        if url != files.last {
                            Divider()
                        }
                    }
                }
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color(.windowBackgroundColor).opacity(0.3))
                )
            }
        }
    }

    private func loadLogs() {
        guard !isRemoteServer else {
            crashReports = []
            logArchives = []
            loadError = nil
            return
        }
        let baseDir = AppPaths.serverDirectory(serverName: server.name)
        let logDir = baseDir.appendingPathComponent("logs", isDirectory: true)
        let crashDir = baseDir.appendingPathComponent("crash-reports", isDirectory: true)
        crashReports = loadFiles(in: crashDir)
        logArchives = loadFiles(in: logDir).filter { url in
            let ext = url.pathExtension.lowercased()
            return ext == "gz" || ext == "zip"
        }
        loadError = nil
    }

    private func loadFiles(in directory: URL) -> [URL] {
        guard FileManager.default.fileExists(atPath: directory.path) else {
            return []
        }
        let files = (try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )) ?? []
        return files.sorted { lhs, rhs in
            let ldate = (try? lhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            let rdate = (try? rhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            return ldate > rdate
        }
    }
}
