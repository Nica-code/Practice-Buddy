import SwiftUI
import UIKit

/// The app's colour model, expressed in the roles the practice tools ask for.
///
/// This used to be a six-theme catalogue (Sonata, Legato, Concert Hall,
/// Luthier, Appassionato, Cantabile) chosen from a Settings picker. Studio Quest
/// replaced that with a single designed palette and a light/dark control, and
/// the picker was removed — but `ThemeManager` still read the saved
/// `pb.settings.colorThemeID`, so anyone who had picked Cantabile in v1 kept
/// getting pink practice tools inside a cobalt app, with no way to change it.
///
/// There is now one palette and it resolves to `StudioQuestTokens`, which is
/// what ports the practice tools onto the Studio Quest system without touching
/// a line of their layout or logic.
struct PBTheme: Identifiable {
    enum Access: Equatable {
        case free
        case paid(productID: String) // kept for future; currently unused
    }

    struct Palette: Equatable {
        let background: Color
        let surface: Color
        let surfaceAlt: Color
        let textPrimary: Color
        let textSecondary: Color
        let accent: Color
    }

    let id: String
    let name: String
    let access: Access

    let palette: Palette
    let dynamicPalette: ((ColorScheme) -> Palette)?

    func resolvedPalette(for colorScheme: ColorScheme) -> Palette {
        dynamicPalette?(colorScheme) ?? palette
    }

    func chromeBackground(for colorScheme: ColorScheme) -> Color {
        resolvedPalette(for: colorScheme).background
    }

    var background: Color { dynamicColor(\.background) }
    var surface: Color { dynamicColor(\.surface) }
    var surfaceAlt: Color { dynamicColor(\.surfaceAlt) }
    var textPrimary: Color { dynamicColor(\.textPrimary) }
    var textSecondary: Color { dynamicColor(\.textSecondary) }
    var accent: Color { dynamicColor(\.accent) }

    private func dynamicColor(_ keyPath: KeyPath<Palette, Color>) -> Color {
        Color(uiColor: UIColor { traits in
            let scheme: ColorScheme = traits.userInterfaceStyle == .dark ? .dark : .light
            return UIColor(resolvedPalette(for: scheme)[keyPath: keyPath])
        })
    }
}

extension PBTheme {
    static func studioQuestPalette(_ scheme: ColorScheme) -> Palette {
        .init(
            background: StudioQuestTokens.ColorRole.background(scheme),
            surface: StudioQuestTokens.ColorRole.surface(scheme),
            surfaceAlt: StudioQuestTokens.ColorRole.raisedSurface(scheme),
            textPrimary: .primary,
            textSecondary: .secondary,
            accent: StudioQuestTokens.ColorRole.cobalt
        )
    }

    static let studioQuest = PBTheme(
        id: "studio_quest",
        name: "Studio Quest",
        access: .free,
        palette: studioQuestPalette(.light),
        dynamicPalette: { studioQuestPalette($0) }
    )

    static let all: [PBTheme] = [studioQuest]

    /// Deliberately ignores the identifier. Saved values from the v1 picker
    /// ("pink_neon", "concert_hall", …) must not resurrect a palette that no
    /// longer matches the rest of the app.
    static func byID(_ id: String) -> PBTheme { studioQuest }
}
