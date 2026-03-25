import SwiftUI

private enum ServerDetailSection: String, CaseIterable, Identifiable {
    case console
    case serverConfig
    case players
    case worlds
    case mods
    case plugins

    var id: String { rawValue }
}

struct ServerLaunchCommandView: View {
    let server: ServerInstance
    @EnvironmentObject var serverRepository: ServerRepository
    @EnvironmentObject var serverNodeRepository: ServerNodeRepository
    @EnvironmentObject var detailState: ResourceDetailState
    @State private var customLaunchCommand: String = ""
    @State private var isDirty = false
    @State private var isVerifyingJar = false
    @State private var launchCommandAutoSaveTask: Task<Void, Never>?
    @Namespace private var sectionIndicatorNamespace
    private var isChinese: Bool {
        Locale.preferredLanguages.first?.hasPrefix("zh") == true
    }
    private var supportsMods: Bool {
        server.serverType == .fabric || server.serverType == .forge
    }
    private var supportsPlugins: Bool {
        server.serverType == .paper
    }
    private var currentSection: ServerDetailSection {
        let requested = ServerDetailSection(rawValue: detailState.serverPanelSection) ?? .console
        switch requested {
        case .mods where !supportsMods:
            return .console
        case .plugins where !supportsPlugins:
            return .console
        default:
            return requested
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "terminal")
                Text("server.launch.title".localized())
                    .font(.title2)
                Spacer()
            }

            TextField("server.launch.placeholder".localized(), text: $customLaunchCommand, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(2...6)
                .onChange(of: customLaunchCommand) { _, newValue in
                    isDirty = newValue != server.launchCommand
                    scheduleLaunchCommandAutoSave()
                }

            HStack {
                Text("server.launch.nogui_hint".localized())
                    .foregroundColor(.secondary)
            }

            HStack {
                Button {
                    verifyAndRepairJar()
                } label: {
                    Label(
                        isVerifyingJar
                            ? "server.launch.verify_jar.running".localized()
                            : "server.launch.verify_jar".localized(),
                        systemImage: "checkmark.shield"
                    )
                }
                .rotationEffect(.degrees(isVerifyingJar ? 360 : 0))
                .animation(.easeInOut(duration: 0.15), value: isVerifyingJar)
                .disabled(isVerifyingJar)
                Spacer()
            }

            Divider()

            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    sectionRow(
                        section: .console,
                        title: "server.console.title".localized(),
                        icon: "terminal"
                    )
                    sectionRow(
                        section: .serverConfig,
                        title: "server.launch.server_config".localized(),
                        icon: "slider.horizontal.3"
                    )
                    sectionRow(
                        section: .players,
                        title: "server.launch.players".localized(),
                        icon: "person.3"
                    )
                    sectionRow(
                        section: .worlds,
                        title: "server.launch.worlds".localized(),
                        icon: "globe.americas"
                    )
                    sectionRow(
                        section: .mods,
                        title: "server.launch.mods".localized(),
                        icon: "puzzlepiece.extension",
                        isEnabled: supportsMods,
                        disabledHint: "server.launch.hint.mods_only".localized()
                    )
                    sectionRow(
                        section: .plugins,
                        title: "server.launch.plugins".localized(),
                        icon: "powerplug",
                        isEnabled: supportsPlugins,
                        disabledHint: "server.launch.hint.plugins_only".localized()
                    )
                }
                .frame(width: 180, alignment: .topLeading)
            }

            Spacer()
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear {
            customLaunchCommand = server.launchCommand
            isDirty = false
            normalizeSelectedSectionIfNeeded()
        }
        .onChange(of: server.id) { _, _ in
            customLaunchCommand = server.launchCommand
            isDirty = false
            normalizeSelectedSectionIfNeeded()
        }
        .onChange(of: detailState.serverPanelSection) { _, _ in
            normalizeSelectedSectionIfNeeded()
        }
        .onChange(of: server.serverType) { _, _ in
            normalizeSelectedSectionIfNeeded()
        }
        .onDisappear {
            launchCommandAutoSaveTask?.cancel()
            saveLaunchCommandIfNeeded()
        }
    }

    private func sectionRow(
        section: ServerDetailSection,
        title: String,
        icon: String,
        isEnabled: Bool = true,
        disabledHint: String? = nil
    ) -> some View {
        let rowButton = Button {
            guard isEnabled else { return }
            withAnimation(.spring(response: 0.22, dampingFraction: 0.88)) {
                detailState.serverPanelSection = section.rawValue
            }
        } label: {
            HStack(spacing: 8) {
                if currentSection == section {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.accentColor)
                        .frame(width: 3, height: 16)
                        .matchedGeometryEffect(id: "server-section-indicator", in: sectionIndicatorNamespace)
                } else {
                    Color.clear
                        .frame(width: 3, height: 16)
                }
                Image(systemName: icon)
                    .frame(width: 16)
                Text(title)
                    .lineLimit(1)
                if !isEnabled, let disabledHint {
                    Text(disabledHint)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 8)
            .padding(.vertical, 7)
            .foregroundStyle(isEnabled ? (currentSection == section ? Color.primary : Color.secondary) : Color.secondary.opacity(0.6))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity, alignment: .leading)
        .opacity(isEnabled ? 1 : 0.65)
        .disabled(!isEnabled)

        return rowButton
    }

    private func normalizeSelectedSectionIfNeeded() {
        if currentSection == .mods, !supportsMods {
            detailState.serverPanelSection = ServerDetailSection.console.rawValue
            return
        }
        if currentSection == .plugins, !supportsPlugins {
            detailState.serverPanelSection = ServerDetailSection.console.rawValue
        }
    }

    private func scheduleLaunchCommandAutoSave() {
        launchCommandAutoSaveTask?.cancel()
        guard isDirty else { return }
        launchCommandAutoSaveTask = Task {
            try? await Task.sleep(nanoseconds: 700_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                saveLaunchCommandIfNeeded()
            }
        }
    }

    private func saveLaunchCommandIfNeeded() {
        guard isDirty else { return }
        var updated = server
        updated.launchCommand = customLaunchCommand.trimmingCharacters(in: .whitespacesAndNewlines)
        _ = serverRepository.updateServerSilently(updated)
        isDirty = false
    }

    private func verifyAndRepairJar() {
        guard server.serverType != .custom else {
            GlobalErrorHandler.shared.handle(
                GlobalError.validation(
                    chineseMessage: "自定义 Jar 无法自动校验与重下",
                    i18nKey: "server.launch.verify_jar.custom_unsupported",
                    level: .notification
                )
            )
            return
        }
        isVerifyingJar = true
        Task {
            defer { isVerifyingJar = false }
            do {
                let target = try await ServerDownloadService.resolveDownloadTargetForServer(server)
                if server.nodeId == ServerNode.local.id {
                    let ok = await ServerDownloadService.verifyLocalJarIntegrity(server: server)
                    if !ok {
                        let dir = AppPaths.serverDirectory(serverName: server.name)
                        _ = try await DownloadManager.downloadFile(
                            urlString: target.url.absoluteString,
                            destinationURL: dir.appendingPathComponent(target.fileName),
                            expectedSha1: target.sha1,
                            headers: target.headers
                        )
                    }
                } else {
                    guard let node = serverNodeRepository.getNode(by: server.nodeId) else {
                        throw GlobalError.validation(
                            chineseMessage: "未找到远程节点配置",
                            i18nKey: "server.console.remote_node_missing",
                            level: .notification
                        )
                    }
                    let ok = (try? await SSHNodeService.verifyRemoteJarIntegrity(
                        node: node,
                        serverName: server.name,
                        jarFileName: server.serverJar
                    )) ?? false
                    if !ok {
                        try await SSHNodeService.redownloadRemoteServerJar(
                            node: node,
                            serverName: server.name,
                            target: target
                        )
                    }
                }
                GlobalErrorHandler.shared.handle(
                    GlobalError.validation(
                        chineseMessage: "Jar 校验完成（异常时已自动重下替换）",
                        i18nKey: "server.launch.verify_jar.success",
                        level: .notification
                    )
                )
            } catch {
                GlobalErrorHandler.shared.handle(error)
            }
        }
    }
}
