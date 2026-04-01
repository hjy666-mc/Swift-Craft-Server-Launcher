import SwiftUI

/// 应用窗口组定义
extension SwiftCraftServerLauncherApp {
    /// 创建所有应用窗口组
    @SceneBuilder
    func appWindowGroups() -> some Scene {
        // 下载中心窗口
        Window("download.center".localized(), id: WindowID.downloadCenter.rawValue) {
            DownloadCenterWindowView()
                .windowStyleConfig(for: .downloadCenter)
                .windowCleanup(for: .downloadCenter)
        }
        .defaultSize(width: 520, height: 420)

        WindowGroup(id: WindowID.serverDetail.rawValue, for: String.self) { serverId in
            ServerDetailWindowView(serverId: serverId.wrappedValue)
                .environmentObject(serverRepository)
                .environmentObject(serverNodeRepository)
                .environmentObject(serverLaunchUseCase)
                .environmentObject(generalSettingsManager)
        } defaultValue: {
            ""
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified(showsTitle: false))
        .defaultSize(width: 1100, height: 720)
    }
}
