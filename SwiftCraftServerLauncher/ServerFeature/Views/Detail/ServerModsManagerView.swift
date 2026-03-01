import SwiftUI
import UniformTypeIdentifiers

struct ServerModsManagerView: View {
    let server: ServerInstance
    @Environment(\.dismiss)
    private var dismiss
    @State private var files: [URL] = []
    @State private var showImporter = false

    var body: some View {
        CommonSheetView(
            header: {
                HStack {
                    Text("server.mods.title".localized())
                        .font(.headline)
                    Spacer()
                    Button("server.mods.import".localized()) { showImporter = true }
                }
            },
            body: {
                if files.isEmpty {
                    Text("common.empty".localized())
                        .foregroundColor(.secondary)
                } else {
                    List {
                        ForEach(files, id: \.self) { url in
                            HStack {
                                Text(url.lastPathComponent)
                                Spacer()
                                Button("common.remove".localized()) { removeFile(url) }
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
                    Button("common.reload".localized()) { loadFiles() }
                }
            }
        )
        .frame(minWidth: 760, minHeight: 520)
        .onAppear { loadFiles() }
        .fileImporter(
            isPresented: $showImporter,
            allowedContentTypes: [.zip, UTType(filenameExtension: "jar") ?? .data],
            allowsMultipleSelection: true
        ) { result in
            if case .success(let urls) = result {
                addFiles(urls)
            }
        }
    }

    private func modsDir() -> URL {
        AppPaths.serverModsDirectory(serverName: server.name)
    }

    private func loadFiles() {
        let dir = modsDir()
        let all = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
        files = all.filter { $0.pathExtension.lowercased() == "jar" }
    }

    private func addFiles(_ urls: [URL]) {
        let dir = modsDir()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        for url in urls {
            guard url.startAccessingSecurityScopedResource() else { continue }
            defer { url.stopAccessingSecurityScopedResource() }
            if url.pathExtension.lowercased() == "zip" {
                unzip(url: url, to: dir)
            } else {
                let target = dir.appendingPathComponent(url.lastPathComponent)
                try? FileManager.default.removeItem(at: target)
                try? FileManager.default.copyItem(at: url, to: target)
            }
        }
        loadFiles()
    }

    private func unzip(url: URL, to destination: URL) {
        let tempDir = destination.appendingPathComponent(".import_tmp_\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = ["-o", url.path, "-d", tempDir.path]
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            GlobalErrorHandler.shared.handle(error)
            try? FileManager.default.removeItem(at: tempDir)
            return
        }

        let enumerator = FileManager.default.enumerator(at: tempDir, includingPropertiesForKeys: nil)
        while let fileURL = enumerator?.nextObject() as? URL {
            if fileURL.pathExtension.lowercased() == "jar" {
                let target = destination.appendingPathComponent(fileURL.lastPathComponent)
                try? FileManager.default.removeItem(at: target)
                try? FileManager.default.moveItem(at: fileURL, to: target)
            }
        }
        try? FileManager.default.removeItem(at: tempDir)
    }

    private func removeFile(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
        loadFiles()
    }
}
