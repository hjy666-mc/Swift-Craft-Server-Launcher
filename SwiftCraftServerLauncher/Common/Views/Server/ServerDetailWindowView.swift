import SwiftUI

struct ServerDetailWindowView: View {
    @StateObject private var coordinator = ServerDetailWindowCoordinator.shared
    @StateObject private var filterState = ResourceFilterState()
    @StateObject private var detailState = ResourceDetailState()
    @EnvironmentObject private var serverRepository: ServerRepository
    @EnvironmentObject private var serverNodeRepository: ServerNodeRepository
    @EnvironmentObject private var serverLaunchUseCase: ServerLaunchUseCase
    @EnvironmentObject private var generalSettings: GeneralSettingsManager

    var body: some View {
        NavigationSplitView(columnVisibility: .constant(.doubleColumn)) {
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
            DetailToolbarView()
        }
        .windowIdentifierConfig(for: .serverDetail)
        .onAppear {
            syncSelection()
        }
        .onChange(of: coordinator.serverId) { _, _ in
            syncSelection()
        }
        .onChange(of: coordinator.preferredSection) { _, _ in
            syncSelection()
        }
    }

    private func syncSelection() {
        guard let serverId = coordinator.serverId else { return }
        detailState.selectedItem = .server(serverId)
        detailState.serverId = serverId
        detailState.serverPanelSection = coordinator.preferredSection
    }
}

#Preview {
    ServerDetailWindowView()
        .environmentObject(ServerRepository())
        .environmentObject(ServerNodeRepository())
        .environmentObject(ServerLaunchUseCase())
        .environmentObject(GeneralSettingsManager.shared)
}
