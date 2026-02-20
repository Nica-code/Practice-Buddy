import SwiftUI

// MARK: - Environment key for PBTheme

private struct PBThemeKey: EnvironmentKey {
    static let defaultValue: PBTheme = .classic
}

extension EnvironmentValues {
    var pbTheme: PBTheme {
        get { self[PBThemeKey.self] }
        set { self[PBThemeKey.self] = newValue }
    }
}

// MARK: - View helper

extension View {
    /// Apply a PBTheme to this view hierarchy.
    func pbTheme(_ theme: PBTheme) -> some View {
        environment(\.pbTheme, theme)
    }
}
