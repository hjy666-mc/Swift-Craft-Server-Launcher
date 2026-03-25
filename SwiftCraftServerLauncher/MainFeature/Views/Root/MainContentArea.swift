import SwiftUI

/// 主内容区域：持有 filterState、detailState，渲染 NavigationSplitView
/// 当 filterState/detailState 变更时仅此视图及其子树重建，MainView 不重建
struct MainContentArea: View {
    let interfaceLayoutStyle: InterfaceLayoutStyle

    @State private var columnVisibility = NavigationSplitViewVisibility.all
    @StateObject private var filterState = ResourceFilterState()
    @StateObject private var detailState = ResourceDetailState()
    @State private var pendingSpotlightIdentifier: String?
    @State private var spotlightRetryCount = 0
    @EnvironmentObject var serverRepository: ServerRepository
    @EnvironmentObject var serverNodeRepository: ServerNodeRepository
    @Environment(\.openSettings)
    private var openSettings: OpenSettingsAction
    @EnvironmentObject private var settingsNavigationManager: SettingsNavigationManager
    @EnvironmentObject private var commandPalette: CommandPaletteController

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 168, ideal: 168, max: 168)
        } content: {
            if interfaceLayoutStyle == .classic {
                middleColumnContentView
            } else {
                middleColumnDetailView
            }
        } detail: {
            if interfaceLayoutStyle == .classic {
                middleColumnDetailView
            } else {
                middleColumnContentView
            }
        }
        .environmentObject(filterState)
        .environmentObject(detailState)
        .onChange(of: detailState.selectedItem) { oldValue, newValue in
            handleSidebarItemChange(from: oldValue, to: newValue)
        }
        .onChange(of: serverRepository.workingPathChanged) { _, _ in
            detailState.selectedItem = .resource(.mod)
            detailState.serverId = nil
        }
        .onAppear {
            if case .game = detailState.selectedItem {
                detailState.selectedItem = .resource(.mod)
            }
        }
        .onAppear {
            SpotlightIndexService.shared.ensureIndexedIfNeeded(nodes: commandPaletteNodes)
            processPendingSpotlight()
        }
        .onChange(of: serverRepository.servers) { _, _ in
            SpotlightIndexService.shared.scheduleIndex(nodes: commandPaletteNodes)
            processPendingSpotlight()
        }
        .onReceive(SpotlightActionCenter.shared.publisher) { identifier in
            pendingSpotlightIdentifier = identifier
            spotlightRetryCount = 0
            processPendingSpotlight()
            serverRepository.reloadServers()
        }
        .sheet(isPresented: $commandPalette.isPresented) {
            CommandPaletteView(nodes: commandPaletteNodes)
        }
    }

    @ViewBuilder private var middleColumnDetailView: some View {
        DetailView()
            .toolbar {
                DetailToolbarView()
            }
    }

    @ViewBuilder private var middleColumnContentView: some View {
        ContentView()
            .toolbar { ContentToolbarView() }
            .navigationSplitViewColumnWidth(min: 235, ideal: 235, max: 280)
    }

    // MARK: - Sidebar Item Change Handlers

    private func handleSidebarItemChange(
        from oldValue: SidebarItem,
        to newValue: SidebarItem
    ) {
        switch (oldValue, newValue) {
        case (.node, .node):
            break
        case (.node, .server(let id)):
            handleResourceToServerTransition(serverId: id)
        case (.node, .resource):
            resetToResourceDefaults()
        case (_, .node):
            detailState.serverId = nil
            detailState.selectedProjectId = nil
            filterState.clearSearchText()
        case (.resource, .server(let id)):
            handleResourceToServerTransition(serverId: id)
        case (.game, .resource):
            resetToResourceDefaults()
        case (.game, .server(let id)):
            handleResourceToServerTransition(serverId: id)
        case (.server, .resource):
            resetToResourceDefaults()
        case let (.server(oldId), .server(newId)):
            handleServerToServerTransition(from: oldId, to: newId)
        case (.resource, .resource):
            resetToResourceDefaults()
        default:
            break
        }
    }

    private func handleResourceToServerTransition(serverId: String) {
        filterState.clearSearchText()
        detailState.gameId = nil
        detailState.selectedProjectId = nil
        detailState.serverId = serverId
        if detailState.serverPanelSection == "console" {
            detailState.serverPanelSection = "console"
        }
    }

    private func handleServerToServerTransition(
        from oldId: String,
        to newId: String
    ) {
        if oldId != newId {
            filterState.clearSearchText()
        }
        detailState.serverId = newId
        if detailState.serverPanelSection == "console" {
            detailState.serverPanelSection = "console"
        }
    }

    private func resetToResourceDefaults() {
        if case .resource = detailState.selectedItem {
            if detailState.gameId == nil {
                filterState.clearSearchText()
            }
        }
        filterState.sortIndex = AppConstants.modrinthIndex

        if case .resource(let resourceType) = detailState.selectedItem {
            detailState.gameResourcesType = resourceType.rawValue
        }
        filterState.clearFiltersAndPagination()

        if detailState.gameId == nil && detailState.selectedProjectId != nil {
            detailState.selectedProjectId = nil
        }
        if detailState.selectedProjectId == nil && detailState.gameId != nil {
            detailState.gameId = nil
            filterState.clearSearchText()
        }
        if detailState.serverId != nil {
            detailState.serverId = nil
        }
        if detailState.loadedProjectDetail != nil && detailState.gameId != nil
            && detailState.selectedProjectId != nil {
            detailState.gameId = nil
            detailState.loadedProjectDetail = nil
            detailState.selectedProjectId = nil
        }
    }

    private func openResource(
        type: ResourceType,
        applySearch: Bool
    ) {
        detailState.selectedItem = .resource(type)
        detailState.gameResourcesType = type.rawValue
        resetToResourceDefaults()
        if applySearch {
            filterState.searchText = commandPalette.query
        }
    }

    private var commandPaletteNodes: [CommandPaletteNode] {
        var nodes: [CommandPaletteNode] = []

        let settingsChildren: [CommandPaletteNode] = [
            CommandPaletteNode(
                id: "settings.basic",
                title: "settings.general.basic.tab".localized(),
                subtitle: "command.palette.section.settings".localized(),
                systemImage: "gearshape",
                settingsTab: .generalBasic
            ),
            CommandPaletteNode(
                id: "settings.update",
                title: "settings.general.update.tab".localized(),
                subtitle: "command.palette.section.settings".localized(),
                systemImage: "arrow.triangle.2.circlepath",
                settingsTab: .generalUpdate
            ),
            CommandPaletteNode(
                id: "settings.safety",
                title: "settings.general.confirmation.tab".localized(),
                subtitle: "command.palette.section.settings".localized(),
                systemImage: "checkmark.shield",
                settingsTab: .generalSafety
            ),
            CommandPaletteNode(
                id: "settings.backup",
                title: "settings.general.backup.tab".localized(),
                subtitle: "command.palette.section.settings".localized(),
                systemImage: "archivebox",
                settingsTab: .generalBackup
            ),
            CommandPaletteNode(
                id: "settings.appearance",
                title: "settings.appearance.tab".localized(),
                subtitle: "command.palette.section.settings".localized(),
                systemImage: "paintpalette",
                settingsTab: .appearance
            ),
        ]

        nodes.append(
            CommandPaletteNode(
                id: "settings",
                title: "command.palette.action.settings".localized(),
                subtitle: "command.palette.section.settings".localized(),
                systemImage: "gearshape",
                children: settingsChildren
            )
        )

        nodes.append(
            CommandPaletteNode(
                id: "downloadCenter",
                title: "command.palette.action.download_center".localized(),
                subtitle: nil,
                systemImage: "arrow.down.circle"
            ) {
                WindowManager.shared.openWindow(id: .downloadCenter)
            }
        )

        let resourceTypes: [ResourceType] = [.mod, .plugin]
        let resourceChildren: [CommandPaletteNode] = resourceTypes.map { type in
            CommandPaletteNode(
                id: "resource:\(type.rawValue)",
                title: type.localizedName,
                subtitle: "command.palette.section.resources".localized(),
                systemImage: type.systemImage,
                searchScope: .resourceType(type),
                searchOnly: false,
                resourceType: type
            ) {
                openResource(type: type, applySearch: !commandPalette.query.isEmpty)
            }
        }

        let resourceSearchNodes: [CommandPaletteNode] = resourceTypes.map { type in
            CommandPaletteNode(
                id: "resource-search:\(type.rawValue)",
                title: type.localizedName,
                subtitle: nil,
                systemImage: type.systemImage,
                searchOnly: true,
                resourceType: type
            ) {
                openResource(type: type, applySearch: true)
            }
        }

        nodes.append(
            CommandPaletteNode(
                id: "resources",
                title: "command.palette.section.resources".localized(),
                subtitle: nil,
                systemImage: "square.grid.2x2",
                children: resourceChildren,
                searchScope: .resources
            )
        )

        nodes.append(contentsOf: resourceSearchNodes)

        let serverChildren = serverRepository.servers.map { server in
            let supportsMods = server.serverType == .fabric || server.serverType == .forge
            let supportsPlugins = server.serverType == .paper
            var detailChildren: [CommandPaletteNode] = [
                CommandPaletteNode(
                    id: "server:\(server.id):console",
                    title: "server.console.title".localized(),
                    subtitle: server.name,
                    systemImage: "terminal"
                ) {
                    detailState.selectedItem = .server(server.id)
                    handleResourceToServerTransition(serverId: server.id)
                    detailState.serverPanelSection = "console"
                },
                CommandPaletteNode(
                    id: "server:\(server.id):config",
                    title: "server.launch.server_config".localized(),
                    subtitle: server.name,
                    systemImage: "slider.horizontal.3"
                ) {
                    detailState.selectedItem = .server(server.id)
                    handleResourceToServerTransition(serverId: server.id)
                    detailState.serverPanelSection = "serverConfig"
                },
                CommandPaletteNode(
                    id: "server:\(server.id):players",
                    title: "server.launch.players".localized(),
                    subtitle: server.name,
                    systemImage: "person.3"
                ) {
                    detailState.selectedItem = .server(server.id)
                    handleResourceToServerTransition(serverId: server.id)
                    detailState.serverPanelSection = "players"
                },
                CommandPaletteNode(
                    id: "server:\(server.id):worlds",
                    title: "server.launch.worlds".localized(),
                    subtitle: server.name,
                    systemImage: "globe.americas"
                ) {
                    detailState.selectedItem = .server(server.id)
                    handleResourceToServerTransition(serverId: server.id)
                    detailState.serverPanelSection = "worlds"
                },
            ]
            if supportsMods {
                detailChildren.append(
                    CommandPaletteNode(
                        id: "server:\(server.id):mods",
                        title: "server.launch.mods".localized(),
                        subtitle: server.name,
                        systemImage: "puzzlepiece.extension"
                    ) {
                        detailState.selectedItem = .server(server.id)
                        handleResourceToServerTransition(serverId: server.id)
                        detailState.serverPanelSection = "mods"
                    }
                )
            }
            if supportsPlugins {
                detailChildren.append(
                    CommandPaletteNode(
                        id: "server:\(server.id):plugins",
                        title: "server.launch.plugins".localized(),
                        subtitle: server.name,
                        systemImage: "powerplug"
                    ) {
                        detailState.selectedItem = .server(server.id)
                        handleResourceToServerTransition(serverId: server.id)
                        detailState.serverPanelSection = "plugins"
                    }
                )
            }

            return CommandPaletteNode(
                id: "server:\(server.id)",
                title: server.name,
                subtitle: "command.palette.section.servers".localized(),
                systemImage: "server.rack",
                children: detailChildren
            ) {
                detailState.selectedItem = .server(server.id)
                handleResourceToServerTransition(serverId: server.id)
            }
        }

        nodes.append(
            CommandPaletteNode(
                id: "servers",
                title: "command.palette.section.servers".localized(),
                subtitle: nil,
                systemImage: "server.rack",
                children: serverChildren
            )
        )

        return nodes
    }

    @discardableResult
    private func handleSpotlightIdentifier(_ identifier: String) -> Bool {
        let id = SpotlightIndexService.shared.stripIdentifierPrefix(identifier)
        let flattened = flattenNodes(commandPaletteNodes)
        guard let node = flattened.first(where: { $0.id == id }) else { return false }

        if node.id == "settings" {
            openSettings()
            settingsNavigationManager.selectedTab = .generalBasic
            return true
        }

        if let tab = node.settingsTab {
            openSettings()
            settingsNavigationManager.selectedTab = tab
            return true
        }

        node.action?()
        return true
    }

    private func processPendingSpotlight() {
        guard let pending = pendingSpotlightIdentifier else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            if handleSpotlightIdentifier(pending) {
                pendingSpotlightIdentifier = nil
                spotlightRetryCount = 0
            } else if spotlightRetryCount < 4 {
                spotlightRetryCount += 1
                processPendingSpotlight()
            }
        }
    }

    private func flattenNodes(_ nodes: [CommandPaletteNode]) -> [CommandPaletteNode] {
        var results: [CommandPaletteNode] = []
        for node in nodes {
            results.append(node)
            if !node.children.isEmpty {
                results.append(contentsOf: flattenNodes(node.children))
            }
        }
        return results
    }
}
