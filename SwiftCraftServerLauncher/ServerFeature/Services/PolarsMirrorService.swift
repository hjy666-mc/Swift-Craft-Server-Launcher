import Foundation

enum PolarsMirrorService {
    struct CoreType: Decodable, Hashable, Identifiable {
        let id: Int
        let name: String
        let description: String?
    }

    struct CoreItem: Decodable, Hashable {
        let name: String
        let downloadURL: String

        enum CodingKeys: String, CodingKey {
            case name
            case downloadURL = "downloadUrl"
        }
    }

    private static let baseURL = URL(string: "https://mirror.polars.cc/api/query/minecraft/core") ?? URL(fileURLWithPath: "/")

    static func fetchCoreTypes() async throws -> [CoreType] {
        let data = try await APIClient.get(url: baseURL)
        return try JSONDecoder().decode([CoreType].self, from: data)
    }

    static func fetchCoreItems(coreTypeId: Int) async throws -> [CoreItem] {
        let url = baseURL.appendingPathComponent("\(coreTypeId)")
        let data = try await APIClient.get(url: url)
        return try JSONDecoder().decode([CoreItem].self, from: data)
    }
}
