import SwiftUI

public struct AppearanceSettingsView: View {
    @StateObject private var themeManager = ThemeManager.shared
    @StateObject private var generalSettings = GeneralSettingsManager.shared

    private let defaultThemeMode: ThemeMode = .system
    private let defaultEnableConsoleColoredOutput = true

    public init() {}

    public var body: some View {
        Form {
            LabeledContent("settings.appearance.theme".localized()) {
                HStack(alignment: .top, spacing: 8) {
                    ThemeSelectorView(selectedTheme: $themeManager.themeMode)
                        .fixedSize()

                    resetIconButton(disabled: themeManager.themeMode == defaultThemeMode) {
                        themeManager.themeMode = defaultThemeMode
                    }
                }
            }
            .labeledContentStyle(.custom)

            LabeledContent("settings.appearance.console_color_output".localized()) {
                HStack(alignment: .top, spacing: 8) {
                    VStack(alignment: .leading, spacing: 4) {
                        Toggle(
                            "settings.appearance.console_color_output.enable".localized(),
                            isOn: $generalSettings.enableConsoleColoredOutput
                        )
                        .toggleStyle(.checkbox)

                        Text("settings.appearance.console_color_output.description".localized())
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    resetIconButton(disabled: generalSettings.enableConsoleColoredOutput == defaultEnableConsoleColoredOutput) {
                        generalSettings.enableConsoleColoredOutput = defaultEnableConsoleColoredOutput
                    }
                }
            }
            .labeledContentStyle(.custom(alignment: .firstTextBaseline))
            .padding(.top, 6)
        }
    }

    @ViewBuilder
    private func resetIconButton(disabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: "arrow.counterclockwise.circle")
                .font(.title3)
        }
        .buttonStyle(.plain)
        .foregroundStyle(disabled ? .tertiary : .secondary)
        .help("common.reset".localized())
        .disabled(disabled)
    }
}
