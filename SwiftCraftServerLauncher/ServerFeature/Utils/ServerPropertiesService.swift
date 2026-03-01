import Foundation

enum ServerPropertiesService {
    static func readProperties(serverDir: URL) throws -> [String: String] {
        let url = serverDir.appendingPathComponent("server.properties")
        guard FileManager.default.fileExists(atPath: url.path) else {
            return [:]
        }
        let content = try String(contentsOf: url, encoding: .utf8)
        var result: [String: String] = [:]
        for line in content.split(separator: "\n", omittingEmptySubsequences: false) {
            let raw = String(line)
            if raw.trimmingCharacters(in: .whitespaces).isEmpty { continue }
            if raw.hasPrefix("#") { continue }
            if let idx = raw.firstIndex(of: "=") {
                let key = String(raw[..<idx]).trimmingCharacters(in: .whitespaces)
                let value = String(raw[raw.index(after: idx)...]).trimmingCharacters(in: .whitespaces)
                result[key] = value
            }
        }
        return result
    }

    static func writeProperties(serverDir: URL, properties: [String: String]) throws {
        let url = serverDir.appendingPathComponent("server.properties")
        let keys = properties.keys.sorted()
        let lines = keys.map { "\($0)=\(properties[$0] ?? "")" }
        let content = lines.joined(separator: "\n") + "\n"
        try content.data(using: .utf8)?.write(to: url, options: .atomic)
    }
}
