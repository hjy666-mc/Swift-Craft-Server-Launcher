import Foundation

class SparkleUpdateService: ObservableObject {
    static let shared = SparkleUpdateService()

    @Published var isCheckingForUpdates = false
    @Published var updateAvailable = false
    @Published var currentVersion = ""
    @Published var latestVersion = ""
    @Published var updateDescription = ""

    private init() {
        currentVersion = Bundle.main.appVersion
    }

    func updateSparkleLanguage(_ language: String) {
        UserDefaults.standard.set([language], forKey: "AppleLanguages")
    }

    func getCurrentArchitecture() -> String {
        Architecture.current.sparkleArch
    }

    func getUpdaterStatus() -> (isInitialized: Bool, sessionInProgress: Bool, isChecking: Bool) {
        (isInitialized: false, sessionInProgress: false, isChecking: isCheckingForUpdates)
    }

    func checkForUpdatesWithUI() {
        isCheckingForUpdates = false
    }

    func checkForUpdatesSilently() {
        isCheckingForUpdates = false
    }
}
