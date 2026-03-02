# SwiftCraftServerLauncher

一个专注于 Minecraft Java 版服务器管理的 macOS 原生启动器（SwiftUI）。

## 项目说明

- 本项目为独立仓库版本，面向“开服管理”场景。
- 基于 [Swift-Craft-Launcher](https://github.com/suhang12332/Swift-Craft-Launcher) 进行二次开发。
- 本项目在开发过程中使用了 AI 辅助。

## 当前定位

- 仅保留服务器相关能力（本地服务器管理为主）。
- 资源安装来源当前仅支持 Modrinth。
- 重点支持服务器创建、启动/停止、日志控制台、配置编辑、世界/模组/插件管理。

## 技术栈

- Swift + SwiftUI
- SQLite（本地数据存储）
- macOS 14+

## 构建运行

> 注：本项目尚未有Release
在 Xcode 中打开 `SwiftCraftServerLauncher` 后运行。

## 开源协议与归因

本项目遵循 **GNU AGPL v3.0**，并包含附加归因条款。

- License: [LICENSE](LICENSE)
- Additional Terms: [doc/ADDITIONAL_TERMS.md](doc/ADDITIONAL_TERMS.md)

根据协议要求，保留上游来源与版权信息：
- Upstream: [Swift-Craft-Launcher](https://github.com/suhang12332/Swift-Craft-Launcher)
