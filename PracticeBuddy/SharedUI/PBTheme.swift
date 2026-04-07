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
    static let customID = "custom_accent"

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
        palette: classicBase(accent: Color(red: 250.0 / 255.0, green: 187.0 / 255.0, blue: 20.0 / 255.0)),
        dynamicPalette: { scheme in
            let accent = Color(red: 250.0 / 255.0, green: 187.0 / 255.0, blue: 20.0 / 255.0)
            if scheme == .dark {
                return classicBase(accent: accent)
            }
            return themedLightBase(
                background: Color(red: 255.0 / 255.0, green: 243.0 / 255.0, blue: 207.0 / 255.0),
                surface: Color(red: 255.0 / 255.0, green: 231.0 / 255.0, blue: 173.0 / 255.0),
                surfaceAlt: Color(red: 255.0 / 255.0, green: 211.0 / 255.0, blue: 107.0 / 255.0),
                accent: accent,
                textPrimary: Color.black,
                textSecondary: Color(red: 0.20, green: 0.15, blue: 0.07)
            )
        }
    )

    // MARK: - Luthier (formerly Warm Maple)
    // IMPORTANT: Keep id = "warm_maple" so existing saved selections still work.
    static let warmMaple = PBTheme(
        id: "warm_maple",
        name: "Luthier",
        access: .free,
        palette: classicBase(accent: Color(red: 242.0 / 255.0, green: 138.0 / 255.0, blue: 49.0 / 255.0)),
        dynamicPalette: { scheme in
            let accent = Color(red: 242.0 / 255.0, green: 138.0 / 255.0, blue: 49.0 / 255.0)
            if scheme == .dark {
                return classicBase(accent: accent)
            }
            return themedLightBase(
                background: Color(red: 255.0 / 255.0, green: 240.0 / 255.0, blue: 228.0 / 255.0),
                surface: Color(red: 255.0 / 255.0, green: 225.0 / 255.0, blue: 203.0 / 255.0),
                surfaceAlt: Color(red: 255.0 / 255.0, green: 192.0 / 255.0, blue: 138.0 / 255.0),
                accent: accent,
                textPrimary: Color.black,
                textSecondary: Color(red: 0.23, green: 0.14, blue: 0.08)
            )
        }
    )

    // MARK: - Appassionato
    static let appassionato = PBTheme(
        id: "appassionato",
        name: "Appassionato",
        access: .free,
        palette: classicBase(accent: Color(red: 248.0 / 255.0, green: 11.0 / 255.0, blue: 4.0 / 255.0)),
        dynamicPalette: { scheme in
            let accent = Color(red: 248.0 / 255.0, green: 11.0 / 255.0, blue: 4.0 / 255.0)
            if scheme == .dark {
                return classicBase(accent: accent)
            }
            return themedLightBase(
                background: Color(red: 255.0 / 255.0, green: 227.0 / 255.0, blue: 226.0 / 255.0),
                surface: Color(red: 255.0 / 255.0, green: 208.0 / 255.0, blue: 206.0 / 255.0),
                surfaceAlt: Color(red: 255.0 / 255.0, green: 173.0 / 255.0, blue: 169.0 / 255.0),
                accent: accent,
                textPrimary: Color.black,
                textSecondary: Color(red: 0.24, green: 0.07, blue: 0.06)
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

    static let all: [PBTheme] = [pinkNeon, concertHall, midnight, warmMaple, appassionato, classic]

    static func byID(_ id: String) -> PBTheme {
        all.first(where: { $0.id == id }) ?? classic
    }

    static func custom(accent: Color) -> PBTheme {
        PBTheme(
            id: customID,
            name: "Custom",
            access: .free,
            palette: classicBase(accent: accent),
            dynamicPalette: { scheme in
                if scheme == .dark {
                    return classicBase(accent: accent)
                }

                let accentUIColor = UIColor(accent)
                let background = Color(uiColor: blended(
                    UIColor.systemGroupedBackground,
                    with: accentUIColor,
                    amount: 0.18
                ))
                let surface = Color(uiColor: blended(
                    UIColor.secondarySystemGroupedBackground,
                    with: accentUIColor,
                    amount: 0.14
                ))
                let surfaceAlt = Color(uiColor: blended(
                    UIColor.tertiarySystemGroupedBackground,
                    with: accentUIColor,
                    amount: 0.22
                ))

                return themedLightBase(
                    background: background,
                    surface: surface,
                    surfaceAlt: surfaceAlt,
                    accent: accent,
                    textPrimary: .black,
                    textSecondary: Color(red: 0.13, green: 0.16, blue: 0.20)
                )
            }
        )
    }

    private static func blended(_ base: UIColor, with accent: UIColor, amount: CGFloat) -> UIColor {
        let clamped = min(max(amount, 0), 1)

        var br: CGFloat = 0
        var bg: CGFloat = 0
        var bb: CGFloat = 0
        var ba: CGFloat = 0
        base.getRed(&br, green: &bg, blue: &bb, alpha: &ba)

        var ar: CGFloat = 0
        var ag: CGFloat = 0
        var ab: CGFloat = 0
        var aa: CGFloat = 0
        accent.getRed(&ar, green: &ag, blue: &ab, alpha: &aa)

        return UIColor(
            red: br * (1 - clamped) + ar * clamped,
            green: bg * (1 - clamped) + ag * clamped,
            blue: bb * (1 - clamped) + ab * clamped,
            alpha: 1
        )
    }
}
