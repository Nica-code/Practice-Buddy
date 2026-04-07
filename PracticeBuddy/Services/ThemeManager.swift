import SwiftUI
import Combine
import UIKit

@MainActor
final class ThemeManager: ObservableObject {

    @AppStorage("pb.settings.colorThemeID") private var colorThemeID: String = PBTheme.classic.id
    @AppStorage("pb.settings.customThemeAccentRed") private var customAccentRed: Double = 0.17
    @AppStorage("pb.settings.customThemeAccentGreen") private var customAccentGreen: Double = 0.47
    @AppStorage("pb.settings.customThemeAccentBlue") private var customAccentBlue: Double = 0.74
    @Published private(set) var theme: PBTheme = .classic

    init() {
        self.theme = resolveTheme(for: colorThemeID)
    }

    func refresh() {
        theme = resolveTheme(for: colorThemeID)
    }

    func select(_ newTheme: PBTheme) {
        colorThemeID = newTheme.id
        theme = resolveTheme(for: newTheme.id)
    }

    var customAccentColor: Color {
        Color(
            red: min(max(customAccentRed, 0), 1),
            green: min(max(customAccentGreen, 0), 1),
            blue: min(max(customAccentBlue, 0), 1)
        )
    }

    var customTheme: PBTheme {
        PBTheme.custom(accent: customAccentColor)
    }

    var isUsingCustomTheme: Bool {
        colorThemeID == PBTheme.customID
    }

    func updateCustomAccent(_ color: Color, applyImmediately: Bool) {
        let uiColor = UIColor(color)
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        guard uiColor.getRed(&red, green: &green, blue: &blue, alpha: &alpha) else { return }

        customAccentRed = min(max(Double(red), 0), 1)
        customAccentGreen = min(max(Double(green), 0), 1)
        customAccentBlue = min(max(Double(blue), 0), 1)

        if applyImmediately || isUsingCustomTheme {
            colorThemeID = PBTheme.customID
            theme = customTheme
        }
    }

    private func resolveTheme(for id: String) -> PBTheme {
        if id == PBTheme.customID {
            return customTheme
        }
        return PBTheme.byID(id)
    }
}
