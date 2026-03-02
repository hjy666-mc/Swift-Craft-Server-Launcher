import SwiftUI
import UniformTypeIdentifiers

@MainActor
class ServerCreationViewModel: ObservableObject {
    @Published var isDownloading: Bool = false
    @Published var isFormValid: Bool = false
    @Published var triggerConfirm: Bool = false
    @Published var triggerCancel: Bool = false

    @Published var selectedServerType: ServerType = .vanilla
    @Published var selectedGameVersion: String = ""
    @Published var versionTime: String = ""
    @Published var selectedLoaderVersion: String = ""
    @Published var availableLoaderVersions: [String] = []
    @Published var availableVersions: [String] = []

    @Published var customJarURL: URL?
    @Published var hasAcceptedEula: Bool = false
    @Published var consoleMode: ServerConsoleMode = .rcon
    @Published var rconPortText: String = "25575"
    @Published var rconPassword: String = ""
    @Published private(set) var isRemoteNode: Bool = false

    let serverSetupService = ServerSetupUtil()
    let serverNameValidator: ServerNameValidator

    private var serverRepository: ServerRepository?
    private var didInit = false
    private var isSubmitting = false
    private let configuration: GameFormConfiguration
    private let selectedNode: ServerNode

    init(configuration: GameFormConfiguration, selectedNode: ServerNode = .local) {
        self.configuration = configuration
        self.selectedNode = selectedNode
        self.isRemoteNode = !selectedNode.isLocal
        self.serverNameValidator = ServerNameValidator(serverSetupService: serverSetupService)
        updateParentState()
    }

    func setup(serverRepository: ServerRepository) {
        self.serverRepository = serverRepository
        if !didInit {
            didInit = true
            Task { await initializeVersionPicker() }
        }
        updateParentState()
    }

    func handleConfirm() {
        Task { await performConfirmAction() }
    }

    func handleCancel() {
        configuration.actions.onCancel()
    }

    func updateParentState() {
        let newIsDownloading = serverSetupService.downloadState.isDownloading
        let newIsFormValid = computeIsFormValid()

        DispatchQueue.main.async { [weak self] in
            self?.configuration.isDownloading.wrappedValue = newIsDownloading
            self?.configuration.isFormValid.wrappedValue = newIsFormValid
            self?.isDownloading = newIsDownloading
            self?.isFormValid = newIsFormValid
        }
    }

    private func computeIsFormValid() -> Bool {
        if !serverNameValidator.isFormValid { return false }
        if !hasAcceptedEula { return false }
        if isRemoteNode && consoleMode == .rcon {
            guard !rconPassword.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
            guard let port = Int(rconPortText), port > 0, port <= 65535 else { return false }
        }
        switch selectedServerType {
        case .custom:
            return customJarURL != nil
        case .fabric, .forge:
            return !selectedGameVersion.isEmpty && !selectedLoaderVersion.isEmpty
        case .vanilla, .paper:
            return !selectedGameVersion.isEmpty
        }
    }

    private func performConfirmAction() async {
        if isSubmitting { return }
        isSubmitting = true
        defer { isSubmitting = false }

        guard let serverRepository = serverRepository else { return }
        let name = serverNameValidator.serverName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        let isDuplicate = await serverSetupService.checkServerNameDuplicate(name)
        if isDuplicate || serverRepository.getServerByName(by: name) != nil {
            handleDuplicateName()
            return
        }

        do {
            await MainActor.run {
                serverSetupService.downloadState.reset()
                serverSetupService.downloadState.isDownloading = true
            }
            defer {
                Task { @MainActor in
                    self.serverSetupService.downloadState.reset()
                    self.serverSetupService.downloadState.isDownloading = false
                }
            }

            var serverJar = "server.jar"
            let javaPath: String
            if selectedNode.isLocal {
                let serverDir = try serverSetupService.createServerDirectory(name: name)
                if selectedServerType == .custom, let url = customJarURL {
                    guard url.startAccessingSecurityScopedResource() else {
                        throw GlobalError.fileSystem(
                            chineseMessage: "无法访问自定义 Jar 文件",
                            i18nKey: "error.filesystem.file_access_failed",
                            level: .notification
                        )
                    }
                    defer { url.stopAccessingSecurityScopedResource() }
                    serverJar = try serverSetupService.copyCustomJar(from: url, to: serverDir)
                } else {
                    serverJar = try await ServerDownloadService.downloadServerJar(
                        serverType: selectedServerType,
                        gameVersion: selectedGameVersion,
                        loaderVersion: selectedLoaderVersion,
                        serverDir: serverDir
                    )
                }
                try serverSetupService.acceptEula(in: serverDir)
                let javaComponent = try await ServerDownloadService.resolveJavaComponent(gameVersion: selectedGameVersion)
                javaPath = await JavaManager.shared.ensureJavaExists(version: javaComponent)

                if selectedServerType == .forge {
                    let tempServer = ServerInstance(
                        name: name,
                        serverType: selectedServerType,
                        gameVersion: selectedGameVersion,
                        loaderVersion: selectedLoaderVersion,
                        serverJar: serverJar,
                        javaPath: javaPath,
                        nodeId: selectedNode.id
                    )
                    try await ForgeInstallerService.install(server: tempServer, serverDir: serverDir)
                }
            } else {
                if selectedServerType == .custom {
                    throw GlobalError.validation(
                        chineseMessage: "远程节点暂不支持上传自定义 Jar",
                        i18nKey: "error.validation.server_not_selected",
                        level: .notification
                    )
                }
                if selectedServerType == .forge {
                    throw GlobalError.validation(
                        chineseMessage: "远程节点暂不支持 Forge 安装流程",
                        i18nKey: "error.validation.server_not_selected",
                        level: .notification
                    )
                }
                let target = try await ServerDownloadService.resolveDownloadTargetForRemote(
                    serverType: selectedServerType,
                    gameVersion: selectedGameVersion,
                    loaderVersion: selectedLoaderVersion
                )
                try await SSHNodeService.prepareRemoteServerDirectoryAndDownload(
                    node: selectedNode,
                    serverName: name,
                    target: target
                )
                serverJar = target.fileName
                javaPath = "java"
            }

            let server = ServerInstance(
                name: name,
                serverType: selectedServerType,
                gameVersion: selectedGameVersion,
                loaderVersion: selectedLoaderVersion,
                serverJar: serverJar,
                javaPath: javaPath,
                nodeId: selectedNode.id,
                consoleMode: consoleMode,
                rconPort: Int(rconPortText) ?? 25575,
                rconPassword: rconPassword.trimmingCharacters(in: .whitespacesAndNewlines)
            )

            serverRepository.addServerSilently(server)
            configuration.actions.onCancel()
        } catch {
            if selectedNode.isLocal {
                let serverDir = AppPaths.serverDirectory(serverName: name)
                if FileManager.default.fileExists(atPath: serverDir.path) {
                    try? FileManager.default.removeItem(at: serverDir)
                }
            }
            GlobalErrorHandler.shared.handle(error)
        }
    }

    private func handleDuplicateName() {
        let error = GlobalError.validation(
            chineseMessage: "服务器名称已存在",
            i18nKey: "error.validation.server_name_duplicate",
            level: .notification
        )
        Logger.shared.error(error.chineseMessage)
        GlobalErrorHandler.shared.handle(error)
    }

    func initializeVersionPicker() async {
        await refreshAvailableVersions(for: selectedServerType)
    }

    func updateAvailableVersions(_ versions: [String]) async {
        self.availableVersions = versions
        if !versions.contains(self.selectedGameVersion) && !versions.isEmpty {
            self.selectedGameVersion = versions.first ?? ""
        }

        if !versions.isEmpty {
            let targetVersion = versions.contains(self.selectedGameVersion) ? self.selectedGameVersion : (versions.first ?? "")
            let timeString = await ModrinthService.queryVersionTime(from: targetVersion)
            self.versionTime = timeString
        }
    }

    func handleServerTypeChange(_ newType: ServerType) {
        selectedServerType = newType
        selectedLoaderVersion = ""
        Task {
            await refreshAvailableVersions(for: newType)

            if requiresLoaderVersion(newType), !selectedGameVersion.isEmpty {
                await updateLoaderVersions(for: newType, gameVersion: selectedGameVersion)
            } else {
                await MainActor.run {
                    availableLoaderVersions = []
                    selectedLoaderVersion = ""
                }
            }
        }
    }

    private func refreshAvailableVersions(for type: ServerType) async {
        let includeSnapshots = GameSettingsManager.shared.includeSnapshotsForGameVersions
        do {
            let versions = try await ServerDownloadService.fetchAvailableGameVersions(
                serverType: type,
                includeSnapshots: includeSnapshots
            )
            await updateAvailableVersions(versions)
        } catch {
            Logger.shared.error("获取服务端版本失败: \(error.localizedDescription)")
            await updateAvailableVersions([])
            GlobalErrorHandler.shared.handle(error)
        }
    }

    func handleGameVersionChange(_ newVersion: String) {
        Task {
            if requiresLoaderVersion(selectedServerType) {
                await updateLoaderVersions(for: selectedServerType, gameVersion: newVersion)
            }
        }
    }

    private func requiresLoaderVersion(_ type: ServerType) -> Bool {
        switch type {
        case .fabric, .forge:
            return true
        default:
            return false
        }
    }

    private func updateLoaderVersions(for type: ServerType, gameVersion: String) async {
        guard requiresLoaderVersion(type), !gameVersion.isEmpty else {
            availableLoaderVersions = []
            selectedLoaderVersion = ""
            return
        }

        var versions: [String] = []

        switch type {
        case .fabric:
            let fabricVersions = await FabricLoaderService.fetchAllLoaderVersions(for: gameVersion)
            versions = fabricVersions.map { $0.loader.version }
        case .forge:
            do {
                let forgeVersions = try await ForgeLoaderService.fetchAllForgeVersions(for: gameVersion)
                versions = forgeVersions.loaders.map { $0.id }
            } catch {
                Logger.shared.error("获取 Forge 版本失败: \(error.localizedDescription)")
                versions = []
            }
        default:
            versions = []
        }

        availableLoaderVersions = versions
        if versions.isEmpty {
            selectedLoaderVersion = ""
            return
        }

        switch type {
        case .fabric:
            if let stable = try? await ServerDownloadService.latestStableFabricLoaderVersion(gameVersion: gameVersion),
               versions.contains(stable) {
                selectedLoaderVersion = stable
            } else if !versions.contains(selectedLoaderVersion) {
                selectedLoaderVersion = versions.first ?? ""
            }
        case .forge:
            if let stable = try? await ServerDownloadService.latestStableForgeVersion(gameVersion: gameVersion),
               versions.contains(stable) {
                selectedLoaderVersion = stable
            } else if !versions.contains(selectedLoaderVersion) {
                selectedLoaderVersion = versions.first ?? ""
            }
        default:
            if !versions.contains(selectedLoaderVersion) {
                selectedLoaderVersion = versions.first ?? ""
            }
        }
    }
}
