import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct ServerWorldsManagerView: View {
    let server: ServerInstance
    @Environment(\.dismiss)
    private var dismiss
    @EnvironmentObject var serverNodeRepository: ServerNodeRepository
    @State private var folders: [URL] = []
    @State private var remoteFolders: [String] = []
    @State private var showImporter = false

    var body: some View {
        CommonSheetView(
            header: {
                HStack {
                    Text("server.worlds.title".localized())
                        .font(.headline)
                    Spacer()
                    Button("server.worlds.open_folder".localized()) { openFolder() }
                    Button("server.worlds.import".localized()) { showImporter = true }
                }
            },
            body: {
                if isRemoteServer ? remoteFolders.isEmpty : folders.isEmpty {
                    Text("common.empty".localized())
                        .foregroundColor(.secondary)
                } else {
                    List {
                        if isRemoteServer {
                            ForEach(remoteFolders, id: \.self) { name in
                                HStack {
                                    Text(name)
                                    Spacer()
                                    Button("common.remove".localized()) { removeRemoteFolder(name) }
                                }
                            }
                        } else {
                            ForEach(folders, id: \.self) { url in
                                HStack {
                                    Text(url.lastPathComponent)
                                    Spacer()
                                    Button("common.remove".localized()) { removeFolder(url) }
                                }
                            }
                        }
                    }
                    .frame(minHeight: 420)
                }
            },
            footer: {
                HStack {
                    Button("common.close".localized()) { dismiss() }
                    Spacer()
                    Button("common.reload".localized()) { loadFolders() }
                }
            }
        )
        .frame(minWidth: 760, minHeight: 520)
        .onAppear { loadFolders() }
        .fileImporter(
            isPresented: $showImporter,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: true
        ) { result in
            if case .success(let urls) = result {
                if !isRemoteServer {
                    importWorlds(urls)
                }
            }
        }
    }

    private var isRemoteServer: Bool {
        server.nodeId != ServerNode.local.id || server.javaPath == "java"
    }

    private func worldDir() -> URL {
        AppPaths.serverDirectory(serverName: server.name)
    }

    private func loadFolders() {
        if isRemoteServer {
            Task {
                guard let node = serverNodeRepository.getNode(by: server.nodeId) else { return }
                if let list = try? await SSHNodeService.listRemoteWorlds(node: node, serverName: server.name) {
                    await MainActor.run { remoteFolders = list }
                }
            }
            return
        }
        let dir = worldDir()
        let urls = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.isDirectoryKey])) ?? []
        folders = urls.filter { url in
            (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
        }
        .filter { $0.lastPathComponent.hasPrefix("world") }
    }

    private func removeFolder(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
        loadFolders()
    }

    private func openFolder() {
        if isRemoteServer { return }
        let dir = worldDir()
        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: dir.path)
    }

    private func importWorlds(_ urls: [URL]) {
        if isRemoteServer { return }
        let dir = worldDir()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        for url in urls {
            guard url.startAccessingSecurityScopedResource() else { continue }
            defer { url.stopAccessingSecurityScopedResource() }
            let target = dir.appendingPathComponent(url.lastPathComponent)
            try? FileManager.default.removeItem(at: target)
            try? FileManager.default.copyItem(at: url, to: target)
        }
        loadFolders()
    }

    private func removeRemoteFolder(_ name: String) {
        guard let node = serverNodeRepository.getNode(by: server.nodeId) else { return }
        Task {
            do {
                try await SSHNodeService.removeRemoteWorld(node: node, serverName: server.name, worldName: name)
                await MainActor.run { loadFolders() }
            } catch {
                await MainActor.run { GlobalErrorHandler.shared.handle(error) }
            }
        }
    }
}
