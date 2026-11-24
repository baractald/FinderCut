import Foundation

enum AppLanguage: String, CaseIterable {
    case system
    case zhHans = "zh-Hans"
    case zhHant = "zh-Hant"
    case en
    case ja
    case ko
    case fr
    case de
    case es

    var nativeDisplayName: String? {
        switch self {
        case .system: return nil
        case .zhHans: return "简体中文"
        case .zhHant: return "繁體中文"
        case .en: return "English"
        case .ja: return "日本語"
        case .ko: return "한국어"
        case .fr: return "Français"
        case .de: return "Deutsch"
        case .es: return "Español"
        }
    }
}

enum L10n {
    static let selectedLanguageKey = "selectedLanguage"

    static var currentLanguage: AppLanguage {
        get { language(in: .standard) }
        set { setLanguage(newValue, in: .standard) }
    }

    static func language(in defaults: UserDefaults) -> AppLanguage {
        guard let raw = defaults.string(forKey: selectedLanguageKey),
              let lang = AppLanguage(rawValue: raw) else {
            return .system
        }
        return lang
    }

    static func setLanguage(_ language: AppLanguage, in defaults: UserDefaults) {
        if language == .system {
            defaults.removeObject(forKey: selectedLanguageKey)
        } else {
            defaults.set(language.rawValue, forKey: selectedLanguageKey)
        }
    }

    static func resolvedBundle(
        for language: AppLanguage = currentLanguage,
        baseBundle: Bundle = .main
    ) -> Bundle {
        if language != .system,
           let path = baseBundle.path(forResource: language.rawValue, ofType: "lproj"),
           let locBundle = Bundle(path: path) {
            return locBundle
        }
        if let preferred = baseBundle.preferredLocalizations.first,
           let path = baseBundle.path(forResource: preferred, ofType: "lproj"),
           let locBundle = Bundle(path: path) {
            return locBundle
        }
        return baseBundle
    }

    static func resolvedLocale(for language: AppLanguage = currentLanguage) -> Locale {
        if language == .system {
            return Locale.current
        }
        return Locale(identifier: language.rawValue)
    }

    static func string(
        _ key: String,
        language: AppLanguage = currentLanguage,
        baseBundle: Bundle = .main
    ) -> String {
        let bundle = resolvedBundle(for: language, baseBundle: baseBundle)
        return bundle.localizedString(forKey: key, value: nil, table: nil)
    }

    static func format(
        _ key: String,
        language: AppLanguage = currentLanguage,
        baseBundle: Bundle = .main,
        _ args: CVarArg...
    ) -> String {
        let template = string(key, language: language, baseBundle: baseBundle)
        return String(format: template, locale: resolvedLocale(for: language), arguments: args)
    }
}
