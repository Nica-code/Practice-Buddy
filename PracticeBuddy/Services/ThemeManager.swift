import SwiftUI
import Combine

/// Vestigial from the v1 theme picker, kept because the practice tools and the
/// tab-bar chrome still read a `PBTheme` from the environment. There is exactly
/// one theme now, so this no longer consults the saved `pb.settings.colorThemeID`
/// — see the note on `PBTheme`.
@MainActor
final class ThemeManager: ObservableObject {
    @Published private(set) var theme: PBTheme = .studioQuest

    func refresh() {
        theme = .studioQuest
    }
}
