import Foundation
import Observation

enum AppLanguage: String, CaseIterable, Identifiable {
    case system, english, chinese
    var id: String { rawValue }
    var localeIdentifier: String? { switch self { case .system: nil; case .english: "en"; case .chinese: "zh-Hans" } }
    var title: String { switch self { case .system: String(localized: "System Default"); case .english: "English"; case .chinese: "简体中文" } }
}

@MainActor @Observable final class AppSettings {
    var language: AppLanguage { didSet { UserDefaults.standard.set(language.rawValue, forKey: "app-language") } }
    init() { language = AppLanguage(rawValue: UserDefaults.standard.string(forKey: "app-language") ?? "system") ?? .system }
}
