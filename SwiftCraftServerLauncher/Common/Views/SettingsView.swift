import SwiftUI
import Foundation

/// 设置标签页枚举
enum SettingsTab: Int {
    case general = 0
    case appearance = 1
}

/// 通用设置视图
/// 应用设置
public struct SettingsView: View {
    @State private var selectedTab: SettingsTab = .general
    @State private var searchText = ""

    public init() {}

    public var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)

                TextField("common.search".localized(), text: $searchText)
                    .textFieldStyle(.plain)

                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.primary.opacity(0.05))
            )

            TabView(selection: $selectedTab) {
                GeneralSettingsView(searchText: searchText)
                    .tabItem {
                        Label("settings.general.tab".localized(), systemImage: "gearshape")
                    }
                    .tag(SettingsTab.general)

                AppearanceSettingsView(searchText: searchText)
                    .tabItem {
                        Label("settings.appearance.tab".localized(), systemImage: "paintpalette")
                    }
                    .tag(SettingsTab.appearance)
            }
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
