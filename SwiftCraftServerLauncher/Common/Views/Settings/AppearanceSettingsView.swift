import AppKit
import SwiftUI

public struct AppearanceSettingsView: View {
    @StateObject private var themeManager = ThemeManager.shared
    @StateObject private var generalSettings = GeneralSettingsManager.shared

    @State private var showingRestartAlert = false
    @State private var selectedLanguage = LanguageManager.shared.selectedLanguage
    @State private var error: GlobalError?

    public init() {}

    public var body: some View {
        Form {
            LabeledContent("settings.language.picker".localized()) {
                Picker("", selection: $selectedLanguage) {
                    ForEach(LanguageManager.shared.languages, id: \.1) { name, code in
                        Text(name).tag(code)
                    }
                }
                .labelsHidden()
                .fixedSize()
                .onChange(of: selectedLanguage) { _, newValue in
                    if newValue != LanguageManager.shared.selectedLanguage {
                        showingRestartAlert = true
                    }
                }
                .confirmationDialog(
                    "settings.language.restart.title".localized(),
                    isPresented: $showingRestartAlert,
                    titleVisibility: .visible
                ) {
                    Button("settings.language.restart.confirm".localized(), role: .destructive) {
                        UserDefaults.standard.set([selectedLanguage], forKey: "AppleLanguages")
                        LanguageManager.shared.selectedLanguage = selectedLanguage
                        restartAppSafely()
                    }
                    .keyboardShortcut(.defaultAction)

                    Button("common.cancel".localized(), role: .cancel) {
                        selectedLanguage = LanguageManager.shared.selectedLanguage
                    }
                } message: {
                    Text("settings.language.restart.message".localized())
                }
            }
            .labeledContentStyle(.custom)
            .padding(.bottom, 10)

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
        .globalErrorHandler()
        .alert(
            "error.notification.validation.title".localized(),
            isPresented: .constant(error != nil && error?.level == .popup)
        ) {
            Button("common.close".localized()) {
                error = nil
            }
        } message: {
            if let error = error {
                Text(error.localizedDescription)
            }
        }
    }

    private func restartAppSafely() {
        do {
            try restartApp()
        } catch {
            let globalError = GlobalError.from(error)
            GlobalErrorHandler.shared.handle(globalError)
            self.error = globalError
        }
    }
}

private func restartApp() throws {
    guard let appURL = Bundle.main.bundleURL as URL? else {
        throw GlobalError.configuration(
            chineseMessage: "无法获取应用路径",
            i18nKey: "error.configuration.app_path_not_found",
            level: .popup
        )
    }

    let task = Process()
    task.executableURL = URL(fileURLWithPath: "/usr/bin/open")
    task.arguments = [appURL.path]

    try task.run()

    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
        NSApplication.shared.terminate(nil)
    }
}
