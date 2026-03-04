import SwiftUI
import AppKit

/// 侧边栏：游戏列表与资源列表导航
public struct SidebarView: View {
    @EnvironmentObject var detailState: ResourceDetailState
    @EnvironmentObject var serverRepository: ServerRepository
    @EnvironmentObject var serverNodeRepository: ServerNodeRepository
    @State private var searchText: String = ""
    @AppStorage("activeServerNodeId")
    private var activeServerNodeId: String = ServerNode.local.id
    @StateObject private var serverActionManager = ServerActionManager.shared
    @State private var hoveredNodeInfoId: String?
    @State private var hoveredNodePopoverId: String?
    @State private var pendingNodePopoverClose: DispatchWorkItem?

    public init() {}

    public var body: some View {
        List(selection: detailState.selectedItemOptionalBinding) {
            Section(header: Text("sidebar.nodes.title".localized())) {
                ForEach(filteredNodes) { node in
                    HStack(spacing: 6) {
                        Button {
                            activeServerNodeId = node.id
                        } label: {
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
                            .padding(.vertical, 2)
                            .padding(.horizontal, 2)
                            .contentShape(Rectangle())
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(activeServerNodeId == node.id ? Color.accentColor.opacity(0.14) : Color.clear)
                            )
                        }
                        .buttonStyle(.plain)

                        Image(systemName: "info.circle")
                            .foregroundStyle(.secondary)
                            .onHover { hovering in
                                if hovering {
                                    pendingNodePopoverClose?.cancel()
                                    hoveredNodeInfoId = node.id
                                } else {
                                    scheduleNodePopoverClose(for: node.id)
                                }
                            }
                            .popover(
                                isPresented: Binding(
                                    get: { hoveredNodeInfoId == node.id || hoveredNodePopoverId == node.id },
                                    set: { showing in
                                        if !showing, hoveredNodeInfoId == node.id {
                                            hoveredNodeInfoId = nil
                                        }
                                    }
                                ),
                                arrowEdge: .trailing
                            ) {
                                nodeInfoPopover(node: node)
                                    .frame(width: 420)
                                    .padding(10)
                                    .onHover { hovering in
                                        if hovering {
                                            pendingNodePopoverClose?.cancel()
                                            hoveredNodePopoverId = node.id
                                        } else {
                                            hoveredNodePopoverId = nil
                                            scheduleNodePopoverClose(for: node.id)
                                        }
                                    }
                            }
                    }
                    .contextMenu {
                        if !node.isLocal {
                            Button(role: .destructive) {
                                serverNodeRepository.deleteNode(id: node.id)
                                if activeServerNodeId == node.id {
                                    activeServerNodeId = ServerNode.local.id
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
                            if let iconURL = server.iconFileURL,
                               let iconImage = NSImage(contentsOf: iconURL) {
                                Image(nsImage: iconImage)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 16, height: 16)
                                    .clipShape(RoundedRectangle(cornerRadius: 4))
                            } else {
                                Image(systemName: server.resolvedIconName)
                            }
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

    @ViewBuilder
    private func nodeInfoPopover(node: ServerNode) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(node.name)
                .font(.headline)
            Text(node.isLocal ? "node.type.local".localized() : "node.type.remote_linux".localized())
                .font(.caption)
                .foregroundStyle(.secondary)
            Divider()
            row("node.info.host".localized(), node.host)
            row("node.info.user".localized(), node.username)
            row("node.info.port".localized(), "\(node.port)")
            row("node.info.remote_root".localized(), node.remoteRootPath, canCopy: true)
            row("node.info.storage".localized(), AppPaths.remoteNodeDirectory(nodeId: node.id).path, canOpen: true)
        }
    }

    @ViewBuilder
    private func row(_ key: String, _ value: String, canCopy: Bool = false, canOpen: Bool = false) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(key)
                .foregroundStyle(.secondary)
                .frame(width: 108, alignment: .leading)
            Text(value)
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)
                .lineLimit(2)
            Spacer(minLength: 0)
            if canCopy {
                Button("复制") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(value, forType: .string)
                }
                .buttonStyle(.plain)
            } else if canOpen {
                Button("打开") {
                    guard FileManager.default.fileExists(atPath: value) else { return }
                    NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: value)])
                }
                .buttonStyle(.plain)
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

    private func scheduleNodePopoverClose(for nodeId: String) {
        pendingNodePopoverClose?.cancel()
        let work = DispatchWorkItem {
            if hoveredNodeInfoId == nodeId, hoveredNodePopoverId == nil {
                hoveredNodeInfoId = nil
            }
            if hoveredNodePopoverId == nodeId {
                hoveredNodePopoverId = nil
            }
        }
        pendingNodePopoverClose = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: work)
    }
}
