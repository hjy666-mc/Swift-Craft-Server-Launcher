import Foundation
import Combine

@MainActor
final class ServerConsoleManager: ObservableObject {
    static let shared = ServerConsoleManager()

    @Published private(set) var logs: [String: [String]] = [:]
    private var inputPipes: [String: Pipe] = [:]

    private init() {}

    func attach(serverId: String, input: Pipe, output: Pipe, error: Pipe) {
        inputPipes[serverId] = input

        output.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            if data.isEmpty { return }
            if let text = String(data: data, encoding: .utf8) {
                Task { @MainActor in
                    self?.append(serverId: serverId, text: text)
                }
            }
        }

        error.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            if data.isEmpty { return }
            if let text = String(data: data, encoding: .utf8) {
                Task { @MainActor in
                    self?.append(serverId: serverId, text: text)
                }
            }
        }
    }

    func detach(serverId: String) {
        inputPipes.removeValue(forKey: serverId)
    }

    func send(serverId: String, command: String) {
        guard let pipe = inputPipes[serverId] else { return }
        let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if let data = (trimmed + "\n").data(using: .utf8) {
            pipe.fileHandleForWriting.write(data)
        }
    }

    func logText(for serverId: String) -> String {
        let lines = logs[serverId] ?? []
        return lines.joined()
    }

    private func append(serverId: String, text: String) {
        if logs[serverId] == nil {
            logs[serverId] = []
        }
        logs[serverId]?.append(text)
    }
}
