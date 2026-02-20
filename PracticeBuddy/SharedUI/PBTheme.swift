import SwiftUI

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

    /// Classic is the visual model for all themes.
    /// In your original Classic, you special-cased dark chrome to pure black.
    /// We apply that uniformly to all themes so tab backgrounds & nav chrome are identical.
    func chromeBackground(for colorScheme: ColorScheme) -> Color {
        if colorScheme == .dark {
            return .black
        }
        return resolvedPalette(for: colorScheme).background
    }

    var background: Color { palette.background }
    var surface: Color { palette.surface }
    var surfaceAlt: Color { palette.surfaceAlt }
    var textPrimary: Color { palette.textPrimary }
    var textSecondary: Color { palette.textSecondary }
    var accent: Color { palette.accent }
}

extension PBTheme {
    static let themePackProductID = "pb_theme_pack" // kept for future, currently unused

    private static func classicBase(accent: Color) -> PBTheme.Palette {
        .init(
            background: Color(uiColor: .systemGroupedBackground),
            surface: Color(uiColor: .secondarySystemGroupedBackground),
            surfaceAlt: Color(uiColor: .tertiarySystemGroupedBackground),
            textPrimary: .primary,
            textSecondary: .secondary,
            accent: accent
        )
    }

    // MARK: - Classic (MODEL)
    static let classic = PBTheme(
        id: "classic",
        name: "Classic",
        access: .free,
        palette: classicBase(accent: .blue),
        dynamicPalette: nil
    )

    // MARK: - Mint (formerly "Midnight")
    // IMPORTANT: Keep id = "midnight" so existing saved selections still work.
    static let midnight = PBTheme(
        id: "midnight",
        name: "Mint",
        access: .free,
        palette: classicBase(accent: Color(red: 0.12, green: 0.62, blue: 0.36)),
        dynamicPalette: nil
    )

    // MARK: - Concert Hall
    static let concertHall = PBTheme(
        id: "concert_hall",
        name: "Concert Hall",
        access: .free,
        palette: classicBase(accent: Color(red: 0.86, green: 0.70, blue: 0.20)),
        dynamicPalette: nil
    )

    // MARK: - Luthier (formerly Warm Maple)
    // IMPORTANT: Keep id = "warm_maple" so existing saved selections still work.
    static let warmMaple = PBTheme(
        id: "warm_maple",
        name: "Luthier",
        access: .free,
        palette: classicBase(accent: Color(red: 0.73, green: 0.33, blue: 0.20)),
        dynamicPalette: nil
    )

    static let all: [PBTheme] = [classic, midnight, concertHall, warmMaple]

    static func byID(_ id: String) -> PBTheme {
        all.first(where: { $0.id == id }) ?? classic
    }
}
