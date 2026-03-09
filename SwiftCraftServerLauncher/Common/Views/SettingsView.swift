import SwiftUI
import Foundation

/// 设置标签页枚举
enum SettingsTab: Int, CaseIterable {
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
                .frame(maxWidth: 300, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.primary.opacity(0.05))
                )

                Picker("", selection: $selectedTab) {
                    Text("settings.general.tab".localized()).tag(SettingsTab.general)
                    Text("settings.appearance.tab".localized()).tag(SettingsTab.appearance)
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 340)

                Spacer(minLength: 0)
            }

            if hasAnySearchResult {
                switch selectedTab {
                case .general:
                    GeneralSettingsView(searchText: searchText)
                case .appearance:
                    AppearanceSettingsView(searchText: searchText)
                }
            } else {
                ContentUnavailableView {
                    Label("result.empty".localized(), systemImage: "magnifyingglass")
                } description: {
                    Text(searchText)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }
        }
        .padding()
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

    private var hasAnySearchResult: Bool {
        let query = normalizedSearchText
        guard !query.isEmpty else { return true }
        return hasGeneralSearchResult || hasAppearanceSearchResult
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

private extension SettingsTab {
    var localizedTitle: String {
        switch self {
        case .general:
            return "settings.general.tab".localized()
        case .appearance:
            return "settings.appearance.tab".localized()
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
