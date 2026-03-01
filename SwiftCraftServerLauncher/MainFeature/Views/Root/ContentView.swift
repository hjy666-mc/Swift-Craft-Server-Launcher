//
//  ContentView.swift
//  SwiftCraftServerLauncher
//
//  Created by su on 2025/6/1.
//

import SwiftUI

struct ContentView: View {
    @EnvironmentObject var filterState: ResourceFilterState
    @EnvironmentObject var detailState: ResourceDetailState
    @EnvironmentObject var serverRepository: ServerRepository
    @EnvironmentObject var serverNodeRepository: ServerNodeRepository

    var body: some View {
        List {
            switch detailState.selectedItem {
            case .game(let gameId):
                Text("\("game.module.removed.with_id".localized())\(gameId)")
                    .foregroundColor(.secondary)
            case .server(let serverId):
                serverContentView(serverId: serverId)
            case .node(let nodeId):
                Text("\("node.selected".localized())\(serverNodeRepository.getNode(by: nodeId)?.name ?? nodeId)")
                    .foregroundColor(.secondary)
            case .resource(let type):
                resourceContentView(type: type)
            }
        }
    }

    @ViewBuilder
    private func resourceContentView(type: ResourceType) -> some View {
        if let projectId = detailState.selectedProjectId {
            ModrinthProjectContentView(
                projectDetail: detailState.loadedProjectDetailBinding,
                projectId: projectId
            )
        } else {
            CategoryContentView(
                project: type.rawValue,
                type: "resource",
                selectedCategories: filterState.selectedCategoriesBinding,
                selectedFeatures: filterState.selectedFeaturesBinding,
                selectedResolutions: filterState.selectedResolutionsBinding,
                selectedPerformanceImpacts: filterState.selectedPerformanceImpactBinding,
                selectedVersions: filterState.selectedVersionsBinding,
                selectedLoaders: filterState.selectedLoadersBinding,
                dataSource: filterState.dataSource
            )
            .id(type)
        }
    }

    @ViewBuilder
    private func serverContentView(serverId: String) -> some View {
        if let server = serverRepository.getServer(by: serverId) {
            ServerLaunchCommandView(server: server)
                .environmentObject(serverRepository)
        }
    }

}
