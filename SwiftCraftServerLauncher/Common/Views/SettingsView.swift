import SwiftUI
import Foundation

/// 设置标签页枚举
enum SettingsTab: Int {
    case generalBasic = 0
    case generalUpdate = 1
    case generalSafety = 2
    case generalBackup = 3
    case appearance = 4
}

/// 通用设置视图
/// 应用设置
public struct SettingsView: View {
    @EnvironmentObject private var settingsNavigation: SettingsNavigationManager

    public init() {}

    public var body: some View {
        TabView(selection: $settingsNavigation.selectedTab) {
            GeneralSettingsView(sections: [.basic])
                .tabItem {
                    Label("settings.general.basic.tab".localized(), systemImage: "gearshape")
                }
                .tag(SettingsTab.generalBasic)

            GeneralSettingsView(sections: [.update])
                .tabItem {
                    Label("settings.general.update.tab".localized(), systemImage: "arrow.triangle.2.circlepath")
                }
                .tag(SettingsTab.generalUpdate)

            GeneralSettingsView(sections: [.safety])
                .tabItem {
                    Label("settings.general.confirmation.tab".localized(), systemImage: "checkmark.shield")
                }
                .tag(SettingsTab.generalSafety)

            GeneralSettingsView(sections: [.backup])
                .tabItem {
                    Label("settings.general.backup.tab".localized(), systemImage: "archivebox")
                }
                .tag(SettingsTab.generalBackup)

            AppearanceSettingsView()
                .tabItem {
                    Label("settings.appearance.tab".localized(), systemImage: "paintpalette")
                }
                .tag(SettingsTab.appearance)
        }
        .padding()
    }
}

struct CustomLabeledContentStyle: LabeledContentStyle {
    let alignment: VerticalAlignment

    init(alignment: VerticalAlignment = .center) {
        self.alignment = alignment
    }

    // 保留系统布局
    func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: alignment) {
            // 使用系统的标签布局
            HStack(spacing: 0) {
                configuration.label
                Text(":")
            }
            .layoutPriority(1)  // 保持标签优先级
            .multilineTextAlignment(.trailing)
            .frame(minWidth: 320, alignment: .trailing)  // 容器右对齐
            // 右侧内容
            configuration.content
                .foregroundColor(.secondary)
            .multilineTextAlignment(.leading)  // 文字左对齐
                .frame(maxWidth: .infinity, alignment: .leading)  // 容器左对齐
        }
        .padding(.vertical, 4)
    }
}

// 使用扩展避免破坏布局
extension LabeledContentStyle where Self == CustomLabeledContentStyle {
    static var custom: Self { .init() }

    static func custom(alignment: VerticalAlignment) -> Self {
        .init(alignment: alignment)
    }
}

#Preview {
    SettingsView()
}
