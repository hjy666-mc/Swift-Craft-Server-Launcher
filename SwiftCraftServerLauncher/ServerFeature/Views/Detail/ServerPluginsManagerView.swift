import SwiftUI
import UniformTypeIdentifiers

struct ServerPluginsManagerView: View {
    let server: ServerInstance
    @EnvironmentObject var serverNodeRepository: ServerNodeRepository
    @State private var files: [URL] = []
    @State private var remoteFiles: [String] = []
    @State private var showImporter = false
    private let autoRefreshTimer = Timer.publish(every: 6, on: .main, in: .common).autoconnect()

    var body: some View {
        CommonSheetView(
            header: {
                HStack {
                    Text("server.plugins.title".localized())
                        .font(.headline)
                    Spacer()
                    Button("server.plugins.import".localized()) { showImporter = true }
                }
            },
            body: {
                if isRemoteServer ? remoteFiles.isEmpty : files.isEmpty {
                    Text("common.empty".localized())
                        .foregroundColor(.secondary)
                } else {
                    List {
                        if isRemoteServer {
                            ForEach(remoteFiles, id: \.self) { fileName in
                                HStack {
                                    Text(fileName)
                                    Spacer()
                                    Button("common.remove".localized()) { removeRemoteFile(fileName) }
                                }
                            }
                        } else {
                            ForEach(files, id: \.self) { url in
                                HStack {
                                    Text(url.lastPathComponent)
                                    Spacer()
                                    Button("common.remove".localized()) { removeFile(url) }
                                }
                            }
                        }
                    }
                    .frame(minHeight: 420)
                }
            },
            footer: {
                HStack {
                    Spacer()
                }
            }
        )
        .frame(minWidth: 760, minHeight: 520)
        .onAppear { loadFiles() }
        .onReceive(autoRefreshTimer) { _ in
            loadFiles()
        }
        .fileImporter(
            isPresented: $showImporter,
            allowedContentTypes: [UTType(filenameExtension: "jar") ?? .data],
            allowsMultipleSelection: true
        ) { result in
            if case .success(let urls) = result {
                addFiles(urls)
            }
        }
    }

    private var isRemoteServer: Bool {
        server.nodeId != ServerNode.local.id || server.javaPath == "java"
    }

    private func pluginsDir() -> URL {
        AppPaths.serverPluginsDirectory(serverName: server.name)
    }

    private func loadFiles() {
        if isRemoteServer {
            guard let node = serverNodeRepository.getNode(by: server.nodeId) else { return }
            Task {
                do {
                    let list = try await SSHNodeService.listRemotePlugins(node: node, serverName: server.name)
                    await MainActor.run { remoteFiles = list }
                } catch {
                    await MainActor.run { GlobalErrorHandler.shared.handle(error) }
                }
            }
            return
        }
        let dir = pluginsDir()
        let all = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
        files = all.filter { $0.pathExtension.lowercased() == "jar" }
    }

    private func addFiles(_ urls: [URL]) {
        if isRemoteServer {
            guard let node = serverNodeRepository.getNode(by: server.nodeId) else { return }
            Task {
                for url in urls where url.pathExtension.lowercased() == "jar" {
                    guard url.startAccessingSecurityScopedResource() else { continue }
                    defer { url.stopAccessingSecurityScopedResource() }
                    do {
                        try await SSHNodeService.uploadRemotePlugin(node: node, serverName: server.name, localURL: url)
                    } catch {
                        await MainActor.run { GlobalErrorHandler.shared.handle(error) }
                    }
                }
                await MainActor.run { loadFiles() }
            }
            return
        }
        let dir = pluginsDir()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        for url in urls {
            guard url.startAccessingSecurityScopedResource() else { continue }
            defer { url.stopAccessingSecurityScopedResource() }
            guard url.pathExtension.lowercased() == "jar" else { continue }
            let target = dir.appendingPathComponent(url.lastPathComponent)
            try? FileManager.default.removeItem(at: target)
            try? FileManager.default.copyItem(at: url, to: target)
        }
        loadFiles()
    }

    private func removeFile(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
        loadFiles()
    }

    private func removeRemoteFile(_ fileName: String) {
        guard let node = serverNodeRepository.getNode(by: server.nodeId) else { return }
        Task {
            do {
                try await SSHNodeService.removeRemotePlugin(node: node, serverName: server.name, fileName: fileName)
                await MainActor.run { loadFiles() }
            } catch {
                await MainActor.run { GlobalErrorHandler.shared.handle(error) }
            }
        }
    }
}
