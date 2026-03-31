import Foundation

@MainActor
final class ServerDetailWindowCoordinator: ObservableObject {
    static let shared = ServerDetailWindowCoordinator()

    @Published private(set) var serverId: String?
    @Published private(set) var preferredSection: String = "console"

    private init() {}

    func open(serverId: String, preferredSection: String? = nil) {
        self.serverId = serverId
        if let preferredSection {
            self.preferredSection = preferredSection
        } else {
            self.preferredSection = "console"
        }
        WindowManager.shared.openWindow(id: .serverDetail)
    }
}
