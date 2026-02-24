import Foundation

enum AppLanguage: String, CaseIterable, Identifiable {
    case system
    case english
    case korean
    case romanian

    var id: String { rawValue }

    var localeIdentifier: String {
        switch self {
        case .system:
            return Locale.current.identifier
        case .english:
            return "en"
        case .korean:
            return "ko"
        case .romanian:
            return "ro"
        }
    }

    var titleKey: String {
        switch self {
        case .system: return "System"
        case .english: return "English"
        case .korean: return "Korean"
        case .romanian: return "Romanian"
        }
    }
}
