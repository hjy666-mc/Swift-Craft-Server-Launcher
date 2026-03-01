//
//  DetailView.swift
//  SwiftCraftServerLauncher
//
//  Created by su on 2025/6/1.
//

import SwiftUI

struct DetailView: View {
    @EnvironmentObject var filterState: ResourceFilterState
    @EnvironmentObject var detailState: ResourceDetailState
    @EnvironmentObject var serverRepository: ServerRepository
    @EnvironmentObject var serverNodeRepository: ServerNodeRepository

    @ViewBuilder var body: some View {
        switch detailState.selectedItem {
        case .game:
            Text("game.module.removed".localized())
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        case .server(let serverId):
            serverDetailView(serverId: serverId).frame(maxWidth: .infinity, alignment: .leading)
        case .node(let nodeId):
            nodeDetailView(nodeId: nodeId).frame(maxWidth: .infinity, alignment: .leading)
        case .resource(let type):
            resourceDetailView(type: type)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private func resourceDetailView(type: ResourceType) -> some View {
        if detailState.selectedProjectId != nil {
            List {
                ModrinthProjectDetailView(
                    projectDetail: detailState.loadedProjectDetail
                )
            }
        } else {
            ModrinthDetailView(
                query: type.rawValue,
                selectedVersions: filterState.selectedVersionsBinding,
                selectedCategories: filterState.selectedCategoriesBinding,
                selectedFeatures: filterState.selectedFeaturesBinding,
                selectedResolutions: filterState.selectedResolutionsBinding,
                selectedPerformanceImpact: filterState.selectedPerformanceImpactBinding,
                selectedProjectId: detailState.selectedProjectIdBinding,
                selectedLoader: filterState.selectedLoadersBinding,
                gameInfo: nil,
                selectedItem: detailState.selectedItemBinding,
                gameType: detailState.gameTypeBinding,
                dataSource: filterState.dataSourceBinding,
                searchText: filterState.searchTextBinding
            )
        }
    }

    @ViewBuilder
    private func serverDetailView(serverId: String) -> some View {
        if let server = serverRepository.getServer(by: serverId) {
            ServerDetailView(server: server)
                .environmentObject(serverRepository)
        }
    }

    @ViewBuilder
    private func nodeDetailView(nodeId: String) -> some View {
        if let node = serverNodeRepository.getNode(by: nodeId) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 10) {
                    Image(systemName: node.isLocal ? "desktopcomputer" : "network")
                        .font(.title2)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(node.name).font(.title3).bold()
                        Text(node.isLocal ? "node.type.local".localized() : "node.type.remote_linux".localized())
                            .foregroundColor(.secondary)
                    }
                }

                VStack(alignment: .leading, spacing: 6) {
                    row("node.info.host".localized(), node.host)
                    row("node.info.user".localized(), node.username)
                    row("node.info.port".localized(), "\(node.port)")
                    row("node.info.remote_root".localized(), node.remoteRootPath)
                    row("node.info.storage".localized(), AppPaths.remoteNodeDirectory(nodeId: node.id).path)
                }
                .padding(12)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 10))
            }
            .padding(.vertical, 10)
        }
    }

    private func row(_ key: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text("\(key):")
                .foregroundColor(.secondary)
                .frame(width: 110, alignment: .leading)
            Text(value)
                .textSelection(.enabled)
            Spacer(minLength: 0)
        }
    }
}
