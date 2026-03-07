//
//  MainContentArea.swift
//  SwiftCraftServerLauncher
//
//  承载 filterState/detailState，将二者从 MainView 根节点下沉至此，
//  减少 filterState（搜索、筛选等）变化时对 MainView 的触发重建。
//

import SwiftUI

/// 主内容区域：持有 filterState、detailState，渲染 NavigationSplitView
/// 当 filterState/detailState 变更时仅此视图及其子树重建，MainView 不重建
struct MainContentArea: View {
    let interfaceLayoutStyle: InterfaceLayoutStyle

    @State private var columnVisibility = NavigationSplitViewVisibility.all
    @StateObject private var filterState = ResourceFilterState()
    @StateObject private var detailState = ResourceDetailState()
    @EnvironmentObject var serverRepository: ServerRepository

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
            if case .resource(let type) = detailState.selectedItem,
               type != .mod && type != .plugin {
                detailState.selectedItem = .resource(.mod)
            }
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
        detailState.serverPanelSection = "console"
    }

    private func handleServerToServerTransition(
        from oldId: String,
        to newId: String
    ) {
        if oldId != newId {
            filterState.clearSearchText()
        }
        detailState.serverId = newId
        detailState.serverPanelSection = "console"
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
}
