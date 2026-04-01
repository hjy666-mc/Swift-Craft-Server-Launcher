import SwiftUI

public struct DetailToolbarView: ToolbarContent {
    @Environment(\.openURL)
    private var openURL
    @ObservedObject var filterState: ResourceFilterState
    @ObservedObject var detailState: ResourceDetailState
    @ObservedObject var serverRepository: ServerRepository
    @ObservedObject var serverLaunchUseCase: ServerLaunchUseCase
    @StateObject private var serverActionManager = ServerActionManager.shared
    @StateObject private var serverStatusManager = ServerStatusManager.shared

    init(
        filterState: ResourceFilterState,
        detailState: ResourceDetailState,
        serverRepository: ServerRepository,
        serverLaunchUseCase: ServerLaunchUseCase
    ) {
        self.filterState = filterState
        self.detailState = detailState
        self.serverRepository = serverRepository
        self.serverLaunchUseCase = serverLaunchUseCase
    }

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

    private func post(_ action: ServerDetailToolbarAction) {
        ServerDetailToolbarActionBus.post(action)
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

                    if detailState.serverPanelSection == "console" {
                        Button {
                            serverActionManager.showInFinder(server: server)
                        } label: {
                            Label("game.path".localized(), systemImage: "folder")
                                .foregroundStyle(.primary)
                        }
                        .help("game.path".localized())
                    }

                    switch detailState.serverPanelSection {
                    case "serverConfig":
                        EmptyView()
                    case "worlds":
                        Button {
                            post(.worldsOpenFolder)
                        } label: {
                            Label("server.worlds.open_folder".localized(), systemImage: "folder")
                        }
                        .help("server.worlds.open_folder".localized())
                        Button {
                            post(.worldsImport)
                        } label: {
                            Label("server.worlds.import".localized(), systemImage: "tray.and.arrow.down")
                        }
                        .help("server.worlds.import".localized())
                    case "mods":
                        Button {
                            post(.modsImport)
                        } label: {
                            Label("server.mods.import".localized(), systemImage: "tray.and.arrow.down")
                        }
                        .help("server.mods.import".localized())
                    case "plugins":
                        Button {
                            post(.pluginsImport)
                        } label: {
                            Label("server.plugins.import".localized(), systemImage: "tray.and.arrow.down")
                        }
                        .help("server.plugins.import".localized())
                    case "console":
                        Button {
                            post(.consoleClear)
                        } label: {
                            Label("common.clear".localized(), systemImage: "trash")
                        }
                        .help("common.clear".localized())
                    case "schedules":
                        Button {
                            post(.schedulesNew)
                        } label: {
                            Label("server.schedules.add".localized(), systemImage: "note.text.badge.plus")
                        }
                        .help("server.schedules.add".localized())
                    default:
                        EmptyView()
                    }
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
                    EmptyView()
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
