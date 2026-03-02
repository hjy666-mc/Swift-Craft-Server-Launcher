//
//  SwiftCraftServerLauncherApp.swift
//  SwiftCraftServerLauncher
//
//  Created by su on 2025/5/30.
//
//  SwiftCraftServerLauncher
//
//
//  This program is free software: you can redistribute it and/or modify
//  it under the terms of the GNU Affero General Public License as published by
//  the Free Software Foundation, either version 3 of the License, or
//  (at your option) any later version.
//
//  This program is distributed in the hope that it will be useful,
//  but WITHOUT ANY WARRANTY; without even the implied warranty of
//  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//  GNU Affero General Public License for more details.
//
//  You should have received a copy of the GNU Affero General Public License
//  along with this program.  If not, see <https://www.gnu.org/licenses/>.
//
//  ADDITIONAL TERMS:
//  This program includes additional terms for source attribution and name usage.
//  See doc/ADDITIONAL_TERMS.md in the project root for details.

import SwiftUI
import UserNotifications
import Combine

@main
struct SwiftCraftServerLauncherApp: App {
    @Environment(\.scenePhase)
    private var scenePhase

    // MARK: - StateObjects
    @StateObject var playerListViewModel = PlayerListViewModel()
    @StateObject var gameRepository = GameRepository()
    @StateObject var serverRepository = ServerRepository()
    @StateObject var serverNodeRepository = ServerNodeRepository()
    @StateObject var gameLaunchUseCase = GameLaunchUseCase()
    @StateObject var serverLaunchUseCase = ServerLaunchUseCase()
    @StateObject private var globalErrorHandler = GlobalErrorHandler.shared
    @StateObject private var appUpdateService = AppUpdateService.shared
    @StateObject var generalSettingsManager = GeneralSettingsManager.shared
    @StateObject var themeManager = ThemeManager.shared
    @StateObject private var skinSelectionStore = SkinSelectionStore()
    @StateObject private var appIdleManager = AppIdleManager.shared

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
                .environmentObject(playerListViewModel)
                .environmentObject(gameRepository)
                .environmentObject(serverRepository)
                .environmentObject(serverNodeRepository)
                .environmentObject(gameLaunchUseCase)
                .environmentObject(serverLaunchUseCase)
                .environmentObject(appUpdateService)
                .environmentObject(generalSettingsManager)
                .environmentObject(skinSelectionStore)
                .preferredColorScheme(themeManager.currentColorScheme)
                .errorAlert()
                .windowOpener()
                .onAppear {
                    appIdleManager.startMonitoring()
                }
                .onChange(of: scenePhase) { _, newPhase in
                    appIdleManager.handleScenePhase(newPhase)
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
                Button("menu.open.log".localized()) {
                    Logger.shared.openLogFile()
                }
                .keyboardShortcut("l", modifiers: [.command, .shift])
            }
            CommandGroup(replacing: .newItem) { }
            CommandGroup(replacing: .saveItem) { }
        }

        Settings {
            SettingsView()
                .environmentObject(gameRepository)
                .environmentObject(serverRepository)
                .environmentObject(serverNodeRepository)
                .environmentObject(appUpdateService)
                .environmentObject(generalSettingsManager)
                .preferredColorScheme(themeManager.currentColorScheme)
                .errorAlert()
        }

        appWindowGroups()
    }
}
