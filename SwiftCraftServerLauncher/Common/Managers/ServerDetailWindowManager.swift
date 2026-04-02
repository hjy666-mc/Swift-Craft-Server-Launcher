import AppKit
import SwiftUI

@MainActor
final class ServerDetailWindowManager: NSObject {
    static let shared = ServerDetailWindowManager()

    private weak var serverRepository: ServerRepository?
    private weak var serverNodeRepository: ServerNodeRepository?
    private weak var serverLaunchUseCase: ServerLaunchUseCase?
    private weak var generalSettingsManager: GeneralSettingsManager?

    private var windowControllers: [UUID: NSWindowController] = [:]

    override private init() {
        super.init()
    }

    func configure(
        serverRepository: ServerRepository,
        serverNodeRepository: ServerNodeRepository,
        serverLaunchUseCase: ServerLaunchUseCase,
        generalSettingsManager: GeneralSettingsManager
    ) {
        self.serverRepository = serverRepository
        self.serverNodeRepository = serverNodeRepository
        self.serverLaunchUseCase = serverLaunchUseCase
        self.generalSettingsManager = generalSettingsManager
    }

    func open(serverId: String) {
        guard let serverRepository,
              let serverNodeRepository,
              let serverLaunchUseCase,
              let generalSettingsManager else {
            return
        }

        let windowKey = UUID()
        let contentView = ServerDetailWindowView(serverId: serverId)
            .environmentObject(serverRepository)
            .environmentObject(serverNodeRepository)
            .environmentObject(serverLaunchUseCase)
            .environmentObject(generalSettingsManager)

        let hostingController = NSHostingController(rootView: contentView)
        let window = NSWindow(contentViewController: hostingController)
        window.identifier = NSUserInterfaceItemIdentifier("\(WindowID.serverDetail.rawValue)-\(windowKey.uuidString)")
        window.setContentSize(NSSize(width: 1100, height: 720))
        window.styleMask.insert([.titled, .closable, .miniaturizable, .resizable])
        window.tabbingMode = .disallowed
        window.toolbarStyle = .unified
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = false
        window.isReleasedWhenClosed = false

        let controller = ServerDetailNSWindowController(window: window) { [weak self] in
            self?.windowControllers.removeValue(forKey: windowKey)
        }
        windowControllers[windowKey] = controller
        controller.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

@MainActor
private final class ServerDetailNSWindowController: NSWindowController, NSWindowDelegate {
    private let onClose: () -> Void

    init(window: NSWindow, onClose: @escaping () -> Void) {
        self.onClose = onClose
        super.init(window: window)
        window.delegate = self
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    func windowWillClose(_ notification: Notification) {
        _ = notification
        onClose()
    }
}
