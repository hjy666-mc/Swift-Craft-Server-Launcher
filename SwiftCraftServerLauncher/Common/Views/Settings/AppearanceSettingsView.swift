import SwiftUI

public struct AppearanceSettingsView: View {
    @StateObject private var themeManager = ThemeManager.shared
    @StateObject private var generalSettings = GeneralSettingsManager.shared

    public init() {}

    public var body: some View {
        Form {
            LabeledContent("settings.appearance.theme".localized()) {
                ThemeSelectorView(selectedTheme: $themeManager.themeMode)
                    .fixedSize()
            }
            .labeledContentStyle(.custom)

            LabeledContent("settings.appearance.console_color_output".localized()) {
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
            }
            .labeledContentStyle(.custom(alignment: .firstTextBaseline))
            .padding(.top, 6)
        }
    }
}
