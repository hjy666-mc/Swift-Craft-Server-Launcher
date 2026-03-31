import SwiftUI

/// 窗口标识符枚举
enum WindowID: String {
    case downloadCenter = "downloadCenter"
    case serverDetail = "serverDetail"
}

extension WindowID: CaseIterable {}
