import Foundation

enum L10n {
    static func f(_ key: String, _ args: CVarArg...) -> String {
        let format = String(localized: String.LocalizationValue(key))
        return String(format: format, locale: Locale.current, arguments: args)
    }
}
