import Foundation

final class ServerLaunchUseCase: ObservableObject {
    @MainActor
    func launchServer(server: ServerInstance) async {
        if server.javaPath == "java" {
            if let remoteNode = await resolveRemoteNodeForLaunch(server: server) {
                await launchRemoteServer(server: server, node: remoteNode)
            } else {
                GlobalErrorHandler.shared.handle(
                    GlobalError.validation(
                        chineseMessage: "未找到可用的远程节点，请先检查节点连接与服务器目录",
                        i18nKey: "error.validation.server_not_selected",
                        level: .notification
                    )
                )
            }
            return
        }

        if server.nodeId != ServerNode.local.id {
            if let remoteNode = await resolveRemoteNodeForLaunch(server: server) {
                await launchRemoteServer(server: server, node: remoteNode)
            } else {
                GlobalErrorHandler.shared.handle(
                    GlobalError.validation(
                        chineseMessage: "未找到远程节点配置，无法启动该服务器",
                        i18nKey: "error.validation.server_not_selected",
                        level: .notification
                    )
                )
            }
            return
        }

        if let remoteNode = await resolveRemoteNodeForLaunch(server: server) {
            await launchRemoteServer(server: server, node: remoteNode)
            return
        }

        let serverDir = AppPaths.serverDirectory(serverName: server.name)
        let jarPath = serverDir.appendingPathComponent(server.serverJar).path
        try? applyLocalConsoleProperties(server: server, serverDir: serverDir)
        var resolvedJavaPath = server.javaPath
        if resolvedJavaPath.isEmpty {
            if let component = try? await ServerDownloadService.resolveJavaComponent(gameVersion: server.gameVersion) {
                resolvedJavaPath = await JavaManager.shared.ensureJavaExists(version: component)
            }
        }

        if server.serverType == .forge {
            do {
                try await ensureForgeReady(server: server, serverDir: serverDir)
            } catch {
                Logger.shared.error("Forge 预处理失败: \(error.localizedDescription)")
                GlobalErrorHandler.shared.handle(error)
                return
            }
        }

        await ensureAvailablePort(server: server, serverDir: serverDir)

        let (launchPath, args) = buildLaunchCommand(
            server: server,
            serverDir: serverDir,
            jarPath: jarPath,
            javaPath: resolvedJavaPath
        )

        let process = Process()
        process.executableURL = URL(fileURLWithPath: launchPath)
        process.arguments = args
        process.currentDirectoryURL = serverDir

        let inputPipe = Pipe()
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardInput = inputPipe
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        do {
            try process.run()
            ServerProcessManager.shared.storeProcess(serverId: server.id, process: process)
            ServerConsoleManager.shared.attach(serverId: server.id, input: inputPipe, output: outputPipe, error: errorPipe)
            ServerStatusManager.shared.setServerRunning(serverId: server.id, isRunning: true)
        } catch {
            Logger.shared.error("服务器启动失败: \(error.localizedDescription)")
            GlobalErrorHandler.shared.handle(error)
        }
    }

    @MainActor
    func stopServer(server: ServerInstance) async {
        if server.nodeId != ServerNode.local.id {
            await stopRemoteServer(server: server)
            return
        }
        _ = ServerProcessManager.shared.stopProcess(for: server.id)
        ServerStatusManager.shared.setServerRunning(serverId: server.id, isRunning: false)
        ServerConsoleManager.shared.detach(serverId: server.id)
    }

    @MainActor
    private func launchRemoteServer(server: ServerInstance, node: ServerNode) async {
        let custom = server.launchCommand.trimmingCharacters(in: .whitespacesAndNewlines)
        let launchCommand = custom.isEmpty
            ? buildRemoteDefaultLaunchCommand(serverJar: server.serverJar)
            : appendNoGuiIfNeeded(command: custom)

        do {
            try await SSHNodeService.ensureRemoteJava21(node: node)
            try await SSHNodeService.updateRemoteServerProperties(node: node, server: server)
            try await SSHNodeService.startRemoteServer(node: node, server: server, launchCommand: launchCommand)
            ServerStatusManager.shared.setServerRunning(serverId: server.id, isRunning: true)
        } catch {
            Logger.shared.error("远程服务器启动失败: \(error.localizedDescription)")
            GlobalErrorHandler.shared.handle(error)
            ServerStatusManager.shared.setServerRunning(serverId: server.id, isRunning: false)
        }
    }

    @MainActor
    private func stopRemoteServer(server: ServerInstance) async {
        guard let node = loadServerNode(nodeId: server.nodeId) else {
            ServerStatusManager.shared.setServerRunning(serverId: server.id, isRunning: false)
            return
        }
        do {
            try await SSHNodeService.stopRemoteServer(node: node, server: server)
        } catch {
            Logger.shared.error("远程服务器停止失败: \(error.localizedDescription)")
            GlobalErrorHandler.shared.handle(error)
        }
        ServerStatusManager.shared.setServerRunning(serverId: server.id, isRunning: false)
    }

    private func buildLaunchCommand(
        server: ServerInstance,
        serverDir: URL,
        jarPath: String,
        javaPath: String
    ) -> (String, [String]) {
        let custom = server.launchCommand.trimmingCharacters(in: .whitespacesAndNewlines)
        if !custom.isEmpty {
            let command = appendNoGuiIfNeeded(command: custom)
            return ("/bin/zsh", ["-lc", command])
        }

        let resolvedJavaPath = javaPath.isEmpty ? "java" : javaPath
        var args: [String] = []

        if server.xms > 0 { args.append("-Xms\(server.xms)M") }
        if server.xmx > 0 { args.append("-Xmx\(server.xmx)M") }
        if !server.jvmArguments.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            args.append(contentsOf: splitArgs(server.jvmArguments))
        }

        if server.serverType == .forge,
            let forgeCommand = buildForgeLaunchCommand(
                serverDir: serverDir,
                resolvedJavaPath: resolvedJavaPath
            ) {
            if forgeCommand.launchPath == "/bin/zsh" {
                return (forgeCommand.launchPath, forgeCommand.args)
            }
            let forgeArgs = args + forgeCommand.args
            return (forgeCommand.launchPath, forgeArgs)
        }

        args.append(contentsOf: ["-jar", jarPath, "nogui"])

        return (resolvedJavaPath, args)
    }

    private func ensureForgeReady(server: ServerInstance, serverDir: URL) async throws {
        if ForgeInstallerService.hasLaunchArtifacts(in: serverDir) {
            return
        }
        guard ForgeInstallerService.isInstallerJar(server.serverJar) else {
            return
        }
        try await ForgeInstallerService.install(server: server, serverDir: serverDir)
    }

    private func buildForgeLaunchCommand(
        serverDir: URL,
        resolvedJavaPath: String
    ) -> (launchPath: String, args: [String])? {
        let runScript = serverDir.appendingPathComponent("run.sh")
        if FileManager.default.fileExists(atPath: runScript.path) {
            return ("/bin/zsh", ["-lc", "./run.sh nogui"])
        }

        if let unixArgs = ForgeInstallerService.findUnixArgsFile(in: serverDir) {
            return (resolvedJavaPath, ["@\(unixArgs.path)", "nogui"])
        }

        if let forgeServerJar = ForgeInstallerService.findForgeServerJar(in: serverDir) {
            return (resolvedJavaPath, ["-jar", forgeServerJar.path, "nogui"])
        }

        return nil
    }

    private func ensureAvailablePort(server: ServerInstance, serverDir: URL) async {
        do {
            let propertiesURL = serverDir.appendingPathComponent("server.properties")
            guard FileManager.default.fileExists(atPath: propertiesURL.path) else { return }
            var properties = try ServerPropertiesService.readProperties(serverDir: serverDir)
            let portString = properties["server-port"] ?? "25565"
            let port = Int(portString) ?? 25565
            if ServerPortChecker.isPortAvailable(port) { return }

            if let newPort = ServerPortChecker.findAvailablePort(startingAt: port + 1) {
                properties["server-port"] = String(newPort)
                try ServerPropertiesService.writeProperties(serverDir: serverDir, properties: properties)
                GlobalErrorHandler.shared.handle(
                    GlobalError.validation(
                        chineseMessage: "端口 \(port) 被占用，已自动改为 \(newPort)",
                        i18nKey: "error.validation.port_in_use",
                        level: .notification
                    )
                )
            }
        } catch {
            GlobalErrorHandler.shared.handle(error)
        }
    }

    private func loadServerNode(nodeId: String) -> ServerNode? {
        let url = AppPaths.dataDirectory.appendingPathComponent("server_nodes.json")
        guard
            let data = try? Data(contentsOf: url),
            let nodes = try? JSONDecoder().decode([ServerNode].self, from: data)
        else { return nil }
        return nodes.first { $0.id == nodeId }
    }

    @MainActor
    private func resolveRemoteNodeForLaunch(server: ServerInstance) async -> ServerNode? {
        if server.nodeId != ServerNode.local.id, let node = loadServerNode(nodeId: server.nodeId) {
            return node
        }

        let localJar = AppPaths.serverDirectory(serverName: server.name).appendingPathComponent(server.serverJar)
        if FileManager.default.fileExists(atPath: localJar.path) {
            return nil
        }

        guard server.javaPath == "java" else {
            return nil
        }

        let url = AppPaths.dataDirectory.appendingPathComponent("server_nodes.json")
        guard
            let data = try? Data(contentsOf: url),
            let nodes = try? JSONDecoder().decode([ServerNode].self, from: data)
        else {
            return nil
        }
        let remoteNodes = nodes.filter { !$0.isLocal }
        for node in remoteNodes {
            if (try? await SSHNodeService.remoteServerDirectoryExists(node: node, serverName: server.name)) == true {
                return node
            }
        }
        return nil
    }

    private func appendNoGuiIfNeeded(command: String) -> String {
        let tokens = splitArgs(command)
        if tokens.contains("nogui") {
            return command
        }
        return command + " nogui"
    }

    private func splitArgs(_ input: String) -> [String] {
        var result: [String] = []
        var current = ""
        var inQuotes = false
        var quoteChar: Character = "\""

        for char in input {
            if char == "\"" || char == "'" {
                if inQuotes && char == quoteChar {
                    inQuotes = false
                } else if !inQuotes {
                    inQuotes = true
                    quoteChar = char
                } else {
                    current.append(char)
                }
                continue
            }

            if char == " " && !inQuotes {
                if !current.isEmpty {
                    result.append(current)
                    current = ""
                }
            } else {
                current.append(char)
            }
        }
        if !current.isEmpty {
            result.append(current)
        }
        return result
    }

    private func buildRemoteDefaultLaunchCommand(serverJar: String) -> String {
        """
        JAVA_BIN=""
        if command -v java21 >/dev/null 2>&1; then
          JAVA_BIN="$(command -v java21)"
        elif command -v java >/dev/null 2>&1; then
          JAVA_MAJOR="$(java -version 2>&1 | sed -n 's/.*version \"\\([0-9][0-9]*\\).*/\\1/p' | head -n 1)"
          if [ -n "$JAVA_MAJOR" ] && [ "$JAVA_MAJOR" -ge 21 ]; then
            JAVA_BIN="$(command -v java)"
          fi
        fi
        if [ -z "$JAVA_BIN" ]; then
          echo "ERROR: Java 21+ is required for this server."
          exit 1
        fi
        "$JAVA_BIN" -jar '\(serverJar)' nogui
        """
    }

    private func applyLocalConsoleProperties(server: ServerInstance, serverDir: URL) throws {
        var properties = try ServerPropertiesService.readProperties(serverDir: serverDir)
        properties["enable-rcon"] = server.consoleMode == .rcon ? "true" : "false"
        properties["rcon.port"] = String(server.rconPort)
        if server.consoleMode == .rcon {
            properties["rcon.password"] = server.rconPassword
        }
        try ServerPropertiesService.writeProperties(serverDir: serverDir, properties: properties)
    }
}
