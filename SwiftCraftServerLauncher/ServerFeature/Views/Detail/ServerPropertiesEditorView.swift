import SwiftUI
import AppKit

private struct ServerConfigFileItem: Identifiable, Hashable {
    let url: URL

    var id: String { url.path }
    var fileName: String { url.lastPathComponent }
    var relativePath: String { url.path }
}

struct ServerPropertiesEditorView: View {
    let server: ServerInstance
    @Environment(\.dismiss)
    private var dismiss
    @EnvironmentObject var serverNodeRepository: ServerNodeRepository
    @State private var properties: [String: String] = [:]
    @State private var isLoaded = false
    @State private var isDirty = false
    @State private var searchText: String = ""
    @State private var showOtherConfigs = false
    @State private var showRawPropertiesEditor = false

    var body: some View {
        CommonSheetView(
            header: {
                HStack {
                    Text("server.properties.title".localized())
                        .font(.headline)
                    Spacer()
                    Button("server.properties.edit_raw".localized()) { showRawPropertiesEditor = true }
                    Button("server.properties.other_configs".localized()) { showOtherConfigs = true }
                }
            },
            body: {
                VStack(alignment: .leading, spacing: 8) {
                    TextField("common.search".localized(), text: $searchText)
                        .textFieldStyle(.roundedBorder)

                    if properties.isEmpty && isLoaded {
                        Text("server.properties.no_properties".localized())
                            .foregroundColor(.secondary)
                    } else {
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 8) {
                                ForEach(filteredKeys, id: \.self) { key in
                                    propertyRow(key: key)
                                }
                            }
                            .padding(.vertical, 2)
                        }
                        .frame(minHeight: 220, maxHeight: 460)
                    }
                }
            },
            footer: {
                HStack {
                    Button("common.close".localized()) { dismiss() }
                    Spacer()
                    Button("common.reload".localized()) { load() }
                    Button("common.save".localized()) { save() }
                        .disabled(!isDirty)
                        .keyboardShortcut(.defaultAction)
                }
            }
        )
        .frame(minWidth: 860, minHeight: 560)
        .onAppear { load() }
        .sheet(isPresented: $showOtherConfigs) {
            ServerExtraConfigFilesView(server: server)
                .presentationDetents([.large])
        }
        .sheet(isPresented: $showRawPropertiesEditor) {
            ServerExtraConfigEditorView(
                fileURL: AppPaths.serverDirectory(serverName: server.name).appendingPathComponent("server.properties"),
                title: "server.properties.file_name".localized()
            )
            .presentationDetents([.fraction(0.95), .large])
        }
    }

    private func load() {
        if server.nodeId != ServerNode.local.id || server.javaPath == "java" {
            Task {
                guard let node = serverNodeRepository.getNode(by: server.nodeId) else { return }
                do {
                    let remoteProps = try await SSHNodeService.readRemoteServerProperties(node: node, serverName: server.name)
                    await MainActor.run {
                        properties = remoteProps
                        isLoaded = true
                        isDirty = false
                    }
                } catch {
                    await MainActor.run { GlobalErrorHandler.shared.handle(error) }
                }
            }
            return
        }
        let dir = AppPaths.serverDirectory(serverName: server.name)
        do {
            properties = try ServerPropertiesService.readProperties(serverDir: dir)
            isLoaded = true
            isDirty = false
        } catch {
            GlobalErrorHandler.shared.handle(error)
        }
    }

    private func save() {
        if server.nodeId != ServerNode.local.id || server.javaPath == "java" {
            Task {
                guard let node = serverNodeRepository.getNode(by: server.nodeId) else { return }
                do {
                    try await SSHNodeService.writeRemoteServerProperties(node: node, serverName: server.name, properties: properties)
                    await MainActor.run { isDirty = false }
                } catch {
                    await MainActor.run { GlobalErrorHandler.shared.handle(error) }
                }
            }
            return
        }
        let dir = AppPaths.serverDirectory(serverName: server.name)
        do {
            try ServerPropertiesService.writeProperties(serverDir: dir, properties: properties)
            isDirty = false
        } catch {
            GlobalErrorHandler.shared.handle(error)
        }
    }

    private var filteredKeys: [String] {
        let keys = properties.keys.sorted()
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return keys }
        return keys.filter { key in
            let value = properties[key]?.lowercased() ?? ""
            let localized = localizedName(for: key).lowercased()
            return key.lowercased().contains(query) || localized.contains(query) || value.contains(query)
        }
    }

    private func propertyRow(key: String) -> some View {
        let value = properties[key] ?? ""
        return HStack(spacing: 8) {
            Text(key)
                .frame(width: 160, alignment: .leading)
            Text(localizedName(for: key))
                .frame(width: 160, alignment: .leading)
                .foregroundColor(.secondary)
            valueEditor(for: key, value: value)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func valueEditor(for key: String, value: String) -> some View {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if normalized == "true" || normalized == "false" {
            return AnyView(
                Toggle("", isOn: Binding(
                    get: { normalized == "true" },
                    set: { newValue in
                        properties[key] = newValue ? "true" : "false"
                        isDirty = true
                    }
                ))
                .labelsHidden()
            )
        }
        return AnyView(
            TextField("", text: Binding(
                get: { properties[key] ?? "" },
                set: { newValue in
                    properties[key] = newValue
                    isDirty = true
                }
            ))
            .textFieldStyle(.roundedBorder)
        )
    }

    private func localizedName(for key: String) -> String {
        switch key {
        case "server-port": return "server.properties.name.server-port".localized()
        case "server-ip": return "server.properties.name.server-ip".localized()
        case "online-mode": return "server.properties.name.online-mode".localized()
        case "enable-command-block": return "server.properties.name.enable-command-block".localized()
        case "view-distance": return "server.properties.name.view-distance".localized()
        case "simulation-distance": return "server.properties.name.simulation-distance".localized()
        case "max-players": return "server.properties.name.max-players".localized()
        case "motd": return "server.properties.name.motd".localized()
        case "level-name": return "server.properties.name.level-name".localized()
        case "level-seed": return "server.properties.name.level-seed".localized()
        case "level-type": return "server.properties.name.level-type".localized()
        case "difficulty": return "server.properties.name.difficulty".localized()
        case "gamemode": return "server.properties.name.gamemode".localized()
        case "pvp": return "server.properties.name.pvp".localized()
        case "allow-flight": return "server.properties.name.allow-flight".localized()
        case "spawn-protection": return "server.properties.name.spawn-protection".localized()
        case "white-list": return "server.properties.name.white-list".localized()
        case "enforce-whitelist": return "server.properties.name.enforce-whitelist".localized()
        case "generate-structures": return "server.properties.name.generate-structures".localized()
        case "allow-nether": return "server.properties.name.allow-nether".localized()
        case "hardcore": return "server.properties.name.hardcore".localized()
        case "max-world-size": return "server.properties.name.max-world-size".localized()
        case "resource-pack": return "server.properties.name.resource-pack".localized()
        case "resource-pack-sha1": return "server.properties.name.resource-pack-sha1".localized()
        case "enable-status": return "server.properties.name.enable-status".localized()
        case "broadcast-rcon-to-ops": return "server.properties.name.broadcast-rcon-to-ops".localized()
        case "broadcast-console-to-ops": return "server.properties.name.broadcast-console-to-ops".localized()
        case "enable-rcon": return "server.properties.name.enable-rcon".localized()
        case "rcon.port": return "server.properties.name.rcon.port".localized()
        case "rcon.password": return "server.properties.name.rcon.password".localized()
        case "enable-query": return "server.properties.name.enable-query".localized()
        case "query.port": return "server.properties.name.query.port".localized()
        case "prevent-proxy-connections": return "server.properties.name.prevent-proxy-connections".localized()
        case "use-native-transport": return "server.properties.name.use-native-transport".localized()
        case "hide-online-players": return "server.properties.name.hide-online-players".localized()
        case "spawn-monsters": return "server.properties.name.spawn-monsters".localized()
        case "spawn-animals": return "server.properties.name.spawn-animals".localized()
        case "spawn-npcs": return "server.properties.name.spawn-npcs".localized()
        case "spawn-protection-radius": return "server.properties.name.spawn-protection-radius".localized()
        default: return key
        }
    }
}

private struct ServerExtraConfigFilesView: View {
    let server: ServerInstance
    @Environment(\.dismiss)
    private var dismiss
    @State private var files: [ServerConfigFileItem] = []
    @State private var searchText = ""
    @State private var selectedFile: ServerConfigFileItem?

    private let allowedExtensions = Set(["yml", "yaml", "toml", "json", "conf", "cfg", "ini"])

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("server.extra_configs.title".localized())
                    .font(.headline)
                Spacer()
                Button("common.reload".localized()) { loadFiles() }
                Button("common.close".localized()) { dismiss() }
            }

            TextField("server.extra_configs.search_file".localized(), text: $searchText)
                .textFieldStyle(.roundedBorder)

            if filteredFiles.isEmpty {
                Text("server.extra_configs.empty".localized())
                    .foregroundColor(.secondary)
            } else {
                List(filteredFiles) { item in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.fileName)
                            Text(relativePath(for: item.url))
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        Button("common.edit".localized()) {
                            selectedFile = item
                        }
                    }
                }
                .frame(minHeight: 420)
            }
        }
        .padding()
        .onAppear { loadFiles() }
        .sheet(item: $selectedFile) { item in
            ServerExtraConfigEditorView(fileURL: item.url, title: item.fileName)
                .presentationDetents([.fraction(0.95), .large])
        }
    }

    private var filteredFiles: [ServerConfigFileItem] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return files }
        return files.filter {
            $0.fileName.lowercased().contains(query) ||
            relativePath(for: $0.url).lowercased().contains(query)
        }
    }

    private func loadFiles() {
        let root = AppPaths.serverDirectory(serverName: server.name)
        var result: [ServerConfigFileItem] = []
        let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        )
        while let url = enumerator?.nextObject() as? URL {
            let resourceValues = try? url.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey])
            if resourceValues?.isDirectory == true {
                continue
            }
            let ext = url.pathExtension.lowercased()
            if !allowedExtensions.contains(ext) {
                continue
            }
            let fileSize = resourceValues?.fileSize ?? 0
            if fileSize > 1_000_000 {
                continue
            }
            if url.lastPathComponent.lowercased() == "eula.txt" {
                continue
            }
            result.append(ServerConfigFileItem(url: url))
        }
        files = result.sorted { $0.url.path < $1.url.path }
    }

    private func relativePath(for url: URL) -> String {
        let root = AppPaths.serverDirectory(serverName: server.name).path
        if url.path.hasPrefix(root) {
            return String(url.path.dropFirst(root.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        }
        return url.path
    }
}

private struct ServerExtraConfigEditorView: View {
    let fileURL: URL
    let title: String
    @Environment(\.dismiss)
    private var dismiss
    @State private var content = ""
    @State private var isLoaded = false
    @State private var isDirty = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(title)
                    .font(.headline)
                Spacer()
                Button("common.reload".localized()) { load() }
                Button("common.save".localized()) { save() }
                    .disabled(!isDirty)
                Button("common.close".localized()) { dismiss() }
            }

            if !isLoaded {
                ProgressView()
            } else {
                LineNumberedTextEditor(text: Binding(
                    get: { content },
                    set: { newValue in
                        content = newValue
                        isDirty = true
                    }
                ))
                .frame(minWidth: 980, minHeight: 680)
            }
        }
        .padding()
        .frame(minWidth: 1080, minHeight: 760)
        .onAppear { load() }
    }

    private func load() {
        do {
            content = try String(contentsOf: fileURL, encoding: .utf8)
            isLoaded = true
            isDirty = false
        } catch {
            let fallbackContent = try? String(contentsOf: fileURL)
            content = fallbackContent ?? ""
            isLoaded = true
            isDirty = false
        }
    }

    private func save() {
        do {
            try content.write(to: fileURL, atomically: true, encoding: .utf8)
            isDirty = false
        } catch {
            GlobalErrorHandler.shared.handle(error)
        }
    }
}

private struct LineNumberedTextEditor: View {
    @Binding var text: String

    var body: some View {
        LineNumberedTextEditorRepresentable(text: $text)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.gray.opacity(0.25), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

private struct LineNumberedTextEditorRepresentable: NSViewRepresentable {
    @Binding var text: String

    func makeNSView(context: Context) -> LineNumberEditorContainer {
        let view = LineNumberEditorContainer()
        view.onTextChange = { newValue in
            if context.coordinator.isUpdatingFromSwiftUI {
                return
            }
            text = newValue
        }
        view.setText(text)
        return view
    }

    func updateNSView(_ nsView: LineNumberEditorContainer, context: Context) {
        if nsView.text != text {
            context.coordinator.isUpdatingFromSwiftUI = true
            nsView.setText(text)
            context.coordinator.isUpdatingFromSwiftUI = false
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator {
        var isUpdatingFromSwiftUI = false
    }
}

private final class LineNumberEditorContainer: NSView, NSTextViewDelegate {
    private let numberView = LineNumberGutterView()
    private let textScrollView = NSScrollView()
    private let textView = NSTextView()
    private var boundsObserver: NSObjectProtocol?
    var onTextChange: ((String) -> Void)?

    var text: String { textView.string }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupViews()
        setupObservers()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupViews()
        setupObservers()
    }

    deinit {
        if let boundsObserver {
            NotificationCenter.default.removeObserver(boundsObserver)
        }
    }

    func setText(_ value: String) {
        textView.string = value
        syncLineNumbers()
    }

    private func setupViews() {
        wantsLayer = true
        numberView.translatesAutoresizingMaskIntoConstraints = false
        numberView.wantsLayer = true
        numberView.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor

        textView.frame = NSRect(x: 0, y: 0, width: 1000, height: 800)
        textView.isRichText = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDataDetectionEnabled = false
        textView.isAutomaticLinkDetectionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        textView.textColor = NSColor.labelColor
        textView.textContainerInset = NSSize(width: 6, height: 6)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = true
        textView.autoresizingMask = [.width]
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = false
        textView.textContainer?.containerSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.delegate = self

        textScrollView.documentView = textView
        textScrollView.hasVerticalScroller = true
        textScrollView.hasHorizontalScroller = true
        textScrollView.autohidesScrollers = true
        textScrollView.borderType = .noBorder
        textScrollView.translatesAutoresizingMaskIntoConstraints = false
        textScrollView.contentView.postsBoundsChangedNotifications = true

        addSubview(numberView)
        addSubview(textScrollView)

        NSLayoutConstraint.activate([
            numberView.leadingAnchor.constraint(equalTo: leadingAnchor),
            numberView.topAnchor.constraint(equalTo: topAnchor),
            numberView.bottomAnchor.constraint(equalTo: bottomAnchor),
            numberView.widthAnchor.constraint(equalToConstant: 72),

            textScrollView.leadingAnchor.constraint(equalTo: numberView.trailingAnchor),
            textScrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            textScrollView.topAnchor.constraint(equalTo: topAnchor),
            textScrollView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    private func setupObservers() {
        boundsObserver = NotificationCenter.default.addObserver(
            forName: NSView.boundsDidChangeNotification,
            object: textScrollView.contentView,
            queue: .main
        ) { [weak self] _ in
            self?.syncNumberScrollOffset()
        }
    }

    private func syncNumberScrollOffset() {
        let sourceBounds = textScrollView.contentView.bounds
        numberView.contentOffsetY = sourceBounds.origin.y
        numberView.needsDisplay = true
    }

    private func syncLineNumbers() {
        let count = max(textView.string.components(separatedBy: "\n").count, 1)
        numberView.totalLines = count
        if let font = textView.font {
            numberView.lineHeight = font.ascender - font.descender + font.leading
        }
        numberView.topInset = textView.textContainerInset.height
        numberView.needsDisplay = true
        syncNumberScrollOffset()
    }

    func textDidChange(_ notification: Notification) {
        syncLineNumbers()
        onTextChange?(textView.string)
    }
}

private final class LineNumberGutterView: NSView {
    var totalLines: Int = 1
    var contentOffsetY: CGFloat = 0
    var lineHeight: CGFloat = 16
    var topInset: CGFloat = 0

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.windowBackgroundColor.setFill()
        dirtyRect.fill()

        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .regular),
            .foregroundColor: NSColor.labelColor.withAlphaComponent(0.8),
        ]

        let visibleTop = contentOffsetY - topInset
        let firstLine = max(Int(floor(visibleTop / max(lineHeight, 1))) + 1, 1)
        let visibleBottom = contentOffsetY + bounds.height
        let lastLine = min(Int(ceil((visibleBottom - topInset) / max(lineHeight, 1))) + 1, totalLines)

        if firstLine <= lastLine {
            for line in firstLine...lastLine {
                let y = topInset + CGFloat(line - 1) * lineHeight - contentOffsetY
                let text = "\(line)" as NSString
                let size = text.size(withAttributes: attrs)
                let x = bounds.width - size.width - 8
                text.draw(at: NSPoint(x: x, y: y), withAttributes: attrs)
            }
        }

        NSColor.separatorColor.setStroke()
        let path = NSBezierPath()
        path.move(to: NSPoint(x: bounds.width - 0.5, y: 0))
        path.line(to: NSPoint(x: bounds.width - 0.5, y: bounds.height))
        path.lineWidth = 1
        path.stroke()
    }
}
