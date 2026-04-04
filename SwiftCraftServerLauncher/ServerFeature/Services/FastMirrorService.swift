import Foundation

enum FastMirrorService {
    struct CoreSummary: Decodable, Hashable {
        let name: String
        let tag: String?
        let recommend: Bool?
        let homepage: String?
        let mcVersions: [String]?

        enum CodingKeys: String, CodingKey {
            case name
            case tag
            case recommend
            case homepage
            case mcVersions = "mc_versions"
        }
    }

    struct CoreInfo: Decodable {
        let name: String
        let tag: String?
        let homepage: String?
        let mcVersions: [String]

        enum CodingKeys: String, CodingKey {
            case name
            case tag
            case homepage
            case mcVersions = "mc_versions"
        }
    }

    struct BuildInfo: Decodable, Hashable {
        let name: String
        let mcVersion: String
        let coreVersion: String
        let updateTime: String?
        let sha1: String?

        enum CodingKeys: String, CodingKey {
            case name
            case mcVersion = "mc_version"
            case coreVersion = "core_version"
            case updateTime = "update_time"
            case sha1
        }
    }

    struct BuildList: Decodable {
        let builds: [BuildInfo]
    }

    struct CoreDetail: Decodable {
        let name: String
        let mcVersion: String
        let coreVersion: String
        let updateTime: String?
        let sha1: String?
        let filename: String
        let downloadURL: String

        enum CodingKeys: String, CodingKey {
            case name
            case mcVersion = "mc_version"
            case coreVersion = "core_version"
            case updateTime = "update_time"
            case sha1
            case filename
            case downloadURL = "download_url"
        }
    }

    struct Response<T: Decodable>: Decodable {
        let data: T?
        let code: String?
        let success: Bool?
        let message: String?
    }

    private static let baseURL = URL(string: "https://download.fastmirror.net/api/v3") ?? URL(fileURLWithPath: "/")

    static func fetchGameVersions(coreName: String) async throws -> [String] {
        let info: CoreInfo = try await requestData(pathComponents: [coreName])
        return info.mcVersions
    }

    static func fetchCores() async throws -> [CoreSummary] {
        let list: [CoreSummary] = try await requestData(pathComponents: [])
        return list
    }

    static func fetchCoreVersions(coreName: String, gameVersion: String) async throws -> [String] {
        let list: BuildList = try await requestData(
            pathComponents: [coreName, gameVersion],
            queryItems: [
                URLQueryItem(name: "offset", value: "0"),
                URLQueryItem(name: "limit", value: "25")
            ]
        )
        let versions = list.builds.map { $0.coreVersion }
        var seen: Set<String> = []
        var unique: [String] = []
        for version in versions where !seen.contains(version) {
            seen.insert(version)
            unique.append(version)
        }
        return unique
    }

    static func fetchCoreDetail(coreName: String, gameVersion: String, coreVersion: String) async throws -> CoreDetail {
        return try await requestData(pathComponents: [coreName, gameVersion, coreVersion])
    }

    static func coreName(for serverType: ServerType) -> String {
        switch serverType {
        case .vanilla:
            return "Vanilla"
        case .paper:
            return "Paper"
        case .fabric:
            return "Fabric"
        case .forge:
            return "Forge"
        case .custom:
            return "Custom"
        }
    }

    static func serverType(for coreName: String) -> ServerType? {
        switch coreName.lowercased() {
        case "vanilla":
            return .vanilla
        case "paper":
            return .paper
        case "fabric":
            return .fabric
        case "forge":
            return .forge
        default:
            return nil
        }
    }

    private static func requestData<T: Decodable>(
        pathComponents: [String],
        queryItems: [URLQueryItem] = []
    ) async throws -> T {
        let url = buildURL(pathComponents: pathComponents, queryItems: queryItems)
        let response: Response<T> = try await APIClient.request(
            url: url,
            headers: ["Accept": "application/json"]
        )
        guard response.success != false, let data = response.data else {
            throw GlobalError.network(
                chineseMessage: response.message ?? "镜像服务不可用",
                i18nKey: "error.network.api_request_failed",
                level: .notification
            )
        }
        return data
    }

    private static func buildURL(pathComponents: [String], queryItems: [URLQueryItem]) -> URL {
        let base = pathComponents.reduce(baseURL) { partial, component in
            partial.appendingPathComponent(component)
        }
        guard !queryItems.isEmpty,
              var components = URLComponents(url: base, resolvingAgainstBaseURL: false) else {
            return base
        }
        components.queryItems = queryItems
        return components.url ?? base
    }
}
