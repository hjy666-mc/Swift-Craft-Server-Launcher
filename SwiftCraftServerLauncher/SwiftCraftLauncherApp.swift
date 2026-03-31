import Combine
import CoreSpotlight
import SwiftUI
import UserNotifications

@main
struct SwiftCraftServerLauncherApp: App {
    @NSApplicationDelegateAdaptor(AppTerminationDelegate.self)
    private var appTerminationDelegate

    @Environment(\.scenePhase)
    private var scenePhase

    // MARK: - StateObjects
    @StateObject var gameRepository = GameRepository()
    @StateObject var serverRepository = ServerRepository()
    @StateObject var serverNodeRepository = ServerNodeRepository()
    @StateObject var gameLaunchUseCase = GameLaunchUseCase()
    @StateObject var serverLaunchUseCase = ServerLaunchUseCase()
    @StateObject private var globalErrorHandler = GlobalErrorHandler.shared
    @StateObject private var appUpdateService = AppUpdateService()
    @StateObject var generalSettingsManager = GeneralSettingsManager.shared
    @StateObject var themeManager = ThemeManager.shared
    @StateObject private var appIdleManager = AppIdleManager.shared
    @StateObject private var commandPalette = CommandPaletteController()
    @StateObject private var settingsNavigationManager = SettingsNavigationManager.shared

    // MARK: - Notification Delegate
    private let notificationCenterDelegate = NotificationCenterDelegate()

    init() {
        // 设置通知中心代理，确保前台时也能展示 Banner
        UNUserNotificationCenter.current().delegate = notificationCenterDelegate

        Task {
            await NotificationManager.requestAuthorizationIfNeeded()
        }
    }

    // MARK: - Body
    var body: some Scene {
        WindowGroup {
            MainView()
                .environment(\.appLogger, Logger.shared)
                .environmentObject(gameRepository)
                .environmentObject(serverRepository)
                .environmentObject(serverNodeRepository)
                .environmentObject(gameLaunchUseCase)
                .environmentObject(serverLaunchUseCase)
                .environmentObject(appUpdateService)
                .environmentObject(generalSettingsManager)
                .environmentObject(commandPalette)
                .environmentObject(settingsNavigationManager)
                .preferredColorScheme(themeManager.currentColorScheme)
                .errorAlert()
                .windowOpener()
                .titlebarSeparatorOnHover()
                .onAppear {
                    appIdleManager.startMonitoring()
                    BackupService.shared.startAutoBackupScheduler()
                }
                .onChange(of: scenePhase) { _, newPhase in
                    appIdleManager.handleScenePhase(newPhase)
                }
                .onContinueUserActivity(CSSearchableItemActionType) { activity in
                    if let identifier = activity.userInfo?[CSSearchableItemActivityIdentifier] as? String {
                        SpotlightActionCenter.shared.send(identifier: identifier)
                    }
                }
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified(showsTitle: false))
        .defaultSize(width: 1200, height: 800)
        .windowResizability(.contentMinSize)
        .conditionalRestorationBehavior()
        .commands {
            CommandGroup(after: .appInfo) {
                Button("menu.check.updates".localized()) {
                    appUpdateService.installLatestRelease()
                }
                .disabled(appUpdateService.isUpdating)
                .keyboardShortcut("u", modifiers: [.command, .shift])
            }
            CommandGroup(after: .help) {
                Button("menu.command.palette".localized()) {
                    commandPalette.present()
                }
                .keyboardShortcut("k", modifiers: [.command])

                Button("menu.visit.website".localized()) {
                    if let url = URL(string: "https://github.com/hjy666-mc/Swift-Craft-Server-Launcher") {
                        NSWorkspace.shared.open(url)
                    }
                }
            }
            CommandGroup(replacing: .newItem) {}
            CommandGroup(replacing: .saveItem) {}
        }

        Settings {
            SettingsView()
                .environmentObject(gameRepository)
                .environmentObject(serverRepository)
                .environmentObject(serverNodeRepository)
                .environmentObject(appUpdateService)
                .environmentObject(generalSettingsManager)
                .environmentObject(settingsNavigationManager)
                .preferredColorScheme(themeManager.currentColorScheme)
                .errorAlert()
        }

        appWindowGroups()
    }
}
