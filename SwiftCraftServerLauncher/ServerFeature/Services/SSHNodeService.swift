import Foundation

enum SSHNodeService {
    struct ConnectionResult {
        let output: String
    }

    static func testConnectionAndPrepareDirectories(node: ServerNode, password: String) async throws -> ConnectionResult {
        let root = node.remoteRootPath.trimmingCharacters(in: .whitespacesAndNewlines)
        let command = """
        mkdir -p '\(escapeSingleQuotes(root))' '\(escapeSingleQuotes("\(root)/servers"))' '\(escapeSingleQuotes("\(root)/data"))' '\(escapeSingleQuotes("\(root)/logs"))' && echo __SCSL_OK__ && uname -a && whoami
        """
        let output = try await runExpectSSH(
            host: node.host,
            port: node.port,
            username: node.username,
            password: password,
            remoteCommand: command
        )
        guard output.contains("__SCSL_OK__") else {
            throw GlobalError.validation(
                chineseMessage: "SSH 连接成功但目录探测失败",
                i18nKey: "error.validation.server_not_selected",
                level: .notification
            )
        }
        return ConnectionResult(output: output)
    }

    static func prepareRemoteServerDirectoryAndDownload(
        node: ServerNode,
        serverName: String,
        target: ServerDownloadService.DownloadTarget
    ) async throws {
        let password = try loadPassword(for: node)
        let root = node.remoteRootPath.trimmingCharacters(in: .whitespacesAndNewlines)
        let serverDir = "\(root)/servers/\(serverName)"
        var headerPart = ""
        if let headers = target.headers, !headers.isEmpty {
            headerPart = headers.map { "-H '\(escapeSingleQuotes("\($0.key): \($0.value)"))'" }.joined(separator: " ")
        }
        let command = """
        mkdir -p '\(escapeSingleQuotes(serverDir))' && curl -fL \(headerPart) '\(escapeSingleQuotes(target.url.absoluteString))' -o '\(escapeSingleQuotes("\(serverDir)/\(target.fileName)"))' && printf "eula=true\\n" > '\(escapeSingleQuotes("\(serverDir)/eula.txt"))' && echo __SCSL_DONE__
        """
        let output = try await runExpectSSH(
            host: node.host,
            port: node.port,
            username: node.username,
            password: password,
            remoteCommand: command,
            timeoutSeconds: 1800
        )
        guard output.contains("__SCSL_DONE__") else {
            throw GlobalError.validation(
                chineseMessage: "远程创建失败，请检查 SSH 输出",
                i18nKey: "error.validation.server_not_selected",
                level: .notification
            )
        }
    }

    static func startRemoteServer(
        node: ServerNode,
        server: ServerInstance,
        launchCommand: String
    ) async throws {
        let password = try loadPassword(for: node)
        let root = node.remoteRootPath.trimmingCharacters(in: .whitespacesAndNewlines)
        let serverDir = "\(root)/servers/\(server.name)"
        let startCommand: String
        if server.consoleMode == .direct {
            let piped = "rm -f .scsl.stdin; mkfifo .scsl.stdin; tail -f .scsl.stdin | \(launchCommand)"
            startCommand = "nohup /bin/sh -lc '\(escapeSingleQuotes(piped))' >> scsl-server.log 2>&1 & echo $! > .scsl.pid"
        } else {
            startCommand = "nohup /bin/sh -lc '\(escapeSingleQuotes(launchCommand))' >> scsl-server.log 2>&1 & echo $! > .scsl.pid"
        }
        let command = """
        cd '\(escapeSingleQuotes(serverDir))' && \
        (test -f eula.txt || printf "eula=true\\n" > eula.txt) && \
        \(startCommand) && \
        sleep 1 && \
        if kill -0 $(cat .scsl.pid) 2>/dev/null; then echo __SCSL_STARTED__; else echo __SCSL_START_FAILED__; tail -n 80 scsl-server.log; fi
        """
        let output = try await runExpectSSH(
            host: node.host,
            port: node.port,
            username: node.username,
            password: password,
            remoteCommand: command
        )
        guard output.contains("__SCSL_STARTED__") else {
            throw GlobalError.validation(
                chineseMessage: "远程启动失败，请检查 SSH 输出: \(output.trimmingCharacters(in: .whitespacesAndNewlines))",
                i18nKey: "error.validation.server_not_selected",
                level: .notification
            )
        }
    }

    static func stopRemoteServer(
        node: ServerNode,
        server: ServerInstance
    ) async throws {
        let password = try loadPassword(for: node)
        let root = node.remoteRootPath.trimmingCharacters(in: .whitespacesAndNewlines)
        let serverDir = "\(root)/servers/\(server.name)"
        let command = """
        cd '\(escapeSingleQuotes(serverDir))' && if test -f .scsl.pid; then kill $(cat .scsl.pid) 2>/dev/null || true; rm -f .scsl.pid; fi && pkill -f '\(escapeSingleQuotes(server.serverJar))' || true && echo __SCSL_STOPPED__
        """
        _ = try await runExpectSSH(
            host: node.host,
            port: node.port,
            username: node.username,
            password: password,
            remoteCommand: command
        )
    }

    static func remoteServerDirectoryExists(node: ServerNode, serverName: String) async throws -> Bool {
        let password = try loadPassword(for: node)
        let root = node.remoteRootPath.trimmingCharacters(in: .whitespacesAndNewlines)
        let serverDir = "\(root)/servers/\(serverName)"
        let command = """
        if test -d '\(escapeSingleQuotes(serverDir))'; then echo __SCSL_EXISTS__; else echo __SCSL_MISSING__; fi
        """
        let output = try await runExpectSSH(
            host: node.host,
            port: node.port,
            username: node.username,
            password: password,
            remoteCommand: command
        )
        return output.contains("__SCSL_EXISTS__")
    }

    static func fetchRemoteServerLog(
        node: ServerNode,
        serverName: String,
        maxLines: Int = 300
    ) async throws -> String {
        let password = try loadPassword(for: node)
        let root = node.remoteRootPath.trimmingCharacters(in: .whitespacesAndNewlines)
        let serverDir = "\(root)/servers/\(serverName)"
        let command = """
        cd '\(escapeSingleQuotes(serverDir))' && if test -f scsl-server.log; then tail -n \(maxLines) scsl-server.log; else echo ""; fi
        """
        return try await runExpectSSH(
            host: node.host,
            port: node.port,
            username: node.username,
            password: password,
            remoteCommand: command
        )
    }

    static func updateRemoteServerProperties(node: ServerNode, server: ServerInstance) async throws {
        let password = try loadPassword(for: node)
        let root = node.remoteRootPath.trimmingCharacters(in: .whitespacesAndNewlines)
        let serverDir = "\(root)/servers/\(server.name)"
        let enableRcon = server.consoleMode == .rcon ? "true" : "false"
        let command = """
        cd '\(escapeSingleQuotes(serverDir))' && touch server.properties && \
        if grep -q '^enable-rcon=' server.properties; then sed -i.bak 's/^enable-rcon=.*/enable-rcon=\(enableRcon)/' server.properties; else echo 'enable-rcon=\(enableRcon)' >> server.properties; fi && \
        if grep -q '^rcon.port=' server.properties; then sed -i.bak 's/^rcon.port=.*/rcon.port=\(server.rconPort)/' server.properties; else echo 'rcon.port=\(server.rconPort)' >> server.properties; fi && \
        if grep -q '^rcon.password=' server.properties; then sed -i.bak 's|^rcon.password=.*|rcon.password=\(escapeSingleQuotes(server.rconPassword))|' server.properties; else echo 'rcon.password=\(escapeSingleQuotes(server.rconPassword))' >> server.properties; fi && \
        rm -f server.properties.bak && echo __SCSL_PROPS_OK__
        """
        let output = try await runExpectSSH(
            host: node.host,
            port: node.port,
            username: node.username,
            password: password,
            remoteCommand: command
        )
        guard output.contains("__SCSL_PROPS_OK__") else {
            throw GlobalError.validation(
                chineseMessage: "远程配置 server.properties 失败",
                i18nKey: "error.validation.server_not_selected",
                level: .notification
            )
        }
    }

    static func ensureRemoteJava21(node: ServerNode) async throws {
        let password = try loadPassword(for: node)
        let command = """
        has_java21() {
          if command -v java21 >/dev/null 2>&1; then
            return 0
          fi
          if command -v java >/dev/null 2>&1; then
            JAVA_VERSION_LINE="$(java -version 2>&1 | head -n 1)"
            JAVA_MAJOR="$(printf "%s" "$JAVA_VERSION_LINE" | cut -d '"' -f 2 | cut -d '.' -f 1)"
            if test -n "$JAVA_MAJOR" && test "$JAVA_MAJOR" -ge 21; then
              return 0
            fi
          fi
          return 1
        }

        if has_java21; then
          echo __SCSL_JAVA21_OK__
          exit 0
        fi

        INSTALL_STATUS="unknown"
        if command -v apt-get >/dev/null 2>&1; then
          export DEBIAN_FRONTEND=noninteractive
          apt-get update -y && (apt-get install -y openjdk-21-jre-headless || apt-get install -y openjdk-21-jdk-headless) && INSTALL_STATUS="ok" || INSTALL_STATUS="fail"
        elif command -v dnf >/dev/null 2>&1; then
          dnf install -y java-21-openjdk-headless && INSTALL_STATUS="ok" || INSTALL_STATUS="fail"
        elif command -v yum >/dev/null 2>&1; then
          (yum install -y java-21-openjdk-headless || yum install -y java-21-openjdk) && INSTALL_STATUS="ok" || INSTALL_STATUS="fail"
        elif command -v zypper >/dev/null 2>&1; then
          zypper --non-interactive install java-21-openjdk-headless && INSTALL_STATUS="ok" || INSTALL_STATUS="fail"
        elif command -v pacman >/dev/null 2>&1; then
          pacman -Sy --noconfirm jre21-openjdk && INSTALL_STATUS="ok" || INSTALL_STATUS="fail"
        elif command -v apk >/dev/null 2>&1; then
          apk add --no-cache openjdk21-jre && INSTALL_STATUS="ok" || INSTALL_STATUS="fail"
        else
          INSTALL_STATUS="no_package_manager"
        fi

        if has_java21; then
          echo __SCSL_JAVA21_OK__
        else
          echo __SCSL_JAVA21_FAIL__:$INSTALL_STATUS
        fi
        exit 0
        """
        let output = try await runExpectSSH(
            host: node.host,
            port: node.port,
            username: node.username,
            password: password,
            remoteCommand: command
        )
        guard output.contains("__SCSL_JAVA21_OK__") else {
            throw GlobalError.validation(
                chineseMessage: "远程未能自动安装 Java 21，请手动安装后重试。输出: \(output.trimmingCharacters(in: .whitespacesAndNewlines))",
                i18nKey: "error.validation.server_not_selected",
                level: .notification
            )
        }
    }

    static func execute(node: ServerNode, remoteCommand: String, timeoutSeconds: Int = 60) async throws -> String {
        let password = try loadPassword(for: node)
        return try await runExpectSSH(
            host: node.host,
            port: node.port,
            username: node.username,
            password: password,
            remoteCommand: remoteCommand,
            timeoutSeconds: timeoutSeconds
        )
    }

    static func readRemoteServerProperties(node: ServerNode, serverName: String) async throws -> [String: String] {
        let root = node.remoteRootPath.trimmingCharacters(in: .whitespacesAndNewlines)
        let serverDir = "\(root)/servers/\(serverName)"
        let command = "cd '\(escapeSingleQuotes(serverDir))' && if test -f server.properties; then cat server.properties; fi"
        let content = try await execute(node: node, remoteCommand: command)
        return parseProperties(content)
    }

    static func writeRemoteServerProperties(node: ServerNode, serverName: String, properties: [String: String]) async throws {
        let root = node.remoteRootPath.trimmingCharacters(in: .whitespacesAndNewlines)
        let serverDir = "\(root)/servers/\(serverName)"
        let keys = properties.keys.sorted()
        let lines = keys.map { "\($0)=\(properties[$0] ?? "")" }
        let content = lines.joined(separator: "\n") + "\n"
        let base64 = Data(content.utf8).base64EncodedString()
        let command = "cd '\(escapeSingleQuotes(serverDir))' && printf '%s' '\(base64)' | base64 -d > server.properties"
        _ = try await execute(node: node, remoteCommand: command)
    }

    static func listRemoteWorlds(node: ServerNode, serverName: String) async throws -> [String] {
        let root = node.remoteRootPath.trimmingCharacters(in: .whitespacesAndNewlines)
        let serverDir = "\(root)/servers/\(serverName)"
        let command = "cd '\(escapeSingleQuotes(serverDir))' && ls -1d world* 2>/dev/null || true"
        let output = try await execute(node: node, remoteCommand: command)
        return output
            .split(separator: "\n")
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    static func removeRemoteWorld(node: ServerNode, serverName: String, worldName: String) async throws {
        let root = node.remoteRootPath.trimmingCharacters(in: .whitespacesAndNewlines)
        let serverDir = "\(root)/servers/\(serverName)"
        let command = "cd '\(escapeSingleQuotes(serverDir))' && rm -rf '\(escapeSingleQuotes(worldName))'"
        _ = try await execute(node: node, remoteCommand: command)
    }

    static func sendRemoteDirectCommand(node: ServerNode, serverName: String, command: String) async throws {
        let root = node.remoteRootPath.trimmingCharacters(in: .whitespacesAndNewlines)
        let serverDir = "\(root)/servers/\(serverName)"
        let cmd = command.replacingOccurrences(of: "'", with: "'\"'\"'")
        let remote = "cd '\(escapeSingleQuotes(serverDir))' && test -p .scsl.stdin && printf '%s\\n' '\(cmd)' >> .scsl.stdin"
        _ = try await execute(node: node, remoteCommand: remote)
    }

    private static func parseProperties(_ content: String) -> [String: String] {
        var result: [String: String] = [:]
        for line in content.split(separator: "\n", omittingEmptySubsequences: false) {
            let raw = String(line)
            if raw.trimmingCharacters(in: .whitespaces).isEmpty { continue }
            if raw.hasPrefix("#") { continue }
            if let idx = raw.firstIndex(of: "=") {
                let key = String(raw[..<idx]).trimmingCharacters(in: .whitespaces)
                let value = String(raw[raw.index(after: idx)...]).trimmingCharacters(in: .whitespaces)
                result[key] = value
            }
        }
        return result
    }

    private static func runExpectSSH(
        host: String,
        port: Int,
        username: String,
        password: String,
        remoteCommand: String,
        timeoutSeconds: Int = 60
    ) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            let outputPipe = Pipe()
            let errorPipe = Pipe()
            process.standardOutput = outputPipe
            process.standardError = errorPipe
            process.executableURL = URL(fileURLWithPath: "/usr/bin/expect")

            let script = """
            set timeout \(timeoutSeconds)
            spawn ssh -p \(port) -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \(username)@\(host) "\(escapeDoubleQuotes(remoteCommand))"
            expect {
                -re {.*yes/no.*} { send "yes\\r"; exp_continue }
                -re {.*[Pp]assword:.*} { send "\(escapeExpectString(password))\\r"; exp_continue }
                timeout { exit 124 }
                eof
            }
            catch wait result
            set code [lindex $result 3]
            exit $code
            """
            process.arguments = ["-c", script]

            process.terminationHandler = { _ in
            let outData = outputPipe.fileHandleForReading.readDataToEndOfFile()
            let errData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let out = String(data: outData, encoding: .utf8) ?? ""
            let err = String(data: errData, encoding: .utf8) ?? ""
            let merged = (out + (err.isEmpty ? "" : "\n" + err)).trimmingCharacters(in: .whitespacesAndNewlines)
            if process.terminationStatus == 0 {
                    continuation.resume(returning: merged)
            } else {
                    let lower = merged.lowercased()
                    if lower.contains("pam_nologin") || lower.contains("system is booting up") {
                        continuation.resume(throwing: GlobalError.validation(
                            chineseMessage: "远程系统正在启动中，SSH 暂不可用，请稍后重试（可先使用 RCON 指令）",
                            i18nKey: "error.validation.server_not_selected",
                            level: .notification
                        ))
                        return
                    }
                    continuation.resume(throwing: GlobalError.validation(
                        chineseMessage: "SSH 执行失败: \(merged)",
                        i18nKey: "error.validation.server_not_selected",
                        level: .notification
                    ))
            }
            }

            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    private static func loadPassword(for node: ServerNode) throws -> String {
        let storageURL = AppPaths.dataDirectory.appendingPathComponent("server_node_passwords.json")
        guard
            let data = try? Data(contentsOf: storageURL),
            let dict = try? JSONDecoder().decode([String: String].self, from: data),
            let password = dict[node.id],
            !password.isEmpty
        else {
            throw GlobalError.validation(
                chineseMessage: "未找到节点密码，请重新执行连接测试",
                i18nKey: "error.validation.server_not_selected",
                level: .notification
            )
        }
        return password
    }

    private static func escapeDoubleQuotes(_ value: String) -> String {
        value.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "$", with: "\\$")
            .replacingOccurrences(of: "[", with: "\\[")
            .replacingOccurrences(of: "]", with: "\\]")
    }

    private static func escapeExpectString(_ value: String) -> String {
        value.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "$", with: "\\$")
            .replacingOccurrences(of: "[", with: "\\[")
            .replacingOccurrences(of: "]", with: "\\]")
    }

    private static func escapeSingleQuotes(_ value: String) -> String {
        value.replacingOccurrences(of: "'", with: "'\"'\"'")
    }
}
