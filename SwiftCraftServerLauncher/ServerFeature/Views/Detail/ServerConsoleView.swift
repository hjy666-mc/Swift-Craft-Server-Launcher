import SwiftUI
import AppKit

struct ServerConsoleView: View {
    let server: ServerInstance
    @StateObject private var console = ServerConsoleManager.shared
    @StateObject private var generalSettings = GeneralSettingsManager.shared
    @EnvironmentObject var serverNodeRepository: ServerNodeRepository
    @State private var commandText: String = ""
    @State private var remoteLogText: String = ""
    @State private var rconOutputText: String = ""
    @State private var remoteLogTask: Task<Void, Never>?
    @State private var localLogTask: Task<Void, Never>?
    @State private var localLogText: String = ""
    @State private var lastRemotePolledText: String = ""
    @State private var lastLocalPolledText: String = ""
    @State private var rconPort: String = "25575"
    @State private var rconPassword: String = ""
    @State private var lastRemoteLogError: String = ""
    @State private var commandHistory: [String] = []
    @State private var historyIndex: Int?
    @FocusState private var commandFieldFocused: Bool
    @State private var keyMonitor: Any?
    @State private var renderedConsoleText: AttributedString = AttributedString()
    @State private var renderTask: Task<Void, Never>?
    @State private var progressiveRenderTask: Task<Void, Never>?
    @State private var isRenderingConsole: Bool = false
    @State private var renderLineLimit: Int = 100
    @State private var hasNewLogsWhileBrowsingHistory: Bool = false
    @State private var followBottom: Bool = true

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("server.console.title".localized())
                    .font(.headline)
                Spacer()
                Button {
                    clearConsole()
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.plain)
                .help("common.clear".localized())
            }
            terminalSurface
        }
        .onAppear {
            rconPort = String(server.rconPort)
            rconPassword = server.rconPassword
            loadCommandHistory()
            startRemoteLogPollingIfNeeded()
            startLocalLogPollingIfNeeded()
            DispatchQueue.main.async {
                commandFieldFocused = true
            }
            installKeyMonitor()
            if let cached = console.renderedText(for: server.id), !cached.characters.isEmpty {
                renderedConsoleText = cached
            } else {
                refreshRenderedConsole()
            }
            renderLineLimit = 100
            hasNewLogsWhileBrowsingHistory = false
            followBottom = true
            scheduleProgressiveRenderIfNeeded()
        }
        .onChange(of: server.id) { _, _ in
            renderedConsoleText = AttributedString()
            isRenderingConsole = true
            remoteLogText = ""
            rconOutputText = ""
            localLogText = ""
            lastRemotePolledText = ""
            lastLocalPolledText = ""
            stopRemoteLogPolling()
            stopLocalLogPolling()
            rconPort = String(server.rconPort)
            rconPassword = server.rconPassword
            commandHistory = []
            historyIndex = nil
            loadCommandHistory()
            startRemoteLogPollingIfNeeded()
            startLocalLogPollingIfNeeded()
            DispatchQueue.main.async {
                commandFieldFocused = true
            }
            renderLineLimit = 100
            refreshRenderedConsole()
            scheduleProgressiveRenderIfNeeded()
        }
        .onDisappear {
            stopRemoteLogPolling()
            stopLocalLogPolling()
            removeKeyMonitor()
            console.setRenderedText(serverId: server.id, text: renderedConsoleText)
            renderTask?.cancel()
            progressiveRenderTask?.cancel()
            renderTask = nil
            progressiveRenderTask = nil
            isRenderingConsole = false
        }
        .onChange(of: consoleText) { _, _ in
            if !followBottom {
                hasNewLogsWhileBrowsingHistory = true
            }
            refreshRenderedConsole()
            scheduleProgressiveRenderIfNeeded()
        }
    }

    private var terminalSurface: some View {
        VStack(spacing: 0) {
            consoleOutput
            commandInput
        }
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.black.opacity(0.06))
        )
    }

    private var consoleOutput: some View {
        ScrollViewReader { proxy in
            ScrollView {
                Text(attributedConsoleText)
                    .font(.system(.caption, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .id("console_end")
            }
            .frame(minHeight: 220)
            .onChange(of: consoleText) { _, _ in
                guard followBottom else { return }
                withAnimation(.easeOut(duration: 0.12)) {
                    proxy.scrollTo("console_end", anchor: .bottom)
                }
            }
            .onChange(of: renderedConsoleText) { _, _ in
                guard followBottom else { return }
                withAnimation(.easeOut(duration: 0.12)) {
                    proxy.scrollTo("console_end", anchor: .bottom)
                }
            }
            .onAppear {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    guard followBottom else { return }
                    proxy.scrollTo("console_end", anchor: .bottom)
                }
            }
            .overlay(alignment: .bottomTrailing) {
                if isRenderingConsole {
                    HStack(spacing: 6) {
                        ProgressView()
                            .controlSize(.small)
                        Text("正在渲染日志...")
                    }
                    .font(.caption)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(.regularMaterial, in: Capsule())
                    .padding(10)
                } else if hasNewLogsWhileBrowsingHistory {
                    Button {
                        followBottom = true
                        hasNewLogsWhileBrowsingHistory = false
                        withAnimation(.easeOut(duration: 0.15)) {
                            proxy.scrollTo("console_end", anchor: .bottom)
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.down.to.line")
                            Text("到底部")
                        }
                        .font(.caption)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(.regularMaterial, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .padding(10)
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
                .padding(.horizontal, 8)
            }
            HStack(spacing: 8) {
                Text(">")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                TextField(
                    "",
                    text: $commandText
                )
                    .textFieldStyle(.plain)
                    .font(.system(.caption, design: .monospaced))
                    .focused($commandFieldFocused)
                    .onSubmit { sendCommand() }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            Button("") { sendInterrupt() }
                .keyboardShortcut("c", modifiers: [.control])
                .frame(width: 0, height: 0)
                .hidden()
            Button("") { clearConsole() }
                .keyboardShortcut("l", modifiers: [.control])
                .frame(width: 0, height: 0)
                .hidden()
        }
    }

    private func sendCommand() {
        let text = commandText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        commandText = ""
        appendHistory(text)
        historyIndex = nil
        if isRemoteServer {
            sendRemoteDirectCommand(text)
            return
        }
        if ServerProcessManager.shared.getProcess(for: server.id) != nil {
            console.send(serverId: server.id, command: text)
            return
        }
        if LocalServerDirectService.isDirectModeAvailable(server: server) {
            do {
                try LocalServerDirectService.sendCommand(server: server, command: text)
            } catch {
                GlobalErrorHandler.shared.handle(error)
            }
            return
        }
        sendLocalRCONCommand(text)
    }

    private func clearConsole() {
        console.clear(serverId: server.id)
        remoteLogText = ""
        localLogText = ""
        rconOutputText = ""
        lastLocalPolledText = currentLocalLogSnapshot(serverName: server.name)
        if isRemoteServer, let node = resolvedRemoteNode(nodeId: server.nodeId) {
            Task { @MainActor in
                if let snapshot = try? await SSHNodeService.fetchRemoteServerLog(node: node, serverName: server.name) {
                    lastRemotePolledText = filterNoisyRconLifecycleLogs(snapshot).trimmingCharacters(in: .whitespacesAndNewlines)
                } else {
                    lastRemotePolledText = ""
                }
            }
        } else {
            lastRemotePolledText = ""
        }
    }

    private func sendInterrupt() {
        let isForce = true
        let hint = "[SCSL] 强制停止中..."
        if isRemoteServer {
            if remoteLogText.isEmpty {
                remoteLogText = hint
            } else {
                remoteLogText += "\n" + hint
            }
        } else {
            if localLogText.isEmpty {
                localLogText = hint
            } else {
                localLogText += "\n" + hint
            }
        }
        if isRemoteServer {
            guard let node = resolvedRemoteNode(nodeId: server.nodeId) else { return }
            Task {
                do {
                    try await SSHNodeService.sendRemoteInterrupt(node: node, serverName: server.name, force: isForce)
                    await MainActor.run {
                        ServerStatusManager.shared.setServerRunning(serverId: server.id, isRunning: false)
                        ServerStatusManager.shared.setServerLaunching(serverId: server.id, isLaunching: false)
                    }
                } catch {
                    GlobalErrorHandler.shared.handle(error)
                }
            }
            return
        }
        if ServerProcessManager.shared.getProcess(for: server.id) != nil {
            _ = ServerProcessManager.shared.stopProcess(for: server.id)
            return
        }
        if LocalServerDirectService.isDirectModeAvailable(server: server) {
            Task {
                do {
                    _ = try await Task.detached(priority: .userInitiated) {
                        try LocalServerDirectService.sendInterrupt(server: server, force: isForce)
                    }.value
                    await MainActor.run {
                        ServerStatusManager.shared.setServerRunning(serverId: server.id, isRunning: false)
                        ServerStatusManager.shared.setServerLaunching(serverId: server.id, isLaunching: false)
                    }
                } catch {
                    GlobalErrorHandler.shared.handle(error)
                }
            }
        }
    }

    private var isRemoteServer: Bool {
        server.nodeId != ServerNode.local.id || server.javaPath == "java"
    }

    private var isRconMode: Bool {
        false
    }

    private var shouldShowRconInputs: Bool {
        isRemoteServer && isRconMode
    }

    private var consoleText: String {
        let localSystem = console.logText(for: server.id)
        if isRemoteServer {
            return [localSystem, remoteLogText]
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
        let lines = text.components(separatedBy: "\n")
        if lines.count <= renderLineLimit {
            return lines
        }
        return Array(lines.suffix(renderLineLimit))
    }

    private var allConsoleLines: [String] {
        let text = consoleText
        guard !text.isEmpty else { return [] }
        return text.components(separatedBy: "\n")
    }

    private var attributedConsoleText: AttributedString {
        renderedConsoleText
    }

    private func refreshRenderedConsole() {
        renderTask?.cancel()
        isRenderingConsole = true
        renderTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 120_000_000)
            if Task.isCancelled { return }
            let lines = consoleLines
            var result = AttributedString()
            for (idx, line) in lines.enumerated() {
                if Task.isCancelled { return }
                result.append(styledLine(line))
                if idx < lines.count - 1 {
                    result.append(AttributedString("\n"))
                }
            }
            renderedConsoleText = result
            console.setRenderedText(serverId: server.id, text: result)
            isRenderingConsole = false
        }
    }

    private func scheduleProgressiveRenderIfNeeded() {
        progressiveRenderTask?.cancel()
        let lines = allConsoleLines
        let target = targetRenderLineLimit(from: lines)
        guard target > renderLineLimit else { return }
        progressiveRenderTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 32_000_000)
                if Task.isCancelled { return }
                let shouldContinue = await MainActor.run { () -> Bool in
                    guard renderLineLimit < target else { return false }
                    renderLineLimit = min(renderLineLimit + 1, target)
                    refreshRenderedConsole()
                    return renderLineLimit < target
                }
                if !shouldContinue { return }
            }
        }
    }

    private func targetRenderLineLimit(from lines: [String]) -> Int {
        let base = 100
        guard !lines.isEmpty else { return base }
        let startMarkers = [
            "Starting net.minecraft.server.Main",
            "[SCSL] 服务器启动中",
            "[SCSL] server starting",
        ]
        let markerIndexes = lines.indices.filter { idx in
            let line = lines[idx]
            return startMarkers.contains { line.contains($0) }
        }
        if markerIndexes.count >= 2, let secondLast = markerIndexes.dropLast().last {
            return max(base, lines.count - secondLast)
        }
        if let only = markerIndexes.last {
            return max(base, lines.count - only)
        }
        return max(base, lines.count)
    }

    private func styledLine(_ line: String) -> AttributedString {
        if !generalSettings.enableConsoleColoredOutput {
            var plain = AttributedString(line)
            plain.foregroundColor = .primary
            return plain
        }
        let baseColor: Color = .primary
        let ns = line as NSString
        let full = NSRange(location: 0, length: ns.length)
        var colors = Array(repeating: baseColor, count: ns.length)

        func paint(_ regex: NSRegularExpression, color: Color) {
            for m in regex.matches(in: line, range: full) {
                guard m.range.length > 0 else { continue }
                for i in m.range.location..<(m.range.location + m.range.length) {
                    colors[i] = color
                }
            }
        }

        if let bracketRegex = try? NSRegularExpression(pattern: #"[\[\]]"#) {
            paint(bracketRegex, color: .primary)
        }
        if let timeRegex = try? NSRegularExpression(pattern: #"\b\d{2}:\d{2}:\d{2}\b"#) {
            paint(timeRegex, color: .blue)
        }
        if let componentRegex = try? NSRegularExpression(pattern: #"\[([^\]/\]]+)\]"#) {
            for m in componentRegex.matches(in: line, range: full) {
                guard m.range.length > 2 else { continue }
                let inner = ns.substring(with: NSRange(location: m.range.location + 1, length: m.range.length - 2))
                if inner.range(of: #"^\d{2}:\d{2}:\d{2}$"#, options: .regularExpression) != nil {
                    continue
                }
                for i in (m.range.location + 1)..<(m.range.location + m.range.length - 1) {
                    colors[i] = .purple
                }
            }
        }
        if let infoRegex = try? NSRegularExpression(pattern: #"\bINFO\b"#, options: [.caseInsensitive]) {
            paint(infoRegex, color: .green)
        }
        if let warnRegex = try? NSRegularExpression(pattern: #"\bWARN\b"#, options: [.caseInsensitive]) {
            paint(warnRegex, color: .yellow)
        }
        if let errorRegex = try? NSRegularExpression(pattern: #"\bERROR\b"#, options: [.caseInsensitive]) {
            paint(errorRegex, color: .red)
        }

        var result = AttributedString()
        if ns.length == 0 { return result }
        var start = 0
        var current = colors[0]
        for i in 1..<ns.length {
            if colors[i] != current {
                let part = ns.substring(with: NSRange(location: start, length: i - start))
                appendStyledSegment(part, color: current, isBold: false, to: &result)
                start = i
                current = colors[i]
            }
        }
        let tail = ns.substring(with: NSRange(location: start, length: ns.length - start))
        appendStyledSegment(tail, color: current, isBold: false, to: &result)
        return result
    }

    private func currentLocalLogSnapshot(serverName: String) -> String {
        let serverDir = AppPaths.serverDirectory(serverName: serverName)
        let candidates = [
            serverDir.appendingPathComponent("logs/latest.log"),
            serverDir.appendingPathComponent("latest.log"),
            serverDir.appendingPathComponent("scsl-server.log"),
            serverDir.appendingPathComponent("server.log"),
        ]
        for file in candidates where FileManager.default.fileExists(atPath: file.path) {
            if let text = try? String(contentsOf: file, encoding: .utf8), !text.isEmpty {
                return text.components(separatedBy: .newlines).suffix(300).joined(separator: "\n")
            }
        }
        return ""
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
                let current = text.components(separatedBy: .newlines).suffix(300).joined(separator: "\n")
                let delta = incrementalDelta(previous: lastLocalPolledText, current: current)
                if !delta.isEmpty {
                    if localLogText.isEmpty {
                        localLogText = delta
                    } else {
                        localLogText += "\n" + delta
                    }
                }
                lastLocalPolledText = current
                return
            }
        }
    }

    @MainActor
    private func loadRemoteLog(nodeId: String, serverName: String) async {
        guard let node = resolvedRemoteNode(nodeId: nodeId) else {
            let line = "[SCSL] \("server.console.remote_node_missing".localized())"
            if remoteLogText.isEmpty {
                remoteLogText = line
            } else if !remoteLogText.contains(line) {
                remoteLogText += "\n" + line
            }
            return
        }
        do {
            let text = try await SSHNodeService.fetchRemoteServerLog(node: node, serverName: serverName)
            let filtered = filterNoisyRconLifecycleLogs(text)
            let current = filtered.trimmingCharacters(in: .whitespacesAndNewlines)
            if !current.isEmpty {
                let delta = incrementalDelta(previous: lastRemotePolledText, current: current)
                if !delta.isEmpty {
                    if remoteLogText.isEmpty {
                        remoteLogText = delta
                    } else {
                        remoteLogText += "\n" + delta
                    }
                }
                lastRemotePolledText = current
            }
            lastRemoteLogError = ""
        } catch {
            let message = error.localizedDescription
            if message != lastRemoteLogError {
                let line = "[SCSL] \(message)"
                if remoteLogText.isEmpty {
                    remoteLogText = line
                } else {
                    remoteLogText += "\n" + line
                }
            }
            lastRemoteLogError = message
        }
    }

    private func incrementalDelta(previous: String, current: String) -> String {
        if previous.isEmpty { return current }
        if current == previous { return "" }
        if current.hasPrefix(previous) {
            return String(current.dropFirst(previous.count)).trimmingCharacters(in: .newlines)
        }

        let previousLines = previous.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        let currentLines = current.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        let maxOverlap = min(previousLines.count, currentLines.count)

        var overlap = 0
        if maxOverlap > 0 {
            for count in stride(from: maxOverlap, through: 1, by: -1)
                where Array(previousLines.suffix(count)) == Array(currentLines.prefix(count)) {
                overlap = count
                break
            }
        }

        let newLines = currentLines.dropFirst(overlap)
        return newLines.joined(separator: "\n").trimmingCharacters(in: .newlines)
    }

    private func sendRemoteDirectCommand(_ command: String) {
        guard let node = resolvedRemoteNode(nodeId: server.nodeId) else {
            GlobalErrorHandler.shared.handle(
                GlobalError.validation(
                    chineseMessage: "未找到远程节点，请重新选择节点后重试",
                    i18nKey: "server.console.remote_node_missing",
                    level: .notification
                )
            )
            return
        }
        Task {
            do {
                try await SSHNodeService.sendRemoteDirectCommand(node: node, serverName: server.name, command: command)
            } catch {
                GlobalErrorHandler.shared.handle(error)
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
        let normalized = raw
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        let lines = normalized.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)

        var kept: [String] = []
        kept.reserveCapacity(lines.count)

        for line in lines {
            let sanitized = line.unicodeScalars
                .filter { scalar in
                    scalar.value == 9 || scalar.value == 27 || scalar.value >= 32
                }
                .map(String.init)
                .joined()

            let trimmed = sanitized.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { continue }
            if trimmed == ">" { continue }
            if trimmed.allSatisfy({ $0 == ">" || $0 == " " }) { continue }
            if trimmed.range(of: #"^>+$"#, options: .regularExpression) != nil { continue }
            if sanitized.contains("RCON Client /127.0.0.1"),
               (sanitized.contains("started") || sanitized.contains("shutting down")) {
                continue
            }
            kept.append(sanitized)
        }

        return kept.joined(separator: "\n")
    }

    private func colorForLine(_ line: String) -> Color {
        let upper = line.uppercased()
        if upper.contains("ERROR") || line.contains("❌") || line.contains("Exception") {
            return .red
        }
        if upper.contains("WARN") || line.contains("⚠️") {
            return .yellow
        }
        if upper.contains("INFO") || line.contains("ℹ️") {
            return .green
        }
        if line.range(of: #"\b\d{2}:\d{2}:\d{2}\b"#, options: .regularExpression) != nil {
            return .blue
        }
        if line.contains("[") && line.contains("]") {
            return .primary
        }
        if upper.contains("PLUGIN")
            || upper.contains("PAPER")
            || upper.contains("FABRIC")
            || upper.contains("FORGE") {
            return .purple
        }
        if line.hasPrefix("[SCSL]") || line.hasPrefix("[RCON]") {
            return .cyan
        }
        return .primary
    }

    private func ansiStyledAttributedText(from text: String) -> AttributedString {
        let normalized = normalizeANSIText(text)
        var result = AttributedString()
        var currentColor: Color = .primary
        var isBold = false
        var buffer = ""
        let chars = Array(normalized)
        var index = 0

        while index < chars.count {
            if chars[index] == "\u{001B}", index + 1 < chars.count, chars[index + 1] == "[" {
                if !buffer.isEmpty {
                    appendStyledSegment(buffer, color: currentColor, isBold: isBold, to: &result)
                    buffer = ""
                }
                index += 2
                var codeBuffer = ""
                while index < chars.count, chars[index] != "m" {
                    codeBuffer.append(chars[index])
                    index += 1
                }
                if index < chars.count, chars[index] == "m" {
                    let codes = codeBuffer.split(separator: ";").compactMap { Int($0) }
                    let parsed = codes.isEmpty ? [0] : codes
                    var i = 0
                    while i < parsed.count {
                        let code = parsed[i]
                        switch code {
                        case 0:
                            currentColor = .primary
                            isBold = false
                        case 1:
                            isBold = true
                        case 22:
                            isBold = false
                        case 30...37, 90...97:
                            currentColor = ansiColor(code) ?? currentColor
                        case 39:
                            currentColor = .primary
                        case 38:
                            if i + 2 < parsed.count, parsed[i + 1] == 5 {
                                currentColor = ansi256Color(parsed[i + 2])
                                i += 2
                            } else if i + 4 < parsed.count, parsed[i + 1] == 2 {
                                let r = parsed[i + 2]
                                let g = parsed[i + 3]
                                let b = parsed[i + 4]
                                currentColor = Color(
                                    red: Double(max(0, min(255, r))) / 255.0,
                                    green: Double(max(0, min(255, g))) / 255.0,
                                    blue: Double(max(0, min(255, b))) / 255.0
                                )
                                i += 4
                            }
                        default:
                            break
                        }
                        i += 1
                    }
                }
            } else {
                buffer.append(chars[index])
            }
            index += 1
        }

        if !buffer.isEmpty {
            appendStyledSegment(buffer, color: currentColor, isBold: isBold, to: &result)
        }
        return result
    }

    private func normalizeANSIText(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\\u001B[", with: "\u{001B}[")
            .replacingOccurrences(of: "\\u001b[", with: "\u{001B}[")
            .replacingOccurrences(of: "\\u{001B}[", with: "\u{001B}[")
            .replacingOccurrences(of: "\\u{001b}[", with: "\u{001B}[")
            .replacingOccurrences(of: "\\x1b[", with: "\u{001B}[")
            .replacingOccurrences(of: "\\x1B[", with: "\u{001B}[")
            .replacingOccurrences(of: "\\033[", with: "\u{001B}[")
    }

    private func containsANSISequence(_ text: String) -> Bool {
        text.contains("\u{001B}[")
            || text.contains("\\u001B[")
            || text.contains("\\u001b[")
            || text.contains("\\u{001B}[")
            || text.contains("\\u{001b}[")
            || text.contains("\\x1b[")
            || text.contains("\\x1B[")
            || text.contains("\\033[")
    }

    private func appendStyledSegment(_ text: String, color: Color, isBold: Bool, to result: inout AttributedString) {
        guard !text.isEmpty else { return }
        var seg = AttributedString(text)
        var attrs = AttributeContainer()
        attrs.foregroundColor = color
        attrs.font = .system(.caption, design: .monospaced).weight(isBold ? .bold : .regular)
        seg.mergeAttributes(attrs)
        result.append(seg)
    }

    private func ansiColor(_ code: Int) -> Color? {
        switch code {
        case 30: return Color(nsColor: .black)
        case 31: return Color(nsColor: .systemRed)
        case 32: return Color(nsColor: .systemGreen)
        case 33: return Color(nsColor: .systemYellow)
        case 34: return Color(nsColor: .systemBlue)
        case 35: return Color(nsColor: .systemPink)
        case 36: return Color(nsColor: .systemTeal)
        case 37: return Color(nsColor: .white)
        case 90: return Color(nsColor: .systemGray)
        case 91: return Color(nsColor: .systemRed).opacity(0.95)
        case 92: return Color(nsColor: .systemGreen).opacity(0.95)
        case 93: return Color(nsColor: .systemYellow).opacity(0.95)
        case 94: return Color(nsColor: .systemBlue).opacity(0.95)
        case 95: return Color(nsColor: .systemPink).opacity(0.95)
        case 96: return Color(nsColor: .systemTeal).opacity(0.95)
        case 97: return Color(nsColor: .white).opacity(0.98)
        default: return nil
        }
    }

    private func ansi256Color(_ code: Int) -> Color {
        let clamped = max(0, min(255, code))
        if clamped < 16 {
            let base: [Color] = [
                .black, .red, .green, .yellow, .blue, .pink, .cyan, .white,
                .gray, .red, .green, .yellow, .blue, .pink, .cyan, .white,
            ]
            return base[clamped]
        }
        if clamped <= 231 {
            let n = clamped - 16
            let r = n / 36
            let g = (n % 36) / 6
            let b = n % 6
            let map = [0, 95, 135, 175, 215, 255]
            return Color(
                red: Double(map[r]) / 255.0,
                green: Double(map[g]) / 255.0,
                blue: Double(map[b]) / 255.0
            )
        }
        let gray = Double((clamped - 232) * 10 + 8) / 255.0
        return Color(red: gray, green: gray, blue: gray)
    }

    private func shouldRetryRcon(error: Error) -> Bool {
        let text = error.localizedDescription.lowercased()
        return text.contains("connection refused")
            || text.contains("timed out")
            || text.contains("eof")
            || text.contains("连接失败")
    }

    private func resolvedRemoteNode(nodeId: String) -> ServerNode? {
        if let node = serverNodeRepository.getNode(by: nodeId), !node.isLocal {
            return node
        }
        let remoteNodes = serverNodeRepository.nodes.filter { !$0.isLocal }
        if remoteNodes.count == 1 {
            return remoteNodes.first
        }
        return nil
    }

    private func historyFileURL() -> URL {
        let base: URL
        if server.nodeId == ServerNode.local.id {
            base = AppPaths.serverDirectory(serverName: server.name)
        } else {
            base = AppPaths.remoteNodeServersDirectory(nodeId: server.nodeId)
                .appendingPathComponent(server.name)
        }
        return base.appendingPathComponent(".console_history")
    }

    private func loadCommandHistory() {
        let url = historyFileURL()
        if let content = try? String(contentsOf: url, encoding: .utf8) {
            commandHistory = normalizeHistoryContent(content)
            saveCommandHistory()
        } else {
            commandHistory = []
        }
    }

    private func saveCommandHistory() {
        let url = historyFileURL()
        let dir = url.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let trimmed = Array(commandHistory.suffix(300))
        let data = trimmed.joined(separator: "\n") + (trimmed.isEmpty ? "" : "\n")
        try? data.write(to: url, atomically: true, encoding: .utf8)
    }

    private func appendHistory(_ command: String) {
        guard !command.isEmpty else { return }
        if commandHistory.last != command {
            commandHistory.append(command)
            saveCommandHistory()
        }
    }

    private func navigateHistoryUp() {
        guard !commandHistory.isEmpty else { return }
        if let index = historyIndex {
            historyIndex = max(0, index - 1)
        } else {
            historyIndex = commandHistory.count - 1
        }
        if let index = historyIndex {
            commandText = commandHistory[index]
        }
    }

    private func navigateHistoryDown() {
        guard !commandHistory.isEmpty else { return }
        guard let index = historyIndex else { return }
        let next = index + 1
        if next >= commandHistory.count {
            historyIndex = nil
            commandText = ""
        } else {
            historyIndex = next
            commandText = commandHistory[next]
        }
    }

    private func normalizeHistoryContent(_ content: String) -> [String] {
        let timestampPattern = #"(\\d{10,}:)"#
        let expanded = content.replacingOccurrences(
            of: timestampPattern,
            with: "\n$1",
            options: .regularExpression
        )
        let lines = expanded
            .split(whereSeparator: \.isNewline)
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }

        var normalized: [String] = []
        for line in lines {
            if line.isEmpty { continue }
            let command: String
            if let range = line.range(of: #"^\d{10,}:"#, options: .regularExpression) {
                command = String(line[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
            } else {
                command = line
            }
            if command.isEmpty { continue }
            if normalized.last != command {
                normalized.append(command)
            }
        }
        return normalized
    }

    private func installKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard commandFieldFocused else { return event }
            switch event.keyCode {
            case 126:
                navigateHistoryUp()
                return nil
            case 125:
                navigateHistoryDown()
                return nil
            default:
                return event
            }
        }
    }

    private func removeKeyMonitor() {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }
    }
}
