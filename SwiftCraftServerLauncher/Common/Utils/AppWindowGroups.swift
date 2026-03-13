//
//  AppWindowGroups.swift
//  SwiftCraftServerLauncher
//
//  Created by su on 2025/1/27.
//

import SwiftUI

/// 应用窗口组定义
extension SwiftCraftServerLauncherApp {
    /// 创建所有应用窗口组
    @SceneBuilder
    func appWindowGroups() -> some Scene {
        // 下载中心窗口
        Window("下载中心", id: WindowID.downloadCenter.rawValue) {
            DownloadCenterWindowView()
                .windowStyleConfig(for: .downloadCenter)
                .windowCleanup(for: .downloadCenter)
        }
        .defaultSize(width: 520, height: 420)
    }
}
