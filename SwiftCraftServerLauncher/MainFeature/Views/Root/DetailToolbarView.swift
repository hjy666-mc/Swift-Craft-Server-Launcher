import SwiftUI

public struct DetailToolbarView: ToolbarContent {
    @Environment(\.openURL)
    private var openURL
    @EnvironmentObject var filterState: ResourceFilterState
    @EnvironmentObject var detailState: ResourceDetailState
    @EnvironmentObject var serverRepository: ServerRepository
    @EnvironmentObject var serverLaunchUseCase: ServerLaunchUseCase
    @StateObject private var serverActionManager = ServerActionManager.shared
    @StateObject private var serverStatusManager = ServerStatusManager.shared
    @StateObject private var downloadCenter = DownloadCenter.shared

    private var currentServer: ServerInstance? {
        if case .server(let serverId) = detailState.selectedItem {
            return serverRepository.getServer(by: serverId)
        }
        return nil
    }

    private func openCurrentResourceInBrowser() {
        guard let slug = detailState.loadedProjectDetail?.slug else { return }
        let baseURL = URLConfig.API.Modrinth.webProjectBase
        guard let url = URL(string: baseURL + slug) else { return }
        openURL(url)
    }

    public var body: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            switch detailState.selectedItem {
            case .server:
                if let server = currentServer {
                    Button {
                        Task {
                            let isRunning = serverStatusManager.isServerRunning(serverId: server.id)
                            if isRunning {
                                await serverLaunchUseCase.stopServer(server: server)
                            } else {
                                serverStatusManager.setServerLaunching(serverId: server.id, isLaunching: true)
                                defer { serverStatusManager.setServerLaunching(serverId: server.id, isLaunching: false) }
                                await serverLaunchUseCase.launchServer(server: server)
                            }
                        }
                    } label: {
                        let isRunning = serverStatusManager.isServerRunning(serverId: server.id)
                        let isLaunching = serverStatusManager.isServerLaunching(serverId: server.id)
                        if isLaunching && !isRunning {
                            ProgressView().controlSize(.small)
                        } else {
                            Label(
                                isRunning ? "stop.fill".localized() : "play.fill".localized(),
                                systemImage: isRunning ? "stop.fill" : "play.fill"
                            )
                        }
                    }
                    .scaleEffect(serverStatusManager.isServerLaunching(serverId: server.id) ? 0.98 : 1.0)
                    .opacity(serverStatusManager.isServerLaunching(serverId: server.id) ? 0.88 : 1.0)
                    .animation(.easeInOut(duration: 0.15), value: serverStatusManager.isServerLaunching(serverId: server.id))
                    .disabled(serverStatusManager.isServerLaunching(serverId: server.id))
                    .applyReplaceTransition()

                    Spacer()

                    Button {
                        serverActionManager.showInFinder(server: server)
                    } label: {
                        Label("game.path".localized(), systemImage: "folder")
                            .foregroundStyle(.primary)
                    }
                    .help("game.path".localized())
                }
            case .resource:
                if detailState.selectedProjectId != nil {
                    Button {
                        detailState.selectedProjectId = nil
                        filterState.selectedTab = 0
                    } label: {
                        Label("return".localized(), systemImage: "arrow.backward")
                    }
                    .help("return".localized())

                    Spacer()

                    Button {
                        openCurrentResourceInBrowser()
                    } label: {
                        Label("common.browser".localized(), systemImage: "safari")
                    }
                    .help("resource.open_in_browser".localized())
                } else {
                    if downloadCenter.hasActiveTasks {
                        Button {
                            WindowManager.shared.openWindow(id: .downloadCenter)
                        } label: {
                            DownloadProgressLabelView(progress: downloadCenter.averageProgress)
                        }
                        .buttonStyle(.plain)
                        .help("下载中心")
                    } else {
                        Label(DataSource.modrinth.localizedName, systemImage: "network")
                            .labelStyle(.titleOnly)
                    }
                }
            case .game:
                EmptyView()
            case .node:
                EmptyView()
            @unknown default:
                EmptyView()
            }
        }
    }
}

private struct DownloadProgressLabelView: View {
    let progress: Double?

    var body: some View {
        let resolvedProgress = progress ?? 0
        HStack(spacing: 8) {
            ProgressView(value: resolvedProgress)
                .progressViewStyle(.linear)
                .frame(width: 140)
            Text("\(Int(resolvedProgress * 100))%")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
