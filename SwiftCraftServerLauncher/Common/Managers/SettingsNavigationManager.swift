import SwiftUI

final class SettingsNavigationManager: ObservableObject {
    static let shared = SettingsNavigationManager()

    @Published var selectedTab: SettingsTab = .generalBasic

    private init() {}
}
