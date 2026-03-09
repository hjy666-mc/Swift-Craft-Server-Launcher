import AppKit
import SwiftUI

public enum GeneralSettingsSection: Hashable {
  case basic
  case update
  case safety
  case backup
}

public struct GeneralSettingsView: View {
  @StateObject private var generalSettings = GeneralSettingsManager.shared
  @EnvironmentObject private var gameRepository: GameRepository
  @EnvironmentObject private var appUpdateService: AppUpdateService
  @State private var showDirectoryPicker = false
  @State private var showBackupDirectoryPicker = false
  @State private var showingRestartAlert = false
  @State private var selectedLanguage = LanguageManager.shared.selectedLanguage
  @State private var error: GlobalError?
  @State private var backupAlertMessage = ""
  @State private var showBackupAlert = false
  @State private var isRunningManualBackup = false
  /// 数据库中所有工作路径及对应游戏数量（用于快速切换）
  @State private var workingPathOptions: [(path: String, count: Int)] = []

  private let defaultLanguage = LanguageManager.getDefaultLanguage()
  private let defaultWorkingDirectory = AppPaths.launcherSupportDirectory.path
  private let defaultConcurrentDownloads = 64
  private let defaultEnableGitHubProxy = true
  private let defaultGitHubProxyURL = "https://gh-proxy.com"
  private let defaultEnableResourcePageCache = true
  private let defaultLaunchAtLoginEnabled = false
  private let defaultUpdateAutoCheckEnabled = true
  private let defaultUpdateAutoDownloadEnabled = false
  private let defaultConfirmDeleteServer = true
  private let defaultConfirmDeleteWorld = true
  private let defaultConfirmUninstallPluginMod = true
  private let defaultConfirmExitWhileRunning = true
  private let defaultBackupAutoEnabled = false
  private let defaultBackupIntervalMinutes = 60
  private let defaultBackupKeepCount = 10
  private let defaultBackupBeforeUpdate = true
  private let defaultBackupDirectory = AppPaths.launcherSupportDirectory
    .appendingPathComponent("backups", isDirectory: true).path
  private let sections: Set<GeneralSettingsSection>

  public init(sections: Set<GeneralSettingsSection> = [.basic, .update, .safety, .backup]) {
    self.sections = sections
  }

  public var body: some View {
    Form {
      if sections.contains(.basic) {
        LabeledContent("settings.language.picker".localized()) {
          HStack(alignment: .top, spacing: 8) {
            Picker("", selection: $selectedLanguage) {
              ForEach(LanguageManager.shared.languages, id: \.1) { name, code in
                Text(name).tag(code)
              }
            }
            .labelsHidden()
            .fixedSize()

            resetIconButton(
              disabled: selectedLanguage == defaultLanguage
            ) {
              selectedLanguage = defaultLanguage
            }
          }
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

        LabeledContent("settings.launcher_working_directory".localized()) {
          HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 8) {
              if !workingPathOptions.isEmpty {
                Picker(
                  "",
                  selection: Binding(
                    get: {
                      generalSettings.launcherWorkingDirectory.isEmpty
                        ? defaultWorkingDirectory
                        : generalSettings.launcherWorkingDirectory
                    },
                    set: { generalSettings.launcherWorkingDirectory = $0 }
                  )
                ) {
                  ForEach(workingPathOptions, id: \.path) { item in
                    Text(workingPathDisplayString(for: item))
                      .lineLimit(1)
                      .truncationMode(.middle)
                      .tag(item.path)
                      .help(item.path)
                  }
                }
                .labelsHidden()
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 320)
              }
              DirectorySettingRow(
                title: "settings.launcher_working_directory".localized(),
                path: generalSettings.launcherWorkingDirectory.isEmpty
                  ? defaultWorkingDirectory
                  : generalSettings.launcherWorkingDirectory,
                description: "settings.working_directory.description".localized(),
                onChoose: { showDirectoryPicker = true },
                onReset: { resetWorkingDirectorySafely() },
                showsResetButton: false
              )
              .fixedSize()
              .fileImporter(
                isPresented: $showDirectoryPicker,
                allowedContentTypes: [.folder],
                allowsMultipleSelection: false
              ) { result in
                handleDirectoryImport(result)
              }
            }

            resetIconButton(
              disabled: generalSettings.launcherWorkingDirectory == defaultWorkingDirectory
            ) {
              resetWorkingDirectorySafely()
            }
          }
        }
        .labeledContentStyle(.custom(alignment: .firstTextBaseline))
        .task {
          workingPathOptions = await gameRepository.fetchAllWorkingPathsWithCounts()
        }
        .onChange(of: generalSettings.launcherWorkingDirectory) { _, _ in
          Task {
            workingPathOptions = await gameRepository.fetchAllWorkingPathsWithCounts()
          }
        }

        LabeledContent("settings.concurrent_downloads.label".localized()) {
          HStack(alignment: .top, spacing: 8) {
            HStack {
              Slider(
                value: Binding(
                  get: {
                    Double(generalSettings.concurrentDownloads)
                  },
                  set: {
                    generalSettings.concurrentDownloads = Int(
                      $0
                    )
                  }
                ),
                in: 1...64
              )
              .controlSize(.mini)
              .animation(.easeOut(duration: 0.5), value: generalSettings.concurrentDownloads)
              Text("\(generalSettings.concurrentDownloads)")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .fixedSize()
            }
            .frame(width: 200)
            .gridColumnAlignment(.leading)
            .labelsHidden()

            resetIconButton(
              disabled: generalSettings.concurrentDownloads == defaultConcurrentDownloads
            ) {
              generalSettings.concurrentDownloads = defaultConcurrentDownloads
            }
          }
        }
        .labeledContentStyle(.custom)

        LabeledContent("settings.github_proxy.label".localized()) {
          HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading) {
              HStack {
                Toggle(
                  "",
                  isOn: $generalSettings.enableGitHubProxy
                )
                .labelsHidden()
                Text("settings.github_proxy.enable".localized())
                  .font(.callout)
                  .foregroundColor(.primary)
              }
              HStack(spacing: 8) {
                TextField(
                  "",
                  text: $generalSettings.gitProxyURL
                )
                .labelsHidden()
                .textFieldStyle(.roundedBorder)
                .frame(width: 200)
                .focusable(false)
                .disabled(!generalSettings.enableGitHubProxy)
                InfoIconWithPopover(text: "settings.github_proxy.description".localized())
              }
            }

            resetIconButton(
              disabled: generalSettings.enableGitHubProxy == defaultEnableGitHubProxy
                && generalSettings.gitProxyURL == defaultGitHubProxyURL
            ) {
              generalSettings.enableGitHubProxy = defaultEnableGitHubProxy
              generalSettings.gitProxyURL = defaultGitHubProxyURL
            }
          }
        }
        .labeledContentStyle(.custom(alignment: .firstTextBaseline))
        .padding(.top, 10)

        LabeledContent("settings.resource_cache.label".localized()) {
          HStack(alignment: .top, spacing: 8) {
            Toggle(
              "settings.resource_cache.enable".localized(),
              isOn: $generalSettings.enableResourcePageCache
            )
            .toggleStyle(.checkbox)

            resetIconButton(
              disabled: generalSettings.enableResourcePageCache == defaultEnableResourcePageCache
            ) {
              generalSettings.enableResourcePageCache = defaultEnableResourcePageCache
            }
          }
        }
        .labeledContentStyle(.custom)
        .padding(.top, 6)
      }

      if sections.contains(.update) {
        LabeledContent("settings.general.launch_at_login".localized()) {
          HStack(alignment: .top, spacing: 8) {
            Toggle("", isOn: $generalSettings.launchAtLoginEnabled)
              .labelsHidden()
            Text(
              generalSettings.launchAtLoginEnabled
                ? "settings.state.enabled".localized()
                : "settings.state.disabled".localized()
            )
            .foregroundStyle(.secondary)

            resetIconButton(
              disabled: generalSettings.launchAtLoginEnabled == defaultLaunchAtLoginEnabled
            ) {
              generalSettings.launchAtLoginEnabled = defaultLaunchAtLoginEnabled
            }
          }
        }
        .labeledContentStyle(.custom)

        LabeledContent("settings.general.update.auto_check".localized()) {
          HStack(alignment: .top, spacing: 8) {
            Toggle("", isOn: $generalSettings.updateAutoCheckEnabled)
              .labelsHidden()
            Text(
              generalSettings.updateAutoCheckEnabled
                ? "settings.state.enabled".localized()
                : "settings.state.disabled".localized()
            )
            .foregroundStyle(.secondary)

            resetIconButton(
              disabled: generalSettings.updateAutoCheckEnabled == defaultUpdateAutoCheckEnabled
            ) {
              generalSettings.updateAutoCheckEnabled = defaultUpdateAutoCheckEnabled
            }
          }
        }
        .labeledContentStyle(.custom)

        LabeledContent("settings.general.update.auto_download".localized()) {
          HStack(alignment: .top, spacing: 8) {
            Toggle("", isOn: $generalSettings.updateAutoDownloadEnabled)
              .labelsHidden()
            Text(
              generalSettings.updateAutoDownloadEnabled
                ? "settings.state.enabled".localized()
                : "settings.state.disabled".localized()
            )
            .foregroundStyle(.secondary)

            resetIconButton(
              disabled: generalSettings.updateAutoDownloadEnabled
                == defaultUpdateAutoDownloadEnabled
            ) {
              generalSettings.updateAutoDownloadEnabled = defaultUpdateAutoDownloadEnabled
            }
          }
        }
        .labeledContentStyle(.custom)
      }

      if sections.contains(.safety) {
        LabeledContent("settings.general.confirm.delete_server".localized()) {
          HStack(alignment: .top, spacing: 8) {
            Toggle("", isOn: $generalSettings.confirmDeleteServer)
              .labelsHidden()
            Text(
              generalSettings.confirmDeleteServer
                ? "settings.state.enabled".localized()
                : "settings.state.disabled".localized()
            )
            .foregroundStyle(.secondary)

            resetIconButton(
              disabled: generalSettings.confirmDeleteServer == defaultConfirmDeleteServer
            ) {
              generalSettings.confirmDeleteServer = defaultConfirmDeleteServer
            }
          }
        }
        .labeledContentStyle(.custom)

        LabeledContent("settings.general.confirm.delete_world".localized()) {
          HStack(alignment: .top, spacing: 8) {
            Toggle("", isOn: $generalSettings.confirmDeleteWorld)
              .labelsHidden()
            Text(
              generalSettings.confirmDeleteWorld
                ? "settings.state.enabled".localized()
                : "settings.state.disabled".localized()
            )
            .foregroundStyle(.secondary)

            resetIconButton(
              disabled: generalSettings.confirmDeleteWorld == defaultConfirmDeleteWorld
            ) {
              generalSettings.confirmDeleteWorld = defaultConfirmDeleteWorld
            }
          }
        }
        .labeledContentStyle(.custom)

        LabeledContent("settings.general.confirm.uninstall_resource".localized()) {
          HStack(alignment: .top, spacing: 8) {
            Toggle("", isOn: $generalSettings.confirmUninstallPluginMod)
              .labelsHidden()
            Text(
              generalSettings.confirmUninstallPluginMod
                ? "settings.state.enabled".localized()
                : "settings.state.disabled".localized()
            )
            .foregroundStyle(.secondary)

            resetIconButton(
              disabled: generalSettings.confirmUninstallPluginMod
                == defaultConfirmUninstallPluginMod
            ) {
              generalSettings.confirmUninstallPluginMod = defaultConfirmUninstallPluginMod
            }
          }
        }
        .labeledContentStyle(.custom)

        LabeledContent("settings.general.confirm.exit_running".localized()) {
          HStack(alignment: .top, spacing: 8) {
            Toggle("", isOn: $generalSettings.confirmExitWhileRunning)
              .labelsHidden()
            Text(
              generalSettings.confirmExitWhileRunning
                ? "settings.state.enabled".localized()
                : "settings.state.disabled".localized()
            )
            .foregroundStyle(.secondary)

            resetIconButton(
              disabled: generalSettings.confirmExitWhileRunning == defaultConfirmExitWhileRunning
            ) {
              generalSettings.confirmExitWhileRunning = defaultConfirmExitWhileRunning
            }
          }
        }
        .labeledContentStyle(.custom)
      }

      if sections.contains(.backup) {
        LabeledContent("settings.general.backup.enable".localized()) {
          HStack(alignment: .top, spacing: 8) {
            Toggle("", isOn: $generalSettings.backupAutoEnabled)
              .labelsHidden()
            Text(
              generalSettings.backupAutoEnabled
                ? "settings.state.enabled".localized()
                : "settings.state.disabled".localized()
            )
            .foregroundStyle(.secondary)

            resetIconButton(disabled: generalSettings.backupAutoEnabled == defaultBackupAutoEnabled) {
              generalSettings.backupAutoEnabled = defaultBackupAutoEnabled
            }
          }
        }
        .labeledContentStyle(.custom)

        LabeledContent("settings.general.backup.interval_minutes".localized()) {
          HStack(alignment: .top, spacing: 8) {
            Text("\(generalSettings.backupIntervalMinutes)")
              .frame(minWidth: 56, alignment: .trailing)
              .monospacedDigit()
            Stepper("", value: $generalSettings.backupIntervalMinutes, in: 5...1440)
              .labelsHidden()

            resetIconButton(
              disabled: generalSettings.backupIntervalMinutes == defaultBackupIntervalMinutes
            ) {
              generalSettings.backupIntervalMinutes = defaultBackupIntervalMinutes
            }
          }
        }
        .labeledContentStyle(.custom)

        LabeledContent("settings.general.backup.keep_count".localized()) {
          HStack(alignment: .top, spacing: 8) {
            Text("\(generalSettings.backupKeepCount)")
              .frame(minWidth: 56, alignment: .trailing)
              .monospacedDigit()
            Stepper("", value: $generalSettings.backupKeepCount, in: 1...200)
              .labelsHidden()

            resetIconButton(disabled: generalSettings.backupKeepCount == defaultBackupKeepCount) {
              generalSettings.backupKeepCount = defaultBackupKeepCount
            }
          }
        }
        .labeledContentStyle(.custom)

        LabeledContent("settings.general.backup.before_update".localized()) {
          HStack(alignment: .top, spacing: 8) {
            Toggle("", isOn: $generalSettings.backupBeforeUpdate)
              .labelsHidden()
            Text(
              generalSettings.backupBeforeUpdate
                ? "settings.state.enabled".localized()
                : "settings.state.disabled".localized()
            )
            .foregroundStyle(.secondary)

            resetIconButton(
              disabled: generalSettings.backupBeforeUpdate == defaultBackupBeforeUpdate
            ) {
              generalSettings.backupBeforeUpdate = defaultBackupBeforeUpdate
            }
          }
        }
        .labeledContentStyle(.custom)

        LabeledContent("settings.general.backup.directory".localized()) {
          HStack(alignment: .top, spacing: 8) {
            DirectorySettingRow(
              title: "settings.general.backup.directory".localized(),
              path: generalSettings.backupDirectoryPath,
              description: "settings.general.backup.directory.description".localized(),
              onChoose: { showBackupDirectoryPicker = true },
              onReset: {
                generalSettings.backupDirectoryPath = defaultBackupDirectory
              },
              showsResetButton: false
            )
            .fixedSize()
            .fileImporter(
              isPresented: $showBackupDirectoryPicker,
              allowedContentTypes: [.folder],
              allowsMultipleSelection: false
            ) { result in
              handleBackupDirectoryImport(result)
            }

            resetIconButton(disabled: generalSettings.backupDirectoryPath == defaultBackupDirectory) {
              generalSettings.backupDirectoryPath = defaultBackupDirectory
            }
          }
        }
        .labeledContentStyle(.custom(alignment: .firstTextBaseline))

        LabeledContent("settings.general.backup.manual".localized()) {
          HStack(alignment: .top, spacing: 8) {
            Button(
              isRunningManualBackup
                ? "settings.general.backup.running".localized()
                : "settings.general.backup.run_now".localized()
            ) {
              runManualBackup()
            }
            .disabled(isRunningManualBackup)
            .buttonStyle(.borderedProminent)

            if generalSettings.backupLastTimestamp > 0 {
              Text(
                String(
                  format: "settings.general.backup.last_format".localized(),
                  formattedDate(generalSettings.backupLastTimestamp)
                )
              )
              .font(.caption)
              .foregroundStyle(.secondary)
            }
          }
        }
        .labeledContentStyle(.custom)
      }
    }
    .onAppear {
      applyLaunchAtLoginPreference()
      appUpdateService.applyUserPreferences()
      BackupService.shared.reloadAutoBackupScheduler()
    }
    .onChange(of: generalSettings.launchAtLoginEnabled) { _, _ in
      applyLaunchAtLoginPreference()
    }
    .onChange(of: generalSettings.updateAutoCheckEnabled) { _, _ in
      appUpdateService.applyUserPreferences()
    }
    .onChange(of: generalSettings.updateAutoDownloadEnabled) { _, _ in
      appUpdateService.applyUserPreferences()
    }
    .onChange(of: generalSettings.backupAutoEnabled) { _, _ in
      BackupService.shared.reloadAutoBackupScheduler()
    }
    .onChange(of: generalSettings.backupIntervalMinutes) { _, _ in
      BackupService.shared.reloadAutoBackupScheduler()
    }
    .onChange(of: generalSettings.backupDirectoryPath) { _, _ in
      BackupService.shared.reloadAutoBackupScheduler()
    }
    .onChange(of: generalSettings.backupKeepCount) { _, _ in
      BackupService.shared.reloadAutoBackupScheduler()
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
    .alert("settings.general.backup.alert.title".localized(), isPresented: $showBackupAlert) {
      Button("common.ok".localized(), role: .cancel) {}
    } message: {
      Text(backupAlertMessage)
    }
  }

  // MARK: - Private Methods

  /// 工作路径选择框展示文案：路径最后一段 + 游戏个数
  private func workingPathDisplayString(for item: (path: String, count: Int)) -> String {
    let lastComponent = (item.path as NSString).lastPathComponent
    let countStr = String(format: "settings.working_path.game_count".localized(), item.count)
    return "\(lastComponent) (\(countStr))"
  }

  /// 安全地重置工作目录
  private func resetWorkingDirectorySafely() {
    do {
      let appSupportDirectory = FileManager.default.urls(
        for: .applicationSupportDirectory,
        in: .userDomainMask
      ).first

      guard let supportDir = appSupportDirectory?.appendingPathComponent(Bundle.main.appName) else {
        throw GlobalError.configuration(
          chineseMessage: "无法获取应用支持目录",
          i18nKey: "error.configuration.app_support_directory_not_found",
          level: .popup
        )
      }

      // 确保目录存在
      try FileManager.default.createDirectory(at: supportDir, withIntermediateDirectories: true)

      generalSettings.launcherWorkingDirectory = supportDir.path

      Logger.shared.info("工作目录已重置为: \(supportDir.path)")
    } catch {
      let globalError = GlobalError.from(error)
      GlobalErrorHandler.shared.handle(globalError)
      self.error = globalError
    }
  }

  /// 处理目录导入结果
  private func handleDirectoryImport(_ result: Result<[URL], Error>) {
    switch result {
    case .success(let urls):
      if let url = urls.first {
        do {
          // 验证目录是否可访问
          let resourceValues = try url.resourceValues(forKeys: [.isDirectoryKey, .isReadableKey])
          guard resourceValues.isDirectory == true, resourceValues.isReadable == true else {
            throw GlobalError.fileSystem(
              chineseMessage: "选择的路径不是可读的目录",
              i18nKey: "error.filesystem.invalid_directory_selected",
              level: .notification
            )
          }

          generalSettings.launcherWorkingDirectory = url.path
          // GameRepository 观察者会自动重新加载，无需手动 loadGames

          Logger.shared.info("工作目录已设置为: \(url.path)")
        } catch {
          let globalError = GlobalError.from(error)
          GlobalErrorHandler.shared.handle(globalError)
          self.error = globalError
        }
      }
    case .failure(let error):
      let globalError = GlobalError.fileSystem(
        chineseMessage: "选择目录失败: \(error.localizedDescription)",
        i18nKey: "error.filesystem.directory_selection_failed",
        level: .notification
      )
      GlobalErrorHandler.shared.handle(globalError)
      self.error = globalError
    }
  }

  /// 安全地重启应用
  private func restartAppSafely() {
    do {
      try restartApp()
    } catch {
      let globalError = GlobalError.from(error)
      GlobalErrorHandler.shared.handle(globalError)
      self.error = globalError
    }
  }

  private func applyLaunchAtLoginPreference() {
    do {
      try LaunchAtLoginManager.shared.applyPreference(enabled: generalSettings.launchAtLoginEnabled)
    } catch {
      GlobalErrorHandler.shared.handle(error)
    }
  }

  private func handleBackupDirectoryImport(_ result: Result<[URL], Error>) {
    switch result {
    case .success(let urls):
      guard let url = urls.first else { return }
      do {
        let resourceValues = try url.resourceValues(forKeys: [.isDirectoryKey, .isReadableKey])
        guard resourceValues.isDirectory == true, resourceValues.isReadable == true else {
          throw GlobalError.fileSystem(
            chineseMessage: "备份目录不可访问",
            i18nKey: "error.filesystem.invalid_directory_selected",
            level: .notification
          )
        }
        generalSettings.backupDirectoryPath = url.path
        BackupService.shared.reloadAutoBackupScheduler()
      } catch {
        GlobalErrorHandler.shared.handle(error)
      }
    case .failure(let error):
      GlobalErrorHandler.shared.handle(error)
    }
  }

  private func runManualBackup() {
    guard !isRunningManualBackup else { return }
    isRunningManualBackup = true
    Task { @MainActor in
      defer { isRunningManualBackup = false }
      do {
        let backupURL = try await BackupService.shared.createBackup(reason: "manual")
        backupAlertMessage = String(
          format: "settings.general.backup.alert.success".localized(),
          backupURL.path
        )
      } catch {
        backupAlertMessage = String(
          format: "settings.general.backup.alert.failure".localized(),
          error.localizedDescription
        )
      }
      showBackupAlert = true
    }
  }

  private func formattedDate(_ timestamp: Double) -> String {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
    return formatter.string(from: Date(timeIntervalSince1970: timestamp))
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

/// 重启应用
/// - Throws: GlobalError 当重启失败时
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

// MARK: - Theme Selector View
struct ThemeSelectorView: View {
  @Binding var selectedTheme: ThemeMode

  var body: some View {
    HStack(spacing: 16) {
      ForEach(ThemeMode.allCases, id: \.self) { theme in
        ThemeOptionView(
          theme: theme,
          isSelected: selectedTheme == theme
        ) {
          selectedTheme = theme
        }
      }
    }
  }
}

// MARK: - Theme Option View
struct ThemeOptionView: View {
  let theme: ThemeMode
  let isSelected: Bool
  let onTap: () -> Void

  var body: some View {
    VStack(spacing: 12) {
      // 主题图标
      ZStack {
        RoundedRectangle(cornerRadius: 6)
          .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: isSelected ? 3 : 0)
          .frame(width: 61, height: 41)

        // 窗口图标内容
        ThemeWindowIcon(theme: theme)
          .frame(width: 60, height: 40)
      }

      // 主题标签
      Text(theme.localizedName)
        .font(.caption)
        .foregroundColor(isSelected ? .primary : .secondary)
    }
    .onTapGesture {
      onTap()
    }
    .animation(.easeInOut(duration: 0.2), value: isSelected)
  }
}

// MARK: - Theme Window Icon
struct ThemeWindowIcon: View {
  let theme: ThemeMode

  var body: some View {
    Image(iconName)
      .resizable()
      .frame(width: 60, height: 40)
      .cornerRadius(6)
  }

  private var iconName: String {
    let isSystem26 = ProcessInfo.processInfo.operatingSystemVersion.majorVersion == 26
    switch theme {
    case .system:
      return isSystem26 ? "AppearanceAuto_Normal_Normal" : "AppearanceAuto_Normal"
    case .light:
      return isSystem26 ? "AppearanceLight_Normal_Normal" : "AppearanceLight_Normal"
    case .dark:
      return isSystem26 ? "AppearanceDark_Normal_Normal" : "AppearanceDark_Normal"
    }
  }
}

#Preview {
  GeneralSettingsView()
}
