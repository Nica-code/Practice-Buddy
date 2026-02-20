import SwiftUI

// MARK: - Environment Key

private struct PBTypographyKey: EnvironmentKey {
    static let defaultValue: PBTypography = PBTypography(
        style: .classic,
        fontChoice: .systemDefault
    )
}

extension EnvironmentValues {
    var pbTypography: PBTypography {
        get { self[PBTypographyKey.self] }
        set { self[PBTypographyKey.self] = newValue }
    }
}

// MARK: - View Helpers

extension View {
    /// Injects typography into the environment.
    func pbTypography(_ typography: PBTypography) -> some View {
        self.environment(\.pbTypography, typography)
    }

    /// Applies the global font design "nudge" for the selected font pack.
    ///
    /// This replaces any previous usage of `type.globalDesign` (which no longer exists).
    /// Global font design should be sourced from the *font pack*, not PBTypography.
    func pbGlobalFontDesign(_ fontChoice: PBFontChoice) -> some View {
        // Keep custom font palettes unmodified at the root level.
        self
    }
}
