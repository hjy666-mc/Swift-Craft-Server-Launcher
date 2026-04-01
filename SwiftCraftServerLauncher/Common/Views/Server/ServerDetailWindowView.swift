import SwiftUI

struct ServerDetailWindowView: View {
    @StateObject private var coordinator = ServerDetailWindowCoordinator.shared
    let serverId: String
    @State private var columnVisibility = NavigationSplitViewVisibility.all
    @StateObject private var filterState = ResourceFilterState()
    @StateObject private var detailState = ResourceDetailState()
    @EnvironmentObject private var serverRepository: ServerRepository
    @EnvironmentObject private var serverNodeRepository: ServerNodeRepository
    @EnvironmentObject private var serverLaunchUseCase: ServerLaunchUseCase
    @EnvironmentObject private var generalSettings: GeneralSettingsManager

    private var serverName: String {
        serverRepository.getServer(by: serverId)?.name ?? "server.window.title".localized()
    }

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            ContentView()
                .navigationSplitViewColumnWidth(min: 235, ideal: 235, max: 280)
        } detail: {
            DetailView()
        }
        .environmentObject(filterState)
        .environmentObject(detailState)
        .environmentObject(serverRepository)
        .environmentObject(serverNodeRepository)
        .environmentObject(serverLaunchUseCase)
        .environmentObject(generalSettings)
        .toolbar {
            DetailToolbarView(
                filterState: filterState,
                detailState: detailState,
                serverRepository: serverRepository,
                serverLaunchUseCase: serverLaunchUseCase
            )
        }
        .windowIdentifierConfig(for: .serverDetail)
        .background(
            WindowAccessor(synchronous: false) { window in
                window.title = serverName
            }
        )
        .onAppear {
            syncSelection()
        }
        .onChange(of: coordinator.preferredSections) { _, _ in
            syncSelection()
        }
    }

    private func syncSelection() {
        detailState.selectedItem = .server(serverId)
        detailState.serverId = serverId
        detailState.serverPanelSection = coordinator.consumePreferredSection(for: serverId)
    }
}

#Preview {
    ServerDetailWindowView(serverId: "preview")
        .environmentObject(ServerRepository())
        .environmentObject(ServerNodeRepository())
        .environmentObject(ServerLaunchUseCase())
        .environmentObject(GeneralSettingsManager.shared)
}
