import Foundation

enum ServerDownloadService {
    struct DownloadTarget {
        let url: URL
        let sha1: String?
        let fileName: String
        let headers: [String: String]?
    }

    static func downloadServerJar(
        serverType: ServerType,
        gameVersion: String,
        loaderVersion: String,
        serverDir: URL
    ) async throws -> String {
        let target = try await resolveDownloadTarget(
            serverType: serverType,
            gameVersion: gameVersion,
            loaderVersion: loaderVersion
        )
        let destinationURL = serverDir.appendingPathComponent(target.fileName)
        _ = try await DownloadManager.downloadFile(
            urlString: target.url.absoluteString,
            destinationURL: destinationURL,
            expectedSha1: target.sha1,
            headers: target.headers
        )
        return target.fileName
    }

    static func resolveDownloadTargetForRemote(
        serverType: ServerType,
        gameVersion: String,
        loaderVersion: String
    ) async throws -> DownloadTarget {
        try await resolveDownloadTarget(
            serverType: serverType,
            gameVersion: gameVersion,
            loaderVersion: loaderVersion
        )
    }

    static func fetchAvailableGameVersions(serverType: ServerType, includeSnapshots: Bool) async throws -> [String] {
        switch serverType {
        case .vanilla, .paper, .custom:
            return try await fetchMojangGameVersions(includeSnapshots: includeSnapshots)
        case .fabric:
            return try await fetchFabricGameVersions(includeSnapshots: includeSnapshots)
        case .forge:
            return try await fetchForgeGameVersions()
        }
    }

    private static func resolveDownloadTarget(
        serverType: ServerType,
        gameVersion: String,
        loaderVersion: String
    ) async throws -> DownloadTarget {
        switch serverType {
        case .vanilla:
            return try await resolveVanilla(gameVersion: gameVersion)
        case .paper:
            return try await resolvePaper(gameVersion: gameVersion)
        case .fabric:
            return try await resolveFabric(gameVersion: gameVersion, loaderVersion: loaderVersion)
        case .forge:
            return try await resolveForge(gameVersion: gameVersion, loaderVersion: loaderVersion)
        case .custom:
            throw GlobalError.validation(
                chineseMessage: "自定义 Jar 不需要下载",
                i18nKey: "error.validation.invalid_download_url",
                level: .notification
            )
        }
    }

    private static func resolveVanilla(gameVersion: String) async throws -> DownloadTarget {
        guard let manifestURL = URL(string: "https://piston-meta.mojang.com/mc/game/version_manifest_v2.json") else {
            throw GlobalError.validation(
                chineseMessage: "无效的下载地址",
                i18nKey: "error.validation.invalid_download_url",
                level: .notification
            )
        }
        let manifest: MojangVersionManifest = try await fetchJSON(url: manifestURL, headers: nil)
        guard let versionInfo = manifest.versions.first(where: { $0.id == gameVersion }) else {
            throw GlobalError.resource(
                chineseMessage: "未找到版本: \(gameVersion)",
                i18nKey: "error.resource.not_found",
                level: .notification
            )
        }
        let versionManifest: MinecraftVersionManifest = try await fetchJSON(url: versionInfo.url, headers: nil)
        guard let serverDownload = versionManifest.downloads.server else {
            throw GlobalError.resource(
                chineseMessage: "该版本没有服务端下载",
                i18nKey: "error.resource.not_found",
                level: .notification
            )
        }
        let fileName = serverDownload.url.lastPathComponent
        return DownloadTarget(
            url: serverDownload.url,
            sha1: serverDownload.sha1,
            fileName: fileName,
            headers: nil
        )
    }

    static func resolveJavaComponent(gameVersion: String) async throws -> String {
        guard let manifestURL = URL(string: "https://piston-meta.mojang.com/mc/game/version_manifest_v2.json") else {
            throw GlobalError.validation(
                chineseMessage: "无效的下载地址",
                i18nKey: "error.validation.invalid_download_url",
                level: .notification
            )
        }
        let manifest: MojangVersionManifest = try await fetchJSON(url: manifestURL, headers: nil)
        guard let versionInfo = manifest.versions.first(where: { $0.id == gameVersion }) else {
            throw GlobalError.resource(
                chineseMessage: "未找到版本: \(gameVersion)",
                i18nKey: "error.resource.not_found",
                level: .notification
            )
        }
        let versionManifest: MinecraftVersionManifest = try await fetchJSON(url: versionInfo.url, headers: nil)
        return versionManifest.javaVersion.component
    }

    private static func resolvePaper(gameVersion: String) async throws -> DownloadTarget {
        guard let url = URL(string: "https://fill.papermc.io/v3/projects/paper/versions/\(gameVersion)/builds") else {
            throw GlobalError.validation(
                chineseMessage: "无效的下载地址",
                i18nKey: "error.validation.invalid_download_url",
                level: .notification
            )
        }
        let headers = ["User-Agent": AppConstants.paperDownloadsUserAgent]
        let builds: [PaperBuild] = try await fetchJSON(url: url, headers: headers)
        guard let build = builds.first(where: { $0.channel.uppercased() == "STABLE" }) else {
            throw GlobalError.resource(
                chineseMessage: "未找到 Paper 稳定版构建",
                i18nKey: "error.resource.not_found",
                level: .notification
            )
        }
        guard let download = build.downloads["server:default"] else {
            throw GlobalError.resource(
                chineseMessage: "未找到 Paper 服务端下载",
                i18nKey: "error.resource.not_found",
                level: .notification
            )
        }
        return DownloadTarget(
            url: download.url,
            sha1: nil,
            fileName: download.name,
            headers: headers
        )
    }

    private static func resolveFabric(gameVersion: String, loaderVersion: String) async throws -> DownloadTarget {
        let loaderURL = URLConfig.API.Fabric.loader.appendingPathComponent(gameVersion)
        let loaderList: [FabricLoaderEntry] = try await fetchJSON(url: loaderURL, headers: nil)
        let selectedLoader: FabricLoaderEntry? = {
            if !loaderVersion.isEmpty {
                return loaderList.first { $0.loader.version == loaderVersion }
            }
            return loaderList.first(where: isStableLoaderEntry) ?? loaderList.first
        }()
        guard let loader = selectedLoader else {
            throw GlobalError.resource(
                chineseMessage: "未找到 Fabric 加载器版本",
                i18nKey: "error.resource.loader_version_not_found",
                level: .notification
            )
        }

        guard let installerURL = URL(string: "https://meta.fabricmc.net/v2/versions/installer") else {
            throw GlobalError.validation(
                chineseMessage: "无效的下载地址",
                i18nKey: "error.validation.invalid_download_url",
                level: .notification
            )
        }
        let installers: [FabricInstaller] = try await fetchJSON(url: installerURL, headers: nil)
        guard let installer = installers.first(where: isStableInstaller) ?? installers.first else {
            throw GlobalError.resource(
                chineseMessage: "未找到 Fabric Installer 版本",
                i18nKey: "error.resource.loader_version_not_found",
                level: .notification
            )
        }

        guard let downloadURL = URL(string: "https://meta.fabricmc.net/v2/versions/loader/\(gameVersion)/\(loader.loader.version)/\(installer.version)/server/jar") else {
            throw GlobalError.validation(
                chineseMessage: "无效的下载地址",
                i18nKey: "error.validation.invalid_download_url",
                level: .notification
            )
        }
        let fileName = "fabric-server-\(gameVersion)-\(loader.loader.version).jar"
        return DownloadTarget(
            url: downloadURL,
            sha1: nil,
            fileName: fileName,
            headers: nil
        )
    }

    private static func resolveForge(gameVersion: String, loaderVersion: String) async throws -> DownloadTarget {
        guard let promotionsURL = URL(string: "https://files.minecraftforge.net/net/minecraftforge/forge/promotions_slim.json") else {
            throw GlobalError.validation(
                chineseMessage: "无效的下载地址",
                i18nKey: "error.validation.invalid_download_url",
                level: .notification
            )
        }
        let promotions: ForgePromotions = try await fetchJSON(url: promotionsURL, headers: nil)

        let resolvedVersion: String = {
            if !loaderVersion.isEmpty { return loaderVersion }
            if let recommended = promotions.promos["\(gameVersion)-recommended"] { return recommended }
            if let latest = promotions.promos["\(gameVersion)-latest"] { return latest }
            return ""
        }()

        if resolvedVersion.isEmpty {
            throw GlobalError.resource(
                chineseMessage: "未找到 Forge 版本",
                i18nKey: "error.resource.forge_loader_version_not_found",
                level: .notification
            )
        }

        let fileName = "forge-\(gameVersion)-\(resolvedVersion)-installer.jar"
        guard let url = URL(string: "https://maven.minecraftforge.net/net/minecraftforge/forge/\(gameVersion)-\(resolvedVersion)/\(fileName)") else {
            throw GlobalError.validation(
                chineseMessage: "无效的下载地址",
                i18nKey: "error.validation.invalid_download_url",
                level: .notification
            )
        }
        return DownloadTarget(url: url, sha1: nil, fileName: fileName, headers: nil)
    }

    static func latestStableFabricLoaderVersion(gameVersion: String) async throws -> String {
        let loaderURL = URLConfig.API.Fabric.loader.appendingPathComponent(gameVersion)
        let loaderList: [FabricLoaderEntry] = try await fetchJSON(url: loaderURL, headers: nil)
        if let stable = loaderList.first(where: isStableLoaderEntry) {
            return stable.loader.version
        }
        if let first = loaderList.first {
            return first.loader.version
        }
        throw GlobalError.resource(
            chineseMessage: "未找到 Fabric 加载器版本",
            i18nKey: "error.resource.loader_version_not_found",
            level: .notification
        )
    }

    static func latestStableForgeVersion(gameVersion: String) async throws -> String {
        guard let promotionsURL = URL(string: "https://files.minecraftforge.net/net/minecraftforge/forge/promotions_slim.json") else {
            throw GlobalError.validation(
                chineseMessage: "无效的下载地址",
                i18nKey: "error.validation.invalid_download_url",
                level: .notification
            )
        }
        let promotions: ForgePromotions = try await fetchJSON(url: promotionsURL, headers: nil)
        if let recommended = promotions.promos["\(gameVersion)-recommended"] { return recommended }
        if let latest = promotions.promos["\(gameVersion)-latest"] { return latest }
        throw GlobalError.resource(
            chineseMessage: "未找到 Forge 版本",
            i18nKey: "error.resource.forge_loader_version_not_found",
            level: .notification
        )
    }

    private static func fetchJSON<T: Decodable>(url: URL, headers: [String: String]?) async throws -> T {
        var request = URLRequest(url: url, timeoutInterval: 30)
        if let headers = headers {
            for (key, value) in headers {
                request.setValue(value, forHTTPHeaderField: key)
            }
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw GlobalError.download(
                chineseMessage: "HTTP 请求失败",
                i18nKey: "error.download.http_status_error",
                level: .notification
            )
        }
        let decoder = JSONDecoder()
        return try decoder.decode(T.self, from: data)
    }

    private static func isStableInstaller(_ item: FabricInstaller) -> Bool {
        item.stable
    }

    private static func isStableLoaderEntry(_ item: FabricLoaderEntry) -> Bool {
        item.loader.stable
    }

    private static func fetchMojangGameVersions(includeSnapshots: Bool) async throws -> [String] {
        guard let manifestURL = URL(string: "https://piston-meta.mojang.com/mc/game/version_manifest_v2.json") else {
            throw GlobalError.validation(
                chineseMessage: "无效的下载地址",
                i18nKey: "error.validation.invalid_download_url",
                level: .notification
            )
        }
        let manifest: MojangVersionManifest = try await fetchJSON(url: manifestURL, headers: nil)
        if includeSnapshots {
            return manifest.versions.map(\.id)
        }
        return manifest.versions.filter { $0.type == "release" }.map(\.id)
    }

    private static func fetchFabricGameVersions(includeSnapshots: Bool) async throws -> [String] {
        guard let url = URL(string: "https://meta.fabricmc.net/v2/versions/game") else {
            throw GlobalError.validation(
                chineseMessage: "无效的下载地址",
                i18nKey: "error.validation.invalid_download_url",
                level: .notification
            )
        }
        let versions: [FabricGameVersionEntry] = try await fetchJSON(url: url, headers: nil)
        if includeSnapshots {
            return versions.map(\.version)
        }
        return versions.filter(\.stable).map(\.version)
    }

    private static func fetchForgeGameVersions() async throws -> [String] {
        guard let promotionsURL = URL(string: "https://files.minecraftforge.net/net/minecraftforge/forge/promotions_slim.json") else {
            throw GlobalError.validation(
                chineseMessage: "无效的下载地址",
                i18nKey: "error.validation.invalid_download_url",
                level: .notification
            )
        }
        let promotions: ForgePromotions = try await fetchJSON(url: promotionsURL, headers: nil)
        let versions = promotions.promos.keys.compactMap { key -> String? in
            let suffixes = ["-recommended", "-latest"]
            guard let suffix = suffixes.first(where: { key.hasSuffix($0) }) else { return nil }
            return String(key.dropLast(suffix.count))
        }
        let unique = Set(versions)
        let sorted = unique.sorted {
            $0.compare($1, options: .numeric) == .orderedDescending
        }
        return sorted
    }
}

struct FabricLoaderEntry: Codable {
    let loader: FabricLoaderVersion
}

struct FabricLoaderVersion: Codable {
    let version: String
    let stable: Bool
}

struct FabricInstaller: Codable {
    let version: String
    let stable: Bool
}

struct FabricGameVersionEntry: Codable {
    let version: String
    let stable: Bool
}

struct PaperBuild: Codable {
    let id: Int
    let time: String
    let channel: String
    let downloads: [String: PaperDownload]
}

struct PaperDownload: Codable {
    let name: String
    let checksums: PaperChecksums
    let size: Int
    let url: URL
}

struct PaperChecksums: Codable {
    let sha256: String
}

struct ForgePromotions: Codable {
    let promos: [String: String]
}
