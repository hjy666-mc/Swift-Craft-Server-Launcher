import SwiftUI

struct ServerConsoleView: View {
    let server: ServerInstance
    @StateObject private var console = ServerConsoleManager.shared
    @EnvironmentObject var serverNodeRepository: ServerNodeRepository
    @State private var commandText: String = ""
    @State private var remoteLogText: String = ""
    @State private var remoteLogTask: Task<Void, Never>?
    @State private var rconPort: String = "25575"
    @State private var rconPassword: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("server.console.title".localized())
                .font(.headline)
            consoleOutput
            commandInput
        }
        .onAppear {
            rconPort = String(server.rconPort)
            rconPassword = server.rconPassword
            startRemoteLogPollingIfNeeded()
        }
        .onChange(of: server.id) { _, _ in
            remoteLogText = ""
            stopRemoteLogPolling()
            rconPort = String(server.rconPort)
            rconPassword = server.rconPassword
            startRemoteLogPollingIfNeeded()
        }
        .onDisappear { stopRemoteLogPolling() }
    }

    private var consoleOutput: some View {
        ScrollViewReader { proxy in
            ScrollView {
                Text(consoleText)
                    .font(.system(.caption, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                    .id("console_end")
            }
            .frame(minHeight: 220)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.black.opacity(0.06))
            )
            .onChange(of: consoleText) { _, _ in
                withAnimation(.easeOut(duration: 0.15)) {
                    proxy.scrollTo("console_end", anchor: .bottom)
                }
            }
        }
    }

    private var commandInput: some View {
        VStack(alignment: .leading, spacing: 8) {
            if isRemoteServer && isRconMode {
                HStack(spacing: 8) {
                    TextField("server.console.rcon.port".localized(), text: $rconPort)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 120)
                    SecureField("server.console.rcon.password".localized(), text: $rconPassword)
                        .textFieldStyle(.roundedBorder)
                }
            }
            HStack(spacing: 8) {
                TextField("server.console.placeholder".localized(), text: $commandText)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { sendCommand() }
                Button("server.console.send".localized()) { sendCommand() }
                    .disabled(commandText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }

    private func sendCommand() {
        let text = commandText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        commandText = ""
        if isRemoteServer && isRconMode {
            sendRemoteRCONCommand(text)
            return
        }
        if isRemoteServer && !isRconMode {
            sendRemoteDirectCommand(text)
            return
        }
        console.send(serverId: server.id, command: text)
    }

    private var isRemoteServer: Bool {
        server.nodeId != ServerNode.local.id || server.javaPath == "java"
    }

    private var isRconMode: Bool {
        server.consoleMode == .rcon
    }

    private var consoleText: String {
        if isRemoteServer {
            return remoteLogText
        }
        return console.logText(for: server.id)
    }

    private func startRemoteLogPollingIfNeeded() {
        guard isRemoteServer else { return }
        remoteLogTask?.cancel()
        let nodeId = server.nodeId
        let serverName = server.name
        remoteLogTask = Task {
            while !Task.isCancelled {
                await loadRemoteLog(nodeId: nodeId, serverName: serverName)
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
        }
    }

    private func stopRemoteLogPolling() {
        remoteLogTask?.cancel()
        remoteLogTask = nil
    }

    @MainActor
    private func loadRemoteLog(nodeId: String, serverName: String) async {
        guard let node = serverNodeRepository.getNode(by: nodeId) else { return }
        if let text = try? await SSHNodeService.fetchRemoteServerLog(node: node, serverName: serverName) {
            remoteLogText = text
        }
    }

    private func sendRemoteRCONCommand(_ command: String) {
        guard let node = serverNodeRepository.getNode(by: server.nodeId) else { return }
        guard let port = UInt16(rconPort.trimmingCharacters(in: .whitespacesAndNewlines)) else { return }
        let password = rconPassword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !password.isEmpty else {
            GlobalErrorHandler.shared.handle(
                GlobalError.validation(
                    chineseMessage: "请先输入 RCON 密码",
                    i18nKey: "error.validation.server_not_selected",
                    level: .notification
                )
            )
            return
        }
        Task {
            do {
                let output = try await RCONService.execute(host: node.host, port: port, password: password, command: command)
                await MainActor.run {
                    if !output.isEmpty {
                        remoteLogText += "\n[RCON] \(output)\n"
                    }
                }
            } catch {
                GlobalErrorHandler.shared.handle(error)
            }
        }
    }

    private func sendRemoteDirectCommand(_ command: String) {
        guard let node = serverNodeRepository.getNode(by: server.nodeId) else { return }
        Task {
            do {
                try await SSHNodeService.sendRemoteDirectCommand(node: node, serverName: server.name, command: command)
            } catch {
                do {
                    _ = try await RCONService.execute(
                        host: node.host,
                        port: UInt16(server.rconPort),
                        password: server.rconPassword,
                        command: command
                    )
                } catch {
                    GlobalErrorHandler.shared.handle(error)
                }
            }
        }
    }
}
