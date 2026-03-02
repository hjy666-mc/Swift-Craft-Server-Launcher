import SwiftUI

struct ServerConsoleView: View {
    let server: ServerInstance
    @StateObject private var console = ServerConsoleManager.shared
    @EnvironmentObject var serverNodeRepository: ServerNodeRepository
    @State private var commandText: String = ""
    @State private var remoteLogText: String = ""
    @State private var rconOutputText: String = ""
    @State private var remoteLogTask: Task<Void, Never>?
    @State private var localLogTask: Task<Void, Never>?
    @State private var localLogText: String = ""
    @State private var rconPort: String = "25575"
    @State private var rconPassword: String = ""
    @State private var lastRemoteLogError: String = ""

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
            startLocalLogPollingIfNeeded()
        }
        .onChange(of: server.id) { _, _ in
            remoteLogText = ""
            rconOutputText = ""
            localLogText = ""
            stopRemoteLogPolling()
            stopLocalLogPolling()
            rconPort = String(server.rconPort)
            rconPassword = server.rconPassword
            startRemoteLogPollingIfNeeded()
            startLocalLogPollingIfNeeded()
        }
        .onDisappear {
            stopRemoteLogPolling()
            stopLocalLogPolling()
        }
    }

    private var consoleOutput: some View {
        ScrollViewReader { proxy in
            ScrollView {
                Text(attributedConsoleText)
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
            if shouldShowRconInputs {
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
        if ServerProcessManager.shared.getProcess(for: server.id) != nil {
            console.send(serverId: server.id, command: text)
            return
        }
        sendLocalRCONCommand(text)
    }

    private var isRemoteServer: Bool {
        server.nodeId != ServerNode.local.id || server.javaPath == "java"
    }

    private var isRconMode: Bool {
        server.consoleMode == .rcon
    }

    private var shouldShowRconInputs: Bool {
        (isRemoteServer && isRconMode) || (!isRemoteServer && ServerProcessManager.shared.getProcess(for: server.id) == nil)
    }

    private var consoleText: String {
        let localSystem = console.logText(for: server.id)
        if isRemoteServer {
            return [localSystem, remoteLogText, rconOutputText]
                .filter { !$0.isEmpty }
                .joined(separator: "\n")
        }
        if !localLogText.isEmpty {
            return [localSystem, localLogText, rconOutputText]
                .filter { !$0.isEmpty }
                .joined(separator: "\n")
        }
        return localSystem
    }

    private var consoleLines: [String] {
        let text = consoleText
        if text.isEmpty { return [] }
        return text.components(separatedBy: "\n")
    }

    private var attributedConsoleText: AttributedString {
        var result = AttributedString()
        let lines = consoleLines
        for (idx, line) in lines.enumerated() {
            var segment = AttributedString(line)
            var container = AttributeContainer()
            container.foregroundColor = colorForLine(line)
            segment.mergeAttributes(container)
            result.append(segment)
            if idx < lines.count - 1 {
                result.append(AttributedString("\n"))
            }
        }
        return result
    }

    private func startRemoteLogPollingIfNeeded() {
        guard isRemoteServer else { return }
        remoteLogTask?.cancel()
        let nodeId = server.nodeId
        let serverName = server.name
        remoteLogTask = Task {
            await loadRemoteLog(nodeId: nodeId, serverName: serverName)
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

    private func startLocalLogPollingIfNeeded() {
        guard !isRemoteServer else { return }
        guard ServerProcessManager.shared.getProcess(for: server.id) == nil else { return }
        localLogTask?.cancel()
        let serverName = server.name
        localLogTask = Task {
            await loadLocalLog(serverName: serverName)
            while !Task.isCancelled {
                await loadLocalLog(serverName: serverName)
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
        }
    }

    private func stopLocalLogPolling() {
        localLogTask?.cancel()
        localLogTask = nil
    }

    @MainActor
    private func loadLocalLog(serverName: String) async {
        let serverDir = AppPaths.serverDirectory(serverName: serverName)
        let candidates = [
            serverDir.appendingPathComponent("logs/latest.log"),
            serverDir.appendingPathComponent("latest.log"),
            serverDir.appendingPathComponent("scsl-server.log"),
            serverDir.appendingPathComponent("server.log"),
        ]
        for file in candidates where FileManager.default.fileExists(atPath: file.path) {
            if let text = try? String(contentsOf: file, encoding: .utf8), !text.isEmpty {
                localLogText = text.components(separatedBy: .newlines).suffix(300).joined(separator: "\n")
                return
            }
        }
    }

    @MainActor
    private func loadRemoteLog(nodeId: String, serverName: String) async {
        guard let node = serverNodeRepository.getNode(by: nodeId) else { return }
        do {
            let text = try await SSHNodeService.fetchRemoteServerLog(node: node, serverName: serverName)
            let filtered = filterNoisyRconLifecycleLogs(text)
            if !filtered.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                remoteLogText = filtered
            }
            lastRemoteLogError = ""
        } catch {
            let message = error.localizedDescription
            lastRemoteLogError = message
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
            var lastError: Error?
            for attempt in 1...8 {
                do {
                    let output: String
                    do {
                        output = try await RCONService.execute(
                            host: node.host,
                            port: port,
                            password: password,
                            command: command
                        )
                    } catch {
                        output = try await SSHNodeService.executeRemoteRCON(
                            node: node,
                            serverName: server.name,
                            port: Int(port),
                            password: password,
                            command: command
                        )
                    }
                    await MainActor.run {
                        if !output.isEmpty {
                            rconOutputText += "\n[RCON] \(output)\n"
                        } else {
                            rconOutputText += "\n[RCON] OK\n"
                        }
                    }
                    return
                } catch {
                    lastError = error
                    if attempt < 8 && shouldRetryRcon(error: error) {
                        try? await Task.sleep(nanoseconds: 700_000_000)
                        continue
                    }
                    break
                }
            }
            if let lastError {
                await MainActor.run {
                    GlobalErrorHandler.shared.handle(lastError)
                }
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

    private func sendLocalRCONCommand(_ command: String) {
        let resolvedPort: UInt16 = {
            if let p = UInt16(rconPort.trimmingCharacters(in: .whitespacesAndNewlines)) {
                return p
            }
            if let props = try? ServerPropertiesService.readProperties(serverDir: AppPaths.serverDirectory(serverName: server.name)),
               let portText = props["rcon.port"],
               let p = UInt16(portText.trimmingCharacters(in: .whitespacesAndNewlines)) {
                rconPort = String(p)
                return p
            }
            return UInt16(server.rconPort)
        }()
        let password: String = {
            let typed = rconPassword.trimmingCharacters(in: .whitespacesAndNewlines)
            if !typed.isEmpty { return typed }
            if let props = try? ServerPropertiesService.readProperties(serverDir: AppPaths.serverDirectory(serverName: server.name)),
               let pass = props["rcon.password"]?.trimmingCharacters(in: .whitespacesAndNewlines),
               !pass.isEmpty {
                rconPassword = pass
                return pass
            }
            return server.rconPassword.trimmingCharacters(in: .whitespacesAndNewlines)
        }()
        guard !password.isEmpty else {
            GlobalErrorHandler.shared.handle(
                GlobalError.validation(
                    chineseMessage: "当前会话未附着到原进程，且未找到 RCON 密码。请在 server.properties 中配置 rcon.password 后重试",
                    i18nKey: "error.validation.server_not_selected",
                    level: .notification
                )
            )
            return
        }
        Task {
            do {
                let output = try await RCONService.execute(
                    host: "127.0.0.1",
                    port: resolvedPort,
                    password: password,
                    command: command
                )
                await MainActor.run {
                    if !output.isEmpty {
                        rconOutputText += "\n[RCON] \(output)\n"
                    }
                }
            } catch {
                await MainActor.run {
                    GlobalErrorHandler.shared.handle(error)
                }
            }
        }
    }

    private func filterNoisyRconLifecycleLogs(_ raw: String) -> String {
        raw
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
            .filter { line in
                !(line.contains("RCON Client /127.0.0.1") &&
                  (line.contains("started") || line.contains("shutting down")))
            }
            .joined(separator: "\n")
    }

    private func colorForLine(_ line: String) -> Color {
        if line.contains("[ERROR]") || line.contains("Exception") || line.contains("❌") {
            return .red
        }
        if line.contains("[WARN]") || line.contains("WARN") || line.contains("⚠️") {
            return .orange
        }
        if line.contains("[INFO]") || line.contains("INFO") || line.contains("ℹ️") {
            return .primary
        }
        if line.contains("Starting") || line.contains("Done (") || line.contains("RCON running on") || line.contains("✅") {
            return .green
        }
        if line.contains("🔍") || line.contains("[DEBUG]") {
            return .secondary
        }
        if line.hasPrefix("[RCON]") || line.contains("SCSL") {
            return .blue
        }
        return .primary
    }

    private func shouldRetryRcon(error: Error) -> Bool {
        let text = error.localizedDescription.lowercased()
        return text.contains("connection refused")
            || text.contains("timed out")
            || text.contains("eof")
            || text.contains("连接失败")
    }
}
