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
        .padding()
        .searchable(
            text: $searchText,
            placement: .toolbar,
            prompt: Text("common.search".localized())
        )
        .onChange(of: searchText) { _, _ in
            syncSelectedTabForSearch()
        }
        .onChange(of: selectedTab) { _, _ in
            syncSelectedTabForSearch()
        }
    }

    private var hasGeneralSearchResult: Bool {
        GeneralSettingsView.containsMatch(for: searchText)
    }

    private var hasAppearanceSearchResult: Bool {
        AppearanceSettingsView.containsMatch(for: searchText)
    }

    private var normalizedSearchText: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private func syncSelectedTabForSearch() {
        guard !normalizedSearchText.isEmpty else { return }

        switch selectedTab {
        case .general where !hasGeneralSearchResult && hasAppearanceSearchResult:
            selectedTab = .appearance
        case .appearance where !hasAppearanceSearchResult && hasGeneralSearchResult:
            selectedTab = .general
        default:
            break
        }
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
