import SwiftUI
import UniformTypeIdentifiers

@MainActor
class ServerCreationViewModel: ObservableObject {
    @Published var isDownloading: Bool = false
    @Published var isFormValid: Bool = false
    @Published var triggerConfirm: Bool = false
    @Published var triggerCancel: Bool = false

    @Published var selectedServerType: ServerType = .vanilla
    @Published var selectedServerIcon: String = "server.rack"
    @Published var selectedServerIconURL: URL?
    @Published var selectedGameVersion: String = ""
    @Published var versionTime: String = ""
    @Published var selectedLoaderVersion: String = ""
    @Published var availableLoaderVersions: [String] = []
    @Published var availableVersions: [String] = []
    @Published var selectedMirrorSource: ServerMirrorSource = .official
    @Published var fastMirrorCores: [FastMirrorService.CoreSummary] = []
    @Published var selectedFastMirrorCoreName: String = ""
    @Published var polarsCoreTypes: [PolarsMirrorService.CoreType] = []
    @Published var selectedPolarsCoreTypeId: Int?
    @Published var polarsCoreItems: [PolarsMirrorService.CoreItem] = []
    @Published var selectedPolarsCoreItemName: String = ""
    @Published var selectedMirrorDownloadURL: String = ""

    @Published var customJarURL: URL?
    @Published var hasAcceptedEula: Bool = false
    @Published var consoleMode: ServerConsoleMode = .direct
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
        configuration.actions.onConfirm()
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
        if selectedMirrorSource == .fastMirror, selectedServerType != .custom {
            return !selectedFastMirrorCoreName.isEmpty && !selectedGameVersion.isEmpty && !selectedLoaderVersion.isEmpty
        }
        if selectedMirrorSource == .polars {
            return selectedPolarsCoreTypeId != nil && !selectedPolarsCoreItemName.isEmpty && !selectedMirrorDownloadURL.isEmpty
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
        let spinnerWatchdog = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 45_000_000_000)
            await MainActor.run {
                guard let self, self.isSubmitting else { return }
                self.serverSetupService.downloadState.reset()
                self.serverSetupService.downloadState.isDownloading = false
                self.isSubmitting = false
                self.updateParentState()
                Logger.shared.warning("服务器创建超时，自动结束加载状态")
            }
        }
        defer {
            spinnerWatchdog.cancel()
            isSubmitting = false
        }

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
                self.serverSetupService.downloadState.reset()
                self.serverSetupService.downloadState.isDownloading = false
                self.updateParentState()
            }

            var serverJar = "server.jar"
            let javaPath: String
            let iconImageFileName: String?
            if selectedNode.isLocal {
                let serverDir = try serverSetupService.createServerDirectory(name: name)
                iconImageFileName = try persistServerIconIfNeeded(serverName: name, baseDirectory: serverDir)
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
                    // 自定义 Jar 不强依赖版本元数据，延迟到启动时再解析/回退 Java。
                    javaPath = ""
                } else {
                    if selectedMirrorSource == .polars {
                        serverJar = try await ServerDownloadService.downloadMirrorJar(
                            downloadURL: selectedMirrorDownloadURL,
                            fileName: selectedMirrorFileName,
                            serverDir: serverDir
                        )
                        javaPath = ""
                    } else {
                        serverJar = try await ServerDownloadService.downloadServerJar(
                            serverType: selectedServerType,
                            gameVersion: selectedGameVersion,
                            loaderVersion: selectedLoaderVersion,
                            serverDir: serverDir,
                            mirror: ServerDownloadService.MirrorDownloadOptions(
                                source: selectedMirrorSource,
                                coreName: selectedFastMirrorCoreName
                            )
                        )
                        let javaComponent = try await ServerDownloadService.resolveJavaComponent(gameVersion: selectedGameVersion)
                        javaPath = await JavaManager.shared.ensureJavaExists(version: javaComponent)
                    }
                }
                if hasAcceptedEula {
                    try serverSetupService.acceptEula(in: serverDir)
                }

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
                let localRemoteServerDir = AppPaths.remoteNodeServersDirectory(nodeId: selectedNode.id)
                    .appendingPathComponent(name, isDirectory: true)
                try? FileManager.default.createDirectory(at: localRemoteServerDir, withIntermediateDirectories: true)
                iconImageFileName = try persistServerIconIfNeeded(serverName: name, baseDirectory: localRemoteServerDir)
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
                    loaderVersion: selectedLoaderVersion,
                    mirror: ServerDownloadService.MirrorDownloadOptions(
                        source: selectedMirrorSource,
                        coreName: selectedFastMirrorCoreName,
                        fileName: selectedMirrorFileName,
                        downloadURL: selectedMirrorDownloadURL
                    )
                )
                let alreadyPrepared = await SSHNodeService.waitForRemoteServerJar(
                    node: selectedNode,
                    serverName: name,
                    expectedJarName: target.fileName,
                    timeoutSeconds: 4,
                    pollIntervalSeconds: 2
                )

                if !alreadyPrepared {
                    _ = await prepareRemoteServerWithTimeout(
                        node: selectedNode,
                        serverName: name,
                        target: target
                    )
                }

                let hasJar = await SSHNodeService.waitForRemoteServerJar(
                    node: selectedNode,
                    serverName: name,
                    expectedJarName: target.fileName,
                    timeoutSeconds: 12,
                    pollIntervalSeconds: 2
                )
                guard hasJar else {
                    throw GlobalError.validation(
                        chineseMessage: "远程目录未检测到 Jar，请检查节点路径与下载权限",
                        i18nKey: "error.validation.server_not_selected",
                        level: .notification
                    )
                }
                serverJar = target.fileName
                javaPath = "java"
            }

            let server = ServerInstance(
                name: name,
                iconName: selectedServerIcon,
                iconImageFileName: iconImageFileName,
                serverType: resolvedServerType(),
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

    private func persistServerIconIfNeeded(serverName: String, baseDirectory: URL) throws -> String? {
        guard let selectedServerIconURL else {
            return nil
        }
        let didAccessSecurityScoped = selectedServerIconURL.startAccessingSecurityScopedResource()
        defer {
            if didAccessSecurityScoped {
                selectedServerIconURL.stopAccessingSecurityScopedResource()
            }
        }

        let ext = selectedServerIconURL.pathExtension.isEmpty ? "png" : selectedServerIconURL.pathExtension.lowercased()
        let fileName = ".scsl-server-icon.\(ext)"
        let destination = baseDirectory.appendingPathComponent(fileName)
        if FileManager.default.fileExists(atPath: destination.path) {
            try? FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.copyItem(at: selectedServerIconURL, to: destination)
        return fileName
    }

    private func prepareRemoteServerWithTimeout(
        node: ServerNode,
        serverName: String,
        target: ServerDownloadService.DownloadTarget
    ) async -> Bool {
        let timeoutSeconds: UInt64 = 20
        return await withTaskGroup(of: Bool.self) { group in
            group.addTask {
                do {
                    try await SSHNodeService.prepareRemoteServerDirectoryAndDownload(
                        node: node,
                        serverName: serverName,
                        target: target
                    )
                    return true
                } catch {
                    let message = GlobalError.from(error).chineseMessage
                    Logger.shared.warning("远程下载异常，转入目录检测: \(message)")
                    return false
                }
            }
            group.addTask {
                try? await Task.sleep(nanoseconds: timeoutSeconds * 1_000_000_000)
                Logger.shared.warning("远程下载确认超时，转入目录检测: \(serverName)")
                return false
            }

            if let result = await group.next() {
                group.cancelAll()
                return result
            }
            return false
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
            if selectedMirrorSource == .fastMirror {
                self.versionTime = ""
            } else {
                let targetVersion = versions.contains(self.selectedGameVersion) ? self.selectedGameVersion : (versions.first ?? "")
                let timeString = await ModrinthService.queryVersionTime(from: targetVersion)
                self.versionTime = timeString
            }
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

    func handleMirrorSourceChange(_ newSource: ServerMirrorSource) {
        if newSource == .fastMirror {
            resetMirrorSelections()
            if selectedServerType == .custom {
                selectedServerType = .vanilla
            }
            Task {
                await loadFastMirrorCores()
                await refreshAvailableVersions(for: selectedServerType)
            }
            return
        }
        if newSource == .polars {
            resetMirrorSelections()
            Task { await loadPolarsCoreTypes() }
            return
        }
        resetMirrorSelections()
        selectedLoaderVersion = ""
        availableLoaderVersions = []
        Task {
            await refreshAvailableVersions(for: selectedServerType)
            if requiresLoaderVersion(selectedServerType), !selectedGameVersion.isEmpty {
                await updateLoaderVersions(for: selectedServerType, gameVersion: selectedGameVersion)
            }
        }
    }

    private func refreshAvailableVersions(for type: ServerType) async {
        let includeSnapshots = GameSettingsManager.shared.includeSnapshotsForGameVersions
        do {
            let versions: [String]
            if selectedMirrorSource == .fastMirror {
                guard !selectedFastMirrorCoreName.isEmpty else {
                    await updateAvailableVersions([])
                    return
                }
                versions = try await FastMirrorService.fetchGameVersions(coreName: selectedFastMirrorCoreName)
            } else if selectedMirrorSource == .polars {
                await updateAvailableVersions([])
                return
            } else {
                versions = try await ServerDownloadService.fetchAvailableGameVersions(
                    serverType: type,
                    includeSnapshots: includeSnapshots
                )
            }
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
        if selectedMirrorSource == .fastMirror {
            return type != .custom
        }
        if selectedMirrorSource == .polars {
            return false
        }
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

        if selectedMirrorSource == .fastMirror {
            do {
                guard !selectedFastMirrorCoreName.isEmpty else {
                    versions = []
                    throw GlobalError.resource(
                        chineseMessage: "未选择核心",
                        i18nKey: "error.resource.not_found",
                        level: .notification
                    )
                }
                versions = try await FastMirrorService.fetchCoreVersions(
                    coreName: selectedFastMirrorCoreName,
                    gameVersion: gameVersion
                )
            } catch {
                Logger.shared.error("获取镜像核心版本失败: \(error.localizedDescription)")
                versions = []
            }
        } else {
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
        }

        availableLoaderVersions = versions
        if versions.isEmpty {
            selectedLoaderVersion = ""
            return
        }

        if selectedMirrorSource == .fastMirror {
            if !versions.contains(selectedLoaderVersion) {
                selectedLoaderVersion = versions.first ?? ""
            }
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

    func handleFastMirrorCoreChange(_ newCoreName: String) {
        selectedFastMirrorCoreName = newCoreName
        if let mapped = FastMirrorService.serverType(for: newCoreName) {
            selectedServerType = mapped
        }
        selectedGameVersion = ""
        selectedLoaderVersion = ""
        availableLoaderVersions = []
        Task {
            await refreshAvailableVersions(for: selectedServerType)
        }
    }

    private func loadFastMirrorCores() async {
        do {
            let cores = try await FastMirrorService.fetchCores()
            let filtered = cores
            await MainActor.run {
                fastMirrorCores = filtered
                if selectedFastMirrorCoreName.isEmpty, let first = filtered.first?.name {
                    handleFastMirrorCoreChange(first)
                } else if !selectedFastMirrorCoreName.isEmpty,
                          !filtered.contains(where: { $0.name == selectedFastMirrorCoreName }),
                          let first = filtered.first?.name {
                    handleFastMirrorCoreChange(first)
                }
            }
        } catch {
            Logger.shared.error("获取镜像核心失败: \(error.localizedDescription)")
            await MainActor.run {
                fastMirrorCores = []
                selectedFastMirrorCoreName = ""
            }
        }
    }

    func handlePolarsCoreTypeChange(_ typeId: Int) {
        selectedPolarsCoreTypeId = typeId
        selectedPolarsCoreItemName = ""
        selectedMirrorDownloadURL = ""
        polarsCoreItems = []
        Task { await loadPolarsCoreItems(typeId: typeId) }
    }

    func handlePolarsCoreItemChange(_ item: PolarsMirrorService.CoreItem) {
        selectedPolarsCoreItemName = item.name
        selectedMirrorDownloadURL = item.downloadURL
    }

    private func loadPolarsCoreTypes() async {
        do {
            let types = try await PolarsMirrorService.fetchCoreTypes()
            await MainActor.run {
                polarsCoreTypes = types
                if selectedPolarsCoreTypeId == nil, let first = types.first?.id {
                    handlePolarsCoreTypeChange(first)
                }
            }
        } catch {
            Logger.shared.error("获取极星核心类型失败: \(error.localizedDescription)")
            await MainActor.run {
                polarsCoreTypes = []
                selectedPolarsCoreTypeId = nil
            }
        }
    }

    private func loadPolarsCoreItems(typeId: Int) async {
        do {
            let items = try await PolarsMirrorService.fetchCoreItems(coreTypeId: typeId)
            await MainActor.run {
                polarsCoreItems = items
                if selectedPolarsCoreItemName.isEmpty, let first = items.first {
                    handlePolarsCoreItemChange(first)
                }
            }
        } catch {
            Logger.shared.error("获取极星核心列表失败: \(error.localizedDescription)")
            await MainActor.run {
                polarsCoreItems = []
                selectedPolarsCoreItemName = ""
                selectedMirrorDownloadURL = ""
            }
        }
    }

    private func resetMirrorSelections() {
        selectedFastMirrorCoreName = ""
        fastMirrorCores = []
        selectedPolarsCoreTypeId = nil
        polarsCoreTypes = []
        polarsCoreItems = []
        selectedPolarsCoreItemName = ""
        selectedMirrorDownloadURL = ""
    }

    private var selectedMirrorFileName: String {
        switch selectedMirrorSource {
        case .polars:
            return selectedPolarsCoreItemName
        default:
            return ""
        }
    }

    private func resolvedServerType() -> ServerType {
        if selectedMirrorSource == .fastMirror,
           let mapped = FastMirrorService.serverType(for: selectedFastMirrorCoreName) {
            return mapped
        }
        if selectedMirrorSource == .polars,
           let type = polarsCoreTypes.first(where: { $0.id == selectedPolarsCoreTypeId })?.name,
           let mapped = FastMirrorService.serverType(for: type) {
            return mapped
        }
        return selectedServerType
    }
}
