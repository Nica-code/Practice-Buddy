import SwiftUI
import Combine

@MainActor
final class ThemeManager: ObservableObject {

    @AppStorage("pb.settings.colorThemeID") private var colorThemeID: String = PBTheme.classic.id
    @Published private(set) var theme: PBTheme = .classic

    init() {
        self.theme = PBTheme.byID(colorThemeID)
    }

    func refresh() {
        theme = PBTheme.byID(colorThemeID)
    }

    func select(_ newTheme: PBTheme) {
        colorThemeID = newTheme.id
        theme = newTheme
    }
}
