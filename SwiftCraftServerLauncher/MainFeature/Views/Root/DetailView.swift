//
//  DetailView.swift
//  SwiftCraftServerLauncher
//
//  Created by su on 2025/6/1.
//

import SwiftUI
import AppKit

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
        case .node:
            EmptyView()
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
            ZStack {
                switch detailState.serverPanelSection {
                case "serverConfig":
                    ServerPropertiesEditorView(server: server)
                case "players":
                    ServerPlayersView(server: server)
                case "worlds":
                    ServerWorldsManagerView(server: server)
                case "mods":
                    if server.serverType == .fabric || server.serverType == .forge {
                        ServerModsManagerView(server: server)
                    } else {
                        ServerConsoleView(server: server)
                    }
                case "plugins":
                    if server.serverType == .paper {
                        ServerPluginsManagerView(server: server)
                    } else {
                        ServerConsoleView(server: server)
                    }
                default:
                    ServerConsoleView(server: server)
                }
            }
            .id("\(server.id)-\(detailState.serverPanelSection)")
            .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity), removal: .opacity))
            .animation(.easeInOut(duration: 0.18), value: detailState.serverPanelSection)
        }
    }
}
