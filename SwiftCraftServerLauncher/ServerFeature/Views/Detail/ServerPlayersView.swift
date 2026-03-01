import SwiftUI

struct ServerPlayersView: View {
    let server: ServerInstance
    @Environment(\.dismiss)
    private var dismiss
    @EnvironmentObject var serverNodeRepository: ServerNodeRepository
    @StateObject private var serverStatusManager = ServerStatusManager.shared
    @State private var whitelist: [ServerPlayerListService.PlayerEntry] = []
    @State private var ops: [ServerPlayerListService.PlayerEntry] = []
    @State private var bannedPlayers: [ServerPlayerListService.PlayerEntry] = []
    @State private var bannedIps: [ServerPlayerListService.PlayerEntry] = []

    @State private var newName: String = ""
    @State private var selectedList: String = "whitelist"

    var body: some View {
        CommonSheetView(
            header: {
                HStack {
                    Text("server.players.title".localized())
                        .font(.headline)
                    Spacer()
                }
            },
            body: {
                VStack(alignment: .leading, spacing: 8) {
                    if serverStatusManager.isServerRunning(serverId: server.id) {
                        Text("server.players.running_hint".localized())
                            .foregroundColor(.secondary)
                    } else {
                        Text("server.players.stopped_hint".localized())
                            .foregroundColor(.secondary)
                    }

                    HStack(spacing: 6) {
                        TextField("server.players.name_placeholder".localized(), text: $newName)
                            .textFieldStyle(.roundedBorder)
                        Picker("", selection: $selectedList) {
                            Text("server.players.list.whitelist".localized()).tag("whitelist")
                            Text("server.players.list.ops".localized()).tag("ops")
                            Text("server.players.list.banned_players".localized()).tag("bannedPlayers")
                            Text("server.players.list.banned_ips".localized()).tag("bannedIps")
                        }
                        .pickerStyle(.menu)
                        Button("common.add".localized()) { addEntry() }
                            .disabled(newName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        Button("common.reload".localized()) { loadAll() }
                    }

                    ScrollView {
                        VStack(alignment: .leading, spacing: 10) {
                            playerList(title: "server.players.list.whitelist".localized(), entries: whitelist) { removeEntry(from: "whitelist", entry: $0) }
                            playerList(title: "server.players.list.ops".localized(), entries: ops) { removeEntry(from: "ops", entry: $0) }
                            playerList(title: "server.players.list.banned_players".localized(), entries: bannedPlayers) { removeEntry(from: "bannedPlayers", entry: $0) }
                            playerList(title: "server.players.list.banned_ips".localized(), entries: bannedIps) { removeEntry(from: "bannedIps", entry: $0) }
                        }
                    }
                    .frame(minHeight: 220, maxHeight: 360)
                }
            },
            footer: {
                HStack(spacing: 8) {
                    Button("common.close".localized()) { dismiss() }
                    Spacer()
                    Button("common.reload".localized()) { loadAll() }
                }
            }
        )
        .frame(minWidth: 760, minHeight: 440)
        .onAppear { loadAll() }
    }

    private func playerList(title: String, entries: [ServerPlayerListService.PlayerEntry], onRemove: @escaping (ServerPlayerListService.PlayerEntry) -> Void) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.subheadline)
            if entries.isEmpty {
                Text("common.empty".localized())
                    .foregroundColor(.secondary)
            } else {
                ForEach(entries, id: \.self) { entry in
                    HStack {
                        Text(entry.name)
                        Spacer()
                        Button("common.remove".localized()) { onRemove(entry) }
                    }
                }
            }
        }
    }

    private func loadAll() {
        if isRemoteServer {
            whitelist = []
            ops = []
            bannedPlayers = []
            bannedIps = []
            return
        }
        let dir = AppPaths.serverDirectory(serverName: server.name)
        do {
            whitelist = try ServerPlayerListService.readList(serverDir: dir, fileName: "whitelist.json")
            ops = try ServerPlayerListService.readList(serverDir: dir, fileName: "ops.json")
            bannedPlayers = try ServerPlayerListService.readList(serverDir: dir, fileName: "banned-players.json")
            bannedIps = try ServerPlayerListService.readList(serverDir: dir, fileName: "banned-ips.json")
        } catch {
            GlobalErrorHandler.shared.handle(error)
        }
    }

    private func saveAll() {
        if isRemoteServer { return }
        if serverStatusManager.isServerRunning(serverId: server.id) { return }
        let dir = AppPaths.serverDirectory(serverName: server.name)
        do {
            try ServerPlayerListService.writeList(serverDir: dir, fileName: "whitelist.json", entries: whitelist)
            try ServerPlayerListService.writeList(serverDir: dir, fileName: "ops.json", entries: ops)
            try ServerPlayerListService.writeList(serverDir: dir, fileName: "banned-players.json", entries: bannedPlayers)
            try ServerPlayerListService.writeList(serverDir: dir, fileName: "banned-ips.json", entries: bannedIps)
        } catch {
            GlobalErrorHandler.shared.handle(error)
        }
    }

    private func addEntry() {
        let name = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        let entry = ServerPlayerListService.PlayerEntry(uuid: "", name: name, level: nil, bypassesPlayerLimit: false, created: nil, source: nil, expires: nil, reason: nil, ip: nil)
        let isRunning = serverStatusManager.isServerRunning(serverId: server.id)

        switch selectedList {
        case "whitelist":
            whitelist.append(entry)
            if isRunning { sendCommand("whitelist add \(name)") }
        case "ops":
            ops.append(entry)
            if isRunning { sendCommand("op \(name)") }
        case "bannedPlayers":
            bannedPlayers.append(entry)
            if isRunning { sendCommand("ban \(name)") }
        case "bannedIps":
            var ipEntry = entry
            ipEntry.ip = name
            ipEntry.name = name
            bannedIps.append(ipEntry)
            if isRunning { sendCommand("ban-ip \(name)") }
        default:
            break
        }
        newName = ""
        if !isRunning { saveAll() }
    }

    private func removeEntry(from list: String, entry: ServerPlayerListService.PlayerEntry) {
        let isRunning = serverStatusManager.isServerRunning(serverId: server.id)
        switch list {
        case "whitelist":
            whitelist.removeAll { $0 == entry }
            if isRunning { sendCommand("whitelist remove \(entry.name)") }
        case "ops":
            ops.removeAll { $0 == entry }
            if isRunning { sendCommand("deop \(entry.name)") }
        case "bannedPlayers":
            bannedPlayers.removeAll { $0 == entry }
            if isRunning { sendCommand("pardon \(entry.name)") }
        case "bannedIps":
            bannedIps.removeAll { $0 == entry }
            if isRunning { sendCommand("pardon-ip \(entry.name)") }
        default:
            break
        }
        if !isRunning { saveAll() }
    }

    private var isRemoteServer: Bool {
        server.nodeId != ServerNode.local.id || server.javaPath == "java"
    }

    private func sendCommand(_ command: String) {
        if !isRemoteServer {
            ServerConsoleManager.shared.send(serverId: server.id, command: command)
            return
        }
        guard let node = serverNodeRepository.getNode(by: server.nodeId) else { return }
        Task {
            do {
                if server.consoleMode == .rcon {
                    _ = try await RCONService.execute(
                        host: node.host,
                        port: UInt16(server.rconPort),
                        password: server.rconPassword,
                        command: command
                    )
                } else {
                    do {
                        try await SSHNodeService.sendRemoteDirectCommand(node: node, serverName: server.name, command: command)
                    } catch {
                        _ = try await RCONService.execute(
                            host: node.host,
                            port: UInt16(server.rconPort),
                            password: server.rconPassword,
                            command: command
                        )
                    }
                }
            } catch {
                await MainActor.run {
                    GlobalErrorHandler.shared.handle(error)
                }
            }
        }
    }
}
