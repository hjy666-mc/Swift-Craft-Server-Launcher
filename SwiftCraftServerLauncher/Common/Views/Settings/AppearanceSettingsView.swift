import SwiftUI

public struct AppearanceSettingsView: View {
    @StateObject private var themeManager = ThemeManager.shared
    @StateObject private var generalSettings = GeneralSettingsManager.shared

    private let defaultThemeMode: ThemeMode = .system
    private let defaultEnableConsoleColoredOutput = true
    private let defaultServerFileManagerShowShortcuts = true

    public init() {}

    public var body: some View {
        Form {
            Section(
                header: Text("settings.appearance.section.theme.header".localized())
            ) {
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
            }

            Section(
                header: Text("settings.appearance.section.console.header".localized())
            ) {
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

            Section(
                header: Text("settings.appearance.section.server.header".localized())
            ) {
                LabeledContent("settings.appearance.server_tabs".localized()) {
                    Menu {
                        ForEach(tabOptions) { option in
                            Toggle(option.title, isOn: Binding(
                                get: { option.isOn() },
                                set: { option.set($0) }
                            ))
                        }
                    } label: {
                        Text("settings.appearance.server_tabs.select".localized())
                            .frame(minWidth: 140, alignment: .leading)
                    }
                    .menuStyle(.automatic)
                    .controlSize(.small)
                }
                .labeledContentStyle(.custom(alignment: .top))

                LabeledContent("settings.appearance.server_file_shortcuts".localized()) {
                    HStack(alignment: .top, spacing: 8) {
                        VStack(alignment: .leading, spacing: 4) {
                            Toggle(
                                "settings.appearance.server_file_shortcuts.enable".localized(),
                                isOn: $generalSettings.serverFileManagerShowShortcuts
                            )
                            .toggleStyle(.checkbox)

                            Text("settings.appearance.server_file_shortcuts.description".localized())
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        resetIconButton(disabled: generalSettings.serverFileManagerShowShortcuts == defaultServerFileManagerShowShortcuts) {
                            generalSettings.serverFileManagerShowShortcuts = defaultServerFileManagerShowShortcuts
                        }
                    }
                }
                .labeledContentStyle(.custom(alignment: .firstTextBaseline))
            }
        }
        .formStyle(.grouped)
    }

    private var tabOptions: [TabOption] {
        [
            TabOption(
                id: "console",
                title: "settings.appearance.server_tab.console".localized(),
                isOn: { generalSettings.serverTabConsoleEnabled },
                set: { generalSettings.serverTabConsoleEnabled = $0 }
            ),
            TabOption(
                id: "server_config",
                title: "settings.appearance.server_tab.server_config".localized(),
                isOn: { generalSettings.serverTabConfigEnabled },
                set: { generalSettings.serverTabConfigEnabled = $0 }
            ),
            TabOption(
                id: "players",
                title: "settings.appearance.server_tab.players".localized(),
                isOn: { generalSettings.serverTabPlayersEnabled },
                set: { generalSettings.serverTabPlayersEnabled = $0 }
            ),
            TabOption(
                id: "worlds",
                title: "settings.appearance.server_tab.worlds".localized(),
                isOn: { generalSettings.serverTabWorldsEnabled },
                set: { generalSettings.serverTabWorldsEnabled = $0 }
            ),
            TabOption(
                id: "mods",
                title: "settings.appearance.server_tab.mods".localized(),
                isOn: { generalSettings.serverTabModsEnabled },
                set: { generalSettings.serverTabModsEnabled = $0 }
            ),
            TabOption(
                id: "plugins",
                title: "settings.appearance.server_tab.plugins".localized(),
                isOn: { generalSettings.serverTabPluginsEnabled },
                set: { generalSettings.serverTabPluginsEnabled = $0 }
            ),
            TabOption(
                id: "schedules",
                title: "settings.appearance.server_tab.schedules".localized(),
                isOn: { generalSettings.serverTabSchedulesEnabled },
                set: { generalSettings.serverTabSchedulesEnabled = $0 }
            ),
            TabOption(
                id: "logs",
                title: "settings.appearance.server_tab.logs".localized(),
                isOn: { generalSettings.serverTabLogsEnabled },
                set: { generalSettings.serverTabLogsEnabled = $0 }
            ),
        ]
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

private struct TabOption: Identifiable {
    let id: String
    let title: String
    let isOn: () -> Bool
    let set: (Bool) -> Void
}
