import Foundation

class ServerStatusManager: ObservableObject {
    static let shared = ServerStatusManager()

    @Published private var serverRunningStates: [String: Bool] = [:]
    @Published private var serverLaunchingStates: [String: Bool] = [:]

    private init() {}

    func isServerRunning(serverId: String) -> Bool {
        let hasLocalProcess = ServerProcessManager.shared.getProcess(for: serverId) != nil
        if hasLocalProcess {
            let actuallyRunning = ServerProcessManager.shared.isServerRunning(serverId: serverId)
            DispatchQueue.main.async {
                self.updateServerStatusIfNeeded(serverId: serverId, actuallyRunning: actuallyRunning)
            }
            return actuallyRunning
        }
        return serverRunningStates[serverId] ?? false
    }

    private func updateServerStatusIfNeeded(serverId: String, actuallyRunning: Bool) {
        if let cachedState = serverRunningStates[serverId], cachedState != actuallyRunning {
            serverRunningStates[serverId] = actuallyRunning
            Logger.shared.debug("服务器状态同步更新: \(serverId) -> \(actuallyRunning ? "运行中" : "已停止")")
        } else if serverRunningStates[serverId] == nil {
            serverRunningStates[serverId] = actuallyRunning
        }
    }

    func setServerRunning(serverId: String, isRunning: Bool) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            let currentState = self.serverRunningStates[serverId]
            if currentState != isRunning {
                self.serverRunningStates[serverId] = isRunning
                Logger.shared.debug("服务器状态更新: \(serverId) -> \(isRunning ? "运行中" : "已停止")")
            }
        }
    }

    func setServerLaunching(serverId: String, isLaunching: Bool) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            let currentState = self.serverLaunchingStates[serverId] ?? false
            if currentState != isLaunching {
                self.serverLaunchingStates[serverId] = isLaunching
                Logger.shared.debug("服务器启动中状态更新: \(serverId) -> \(isLaunching ? "启动中" : "非启动中")")
            }
        }
    }

    func isServerLaunching(serverId: String) -> Bool {
        serverLaunchingStates[serverId] ?? false
    }

    func removeServerState(serverId: String) {
        DispatchQueue.main.async { [weak self] in
            self?.serverRunningStates.removeValue(forKey: serverId)
            self?.serverLaunchingStates.removeValue(forKey: serverId)
        }
    }
}
