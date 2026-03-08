import Foundation
import SwiftUI

/// 语言管理器
/// 只负责语言列表和 bundle
public class LanguageManager {
    private static let appleLanguagesKey = "AppleLanguages"

    /// 当前选中的语言（取 AppleLanguages 数组的第一个）
    public var selectedLanguage: String {
        get {
            UserDefaults.standard.stringArray(forKey: Self.appleLanguagesKey)?.first ?? ""
        }
        set {
            if newValue.isEmpty {
                UserDefaults.standard.set([String](), forKey: Self.appleLanguagesKey)
            } else {
                var langs = UserDefaults.standard.stringArray(forKey: Self.appleLanguagesKey) ?? []
                langs.removeAll { $0 == newValue }
                langs.insert(newValue, at: 0)
                UserDefaults.standard.set(langs, forKey: Self.appleLanguagesKey)
            }
        }
    }

    /// 单例实例
    public static let shared = LanguageManager()

    private init() {
        // 如果是首次启动（selectedLanguage为空），则根据系统语言设置默认语言
        if selectedLanguage.isEmpty {
            selectedLanguage = Self.getDefaultLanguage()
        }
    }

    /// 支持的语言列表
    public let languages: [(String, String)] = [
        ("🇨🇳 简体中文", "zh-Hans"),
        ("🇺🇸 English", "en"),
    ]

    /// 获取当前语言的 Bundle
    public var bundle: Bundle {
        if let path = Bundle.main.path(forResource: selectedLanguage, ofType: "lproj"),
           let bundle = Bundle(path: path) {
            return bundle
        }
        return .main
    }

    public static func getDefaultLanguage() -> String {

        let preferredLanguages = Locale.preferredLanguages

        for preferredLanguage in preferredLanguages {
            let languageCode = preferredLanguage.prefix(2).lowercased()
            if languageCode == "zh" {
                return "zh-Hans"
            }
            if languageCode == "en" {
                return "en"
            }
        }

        // 仅支持 zh-Hans 与 en，默认英文
        return "en"
    }
}

// MARK: - String Localization Extension

extension String {
    /// 获取本地化字符串
    /// - Parameter bundle: 语言包，默认使用当前语言
    /// - Returns: 本地化后的字符串
    public func localized(
        _ bundle: Bundle = LanguageManager.shared.bundle
    ) -> String {
        bundle.localizedString(forKey: self, value: self, table: nil)
    }
}
