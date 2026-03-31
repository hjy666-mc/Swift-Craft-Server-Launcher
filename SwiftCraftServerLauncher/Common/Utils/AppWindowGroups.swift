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

        Window("server.window.title".localized(), id: WindowID.serverDetail.rawValue) {
            ServerDetailWindowView()
                .environmentObject(serverRepository)
                .environmentObject(serverNodeRepository)
                .environmentObject(serverLaunchUseCase)
                .environmentObject(generalSettingsManager)
        }
        .defaultSize(width: 1100, height: 720)
    }
}
