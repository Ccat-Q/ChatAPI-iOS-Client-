import Foundation
import Observation

enum AppLanguage: String, CaseIterable, Identifiable {
    case system, english, chinese
    var id: String { rawValue }
    var localeIdentifier: String? { switch self { case .system: nil; case .english: "en"; case .chinese: "zh-Hans" } }
    var title: String { switch self { case .system: localized("System Default", "跟随系统"); case .english: "English"; case .chinese: "简体中文" } }
}

@MainActor @Observable final class AppSettings {
    var language: AppLanguage { didSet { defaults.set(language.rawValue, forKey: "app-language") } }
    var requiresAppUnlock: Bool { didSet { defaults.set(requiresAppUnlock, forKey: "requires-app-unlock") } }
    @ObservationIgnored private let defaults: UserDefaults
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        language = AppLanguage(rawValue: defaults.string(forKey: "app-language") ?? "system") ?? .system
        requiresAppUnlock = defaults.object(forKey: "requires-app-unlock") as? Bool ?? true
    }
}

func localized(_ english: String, _ chinese: String) -> String {
    let language = AppLanguage(rawValue: UserDefaults.standard.string(forKey: "app-language") ?? "system") ?? .system
    let isChinese = language == .chinese || (language == .system && Locale.preferredLanguages.first?.hasPrefix("zh") == true)
    return isChinese ? chinese : english
}
