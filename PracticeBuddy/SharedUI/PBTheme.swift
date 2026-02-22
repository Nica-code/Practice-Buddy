import SwiftUI
import UIKit

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
        // Pink Neon intentionally keeps pink chrome in dark mode too.
        if id == "pink_neon" {
            return resolvedPalette(for: colorScheme).background
        }
        if colorScheme == .dark {
            return .black
        }
        return resolvedPalette(for: colorScheme).background
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

    private static func themedLightBase(
        background: Color,
        surface: Color,
        surfaceAlt: Color,
        accent: Color,
        textPrimary: Color,
        textSecondary: Color
    ) -> PBTheme.Palette {
        .init(
            background: background,
            surface: surface,
            surfaceAlt: surfaceAlt,
            textPrimary: textPrimary,
            textSecondary: textSecondary,
            accent: accent
        )
    }

    // MARK: - Classic (MODEL)
    static let classic = PBTheme(
        id: "classic",
        name: "Sonata",
        access: .free,
        palette: classicBase(accent: Color(red: 0.17, green: 0.47, blue: 0.74)),
        dynamicPalette: { scheme in
            if scheme == .dark {
                return classicBase(accent: Color(red: 0.17, green: 0.47, blue: 0.74))
            }
            return themedLightBase(
                background: Color(red: 198.0 / 255.0, green: 224.0 / 255.0, blue: 233.0 / 255.0), // Pantone-like 2905 family
                surface: Color(red: 225.0 / 255.0, green: 240.0 / 255.0, blue: 246.0 / 255.0),
                surfaceAlt: Color(red: 174.0 / 255.0, green: 210.0 / 255.0, blue: 224.0 / 255.0),
                accent: Color(red: 0.17, green: 0.47, blue: 0.74),
                textPrimary: Color.black,
                textSecondary: Color(red: 0.13, green: 0.16, blue: 0.20)
            )
        }
    )

    // MARK: - Mint (formerly "Midnight")
    // IMPORTANT: Keep id = "midnight" so existing saved selections still work.
    static let midnight = PBTheme(
        id: "midnight",
        name: "Legato",
        access: .free,
        palette: classicBase(accent: Color(red: 0.14, green: 0.56, blue: 0.35)),
        dynamicPalette: { scheme in
            let accent = Color(red: 0.14, green: 0.56, blue: 0.35)
            if scheme == .dark {
                return classicBase(accent: accent)
            }
            return themedLightBase(
                background: Color(red: 201.0 / 255.0, green: 228.0 / 255.0, blue: 204.0 / 255.0), // Pantone-like 345 family
                surface: Color(red: 225.0 / 255.0, green: 241.0 / 255.0, blue: 227.0 / 255.0),
                surfaceAlt: Color(red: 171.0 / 255.0, green: 210.0 / 255.0, blue: 177.0 / 255.0),
                accent: accent,
                textPrimary: Color.black,
                textSecondary: Color(red: 0.12, green: 0.18, blue: 0.14)
            )
        }
    )

    // MARK: - Concert Hall
    static let concertHall = PBTheme(
        id: "concert_hall",
        name: "Concert Hall",
        access: .free,
        palette: classicBase(accent: Color(red: 0.82, green: 0.64, blue: 0.16)),
        dynamicPalette: { scheme in
            let accent = Color(red: 0.82, green: 0.64, blue: 0.16)
            if scheme == .dark {
                return classicBase(accent: accent)
            }
            return themedLightBase(
                background: Color(red: 248.0 / 255.0, green: 222.0 / 255.0, blue: 141.0 / 255.0), // Pantone 12-0825 TCX Popcorn
                surface: Color(red: 252.0 / 255.0, green: 239.0 / 255.0, blue: 190.0 / 255.0),
                surfaceAlt: Color(red: 244.0 / 255.0, green: 212.0 / 255.0, blue: 112.0 / 255.0),
                accent: accent,
                textPrimary: Color.black,
                textSecondary: Color(red: 0.14, green: 0.14, blue: 0.14)
            )
        }
    )

    // MARK: - Luthier (formerly Warm Maple)
    // IMPORTANT: Keep id = "warm_maple" so existing saved selections still work.
    static let warmMaple = PBTheme(
        id: "warm_maple",
        name: "Luthier",
        access: .free,
        palette: classicBase(accent: Color(red: 0.63, green: 0.35, blue: 0.15)),
        dynamicPalette: { scheme in
            let accent = Color(red: 0.63, green: 0.35, blue: 0.15)
            if scheme == .dark {
                return classicBase(accent: accent)
            }
            return themedLightBase(
                background: Color(red: 227.0 / 255.0, green: 190.0 / 255.0, blue: 141.0 / 255.0), // Pantone-like 728 family
                surface: Color(red: 241.0 / 255.0, green: 214.0 / 255.0, blue: 176.0 / 255.0),
                surfaceAlt: Color(red: 214.0 / 255.0, green: 169.0 / 255.0, blue: 117.0 / 255.0),
                accent: accent,
                textPrimary: Color.black,
                textSecondary: Color(red: 0.16, green: 0.13, blue: 0.10)
            )
        }
    )

    // MARK: - Pink Neon
    static let pinkNeon = PBTheme(
        id: "pink_neon",
        name: "Cantabile",
        access: .free,
        palette: .init(
            background: Color(red: 244.0 / 255.0, green: 194.0 / 255.0, blue: 214.0 / 255.0), // Pantone-like 1895 family
            surface: Color(red: 250.0 / 255.0, green: 223.0 / 255.0, blue: 235.0 / 255.0),
            surfaceAlt: Color(red: 236.0 / 255.0, green: 176.0 / 255.0, blue: 202.0 / 255.0),
            textPrimary: Color.black,
            textSecondary: Color(red: 0.16, green: 0.12, blue: 0.15),
            accent: Color(red: 0.84, green: 0.40, blue: 0.62)
        ),
        dynamicPalette: { scheme in
            if scheme == .dark {
                return .init(
                    background: Color(red: 0.205, green: 0.120, blue: 0.185),
                    surface: Color(red: 0.260, green: 0.155, blue: 0.235),
                    surfaceAlt: Color(red: 0.330, green: 0.195, blue: 0.295),
                    textPrimary: Color(red: 0.996, green: 0.952, blue: 0.980),
                    textSecondary: Color(red: 0.945, green: 0.820, blue: 0.905),
                    accent: Color(red: 0.985, green: 0.700, blue: 0.865)
                )
            }
            return .init(
                background: Color(red: 244.0 / 255.0, green: 194.0 / 255.0, blue: 214.0 / 255.0),
                surface: Color(red: 250.0 / 255.0, green: 223.0 / 255.0, blue: 235.0 / 255.0),
                surfaceAlt: Color(red: 236.0 / 255.0, green: 176.0 / 255.0, blue: 202.0 / 255.0),
                textPrimary: Color.black,
                textSecondary: Color(red: 0.16, green: 0.12, blue: 0.15),
                accent: Color(red: 0.84, green: 0.40, blue: 0.62)
            )
        }
    )

    static let all: [PBTheme] = [pinkNeon, concertHall, midnight, warmMaple, classic]

    static func byID(_ id: String) -> PBTheme {
        all.first(where: { $0.id == id }) ?? classic
    }
}
