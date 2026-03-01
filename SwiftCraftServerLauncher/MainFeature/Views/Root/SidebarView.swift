import SwiftUI

/// 侧边栏：游戏列表与资源列表导航
public struct SidebarView: View {
    @EnvironmentObject var detailState: ResourceDetailState
    @EnvironmentObject var serverRepository: ServerRepository
    @EnvironmentObject var serverNodeRepository: ServerNodeRepository
    @State private var searchText: String = ""
    @AppStorage("activeServerNodeId") private var activeServerNodeId: String = ServerNode.local.id
    @StateObject private var serverActionManager = ServerActionManager.shared

    public init() {}

    public var body: some View {
        List(selection: detailState.selectedItemOptionalBinding) {
            Section(header: Text("sidebar.nodes.title".localized())) {
                ForEach(filteredNodes) { node in
                    NavigationLink(value: SidebarItem.node(node.id)) {
                        HStack(spacing: 6) {
                            Image(systemName: node.isLocal ? "desktopcomputer" : "network")
                            Text(node.name)
                                .lineLimit(1)
                            Spacer(minLength: 4)
                            if activeServerNodeId == node.id {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.accentColor)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 6)
                        .padding(.horizontal, 4)
                        .contentShape(Rectangle())
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(activeServerNodeId == node.id ? Color.accentColor.opacity(0.14) : Color.clear)
                        )
                    }
                    .contextMenu {
                        if !node.isLocal {
                            Button(role: .destructive) {
                                serverNodeRepository.deleteNode(id: node.id)
                                if activeServerNodeId == node.id {
                                    activeServerNodeId = ServerNode.local.id
                                    detailState.selectedItem = .node(ServerNode.local.id)
                                }
                            } label: {
                                Label("node.delete".localized(), systemImage: "trash")
                            }
                        }
                    }
                }
            }

            // 资源部分
            Section(header: Text("sidebar.resources.title".localized())) {
                ForEach([ResourceType.mod, ResourceType.plugin], id: \.self) { type in
                    NavigationLink(value: SidebarItem.resource(type)) {
                        HStack(spacing: 6) {
                            Label(type.localizedName, systemImage: type.systemImage)
                        }
                    }
                }
            }

            Section(header: Text("\("sidebar.servers.title".localized()) (\(filteredServers.count))")) {
                ForEach(filteredServers) { server in
                    NavigationLink(value: SidebarItem.server(server.id)) {
                        HStack(spacing: 6) {
                            Image(systemName: "server.rack")
                            Text(server.name)
                                .lineLimit(1)
                        }
                        .tag(server.id)
                    }
                    .contextMenu {
                        Button(role: .destructive) {
                            serverActionManager.deleteServer(
                                server: server,
                                serverRepository: serverRepository,
                                selectedItem: detailState.selectedItemBinding
                            )
                        } label: {
                            Label("sidebar.context_menu.delete_game".localized(), systemImage: "trash")
                        }
                    }
                }
                if filteredServers.isEmpty {
                    Text("node.no_servers".localized())
                        .foregroundColor(.secondary)
                }
            }

            if !filteredCorruptedServers.isEmpty {
                Section(header: Text("sidebar.corrupted_servers.title".localized())) {
                    ForEach(filteredCorruptedServers, id: \.self) { name in
                        HStack(spacing: 6) {
                            Label(name, systemImage: "exclamationmark.triangle")
                        }
                        .contextMenu {
                            Button(role: .destructive) {
                                serverActionManager.deleteCorruptedServer(
                                    name: name,
                                    serverRepository: serverRepository
                                )
                            } label: {
                                Label("sidebar.context_menu.delete_game".localized(), systemImage: "trash")
                            }
                        }
                    }
                }
            }
        }
        .searchable(text: $searchText, placement: .sidebar, prompt: Localized.Sidebar.Search.games)
        .listStyle(.sidebar)
        .onAppear {
            serverRepository.reloadServers()
            if serverNodeRepository.getNode(by: activeServerNodeId) == nil {
                activeServerNodeId = ServerNode.local.id
            }
        }
        .onChange(of: detailState.selectedItem) { _, newValue in
            if case .node(let nodeId) = newValue {
                activeServerNodeId = nodeId
            }
        }
    }

    private var filteredServers: [ServerInstance] {
        let nodeServers = serverRepository.servers.filter { $0.nodeId == activeServerNodeId }
        if searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return nodeServers
        }
        let lower = searchText.lowercased()
        return nodeServers.filter { $0.name.lowercased().contains(lower) }
    }

    private var filteredNodes: [ServerNode] {
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return serverNodeRepository.nodes
        }
        let lower = trimmed.lowercased()
        return serverNodeRepository.nodes.filter {
            $0.name.lowercased().contains(lower) || $0.host.lowercased().contains(lower)
        }
    }

    private var filteredCorruptedServers: [String] {
        let names = serverRepository.corruptedServers
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return names
        }
        let lower = trimmed.lowercased()
        return names.filter { $0.lowercased().contains(lower) }
    }
}
