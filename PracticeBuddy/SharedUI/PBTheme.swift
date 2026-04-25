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
        // Chrome now follows the palette in both modes so the liquid-glass surfaces
        // float over a tinted backdrop instead of pure black.
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
    static let themePackProductID = "pb_theme_pack" // kept for future, currently unused
    static let customID = "custom_accent"

    private static func classicBase(accent: Color) -> PBTheme.Palette {
        .init(
            background: Color(uiColor: UIColor { traits in
                traits.userInterfaceStyle == .dark
                    ? UIColor(red: 0.035, green: 0.040, blue: 0.062, alpha: 1.0)
                    : UIColor.systemGroupedBackground
            }),
            surface: Color(uiColor: UIColor { traits in
                traits.userInterfaceStyle == .dark
                    ? UIColor(red: 0.075, green: 0.082, blue: 0.118, alpha: 1.0)
                    : UIColor.secondarySystemGroupedBackground
            }),
            surfaceAlt: Color(uiColor: UIColor { traits in
                traits.userInterfaceStyle == .dark
                    ? UIColor(red: 0.120, green: 0.130, blue: 0.180, alpha: 1.0)
                    : UIColor.tertiarySystemGroupedBackground
            }),
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
        palette: classicBase(accent: Color(red: 0.28, green: 0.52, blue: 0.96)),
        dynamicPalette: { scheme in
            if scheme == .dark {
                return classicBase(accent: Color(red: 0.45, green: 0.68, blue: 1.0))
            }
            return themedLightBase(
                background: Color(red: 218.0 / 255.0, green: 240.0 / 255.0, blue: 255.0 / 255.0),
                surface: Color(red: 238.0 / 255.0, green: 248.0 / 255.0, blue: 255.0 / 255.0),
                surfaceAlt: Color(red: 170.0 / 255.0, green: 219.0 / 255.0, blue: 255.0 / 255.0),
                accent: Color(red: 0.08, green: 0.38, blue: 1.00),
                textPrimary: Color.black,
                textSecondary: Color(red: 0.09, green: 0.14, blue: 0.22)
            )
        }
    )

    // MARK: - Mint (formerly "Midnight")
    // IMPORTANT: Keep id = "midnight" so existing saved selections still work.
    static let midnight = PBTheme(
        id: "midnight",
        name: "Legato",
        access: .free,
        palette: classicBase(accent: Color(red: 0.10, green: 0.74, blue: 0.52)),
        dynamicPalette: { scheme in
            let lightAccent = Color(red: 0.05, green: 0.66, blue: 0.46)
            let darkAccent = Color(red: 0.30, green: 0.92, blue: 0.66)
            if scheme == .dark {
                return classicBase(accent: darkAccent)
            }
            return themedLightBase(
                background: Color(red: 211.0 / 255.0, green: 248.0 / 255.0, blue: 236.0 / 255.0),
                surface: Color(red: 235.0 / 255.0, green: 255.0 / 255.0, blue: 247.0 / 255.0),
                surfaceAlt: Color(red: 144.0 / 255.0, green: 236.0 / 255.0, blue: 207.0 / 255.0),
                accent: lightAccent,
                textPrimary: Color.black,
                textSecondary: Color(red: 0.05, green: 0.18, blue: 0.14)
            )
        }
    )

    // MARK: - Concert Hall
    static let concertHall = PBTheme(
        id: "concert_hall",
        name: "Concert Hall",
        access: .free,
        palette: classicBase(accent: Color(red: 1.00, green: 0.78, blue: 0.18)),
        dynamicPalette: { scheme in
            let lightAccent = Color(red: 0.98, green: 0.74, blue: 0.10)
            let darkAccent = Color(red: 1.00, green: 0.86, blue: 0.32)
            if scheme == .dark {
                return classicBase(accent: darkAccent)
            }
            return themedLightBase(
                background: Color(red: 255.0 / 255.0, green: 246.0 / 255.0, blue: 210.0 / 255.0),
                surface: Color(red: 255.0 / 255.0, green: 251.0 / 255.0, blue: 232.0 / 255.0),
                surfaceAlt: Color(red: 168.0 / 255.0, green: 231.0 / 255.0, blue: 242.0 / 255.0),
                accent: lightAccent,
                textPrimary: Color.black,
                textSecondary: Color(red: 0.20, green: 0.14, blue: 0.06)
            )
        }
    )

    // MARK: - Luthier (formerly Warm Maple)
    // IMPORTANT: Keep id = "warm_maple" so existing saved selections still work.
    static let warmMaple = PBTheme(
        id: "warm_maple",
        name: "Luthier",
        access: .free,
        palette: classicBase(accent: Color(red: 1.00, green: 0.50, blue: 0.18)),
        dynamicPalette: { scheme in
            let lightAccent = Color(red: 0.98, green: 0.46, blue: 0.14)
            let darkAccent = Color(red: 1.00, green: 0.62, blue: 0.30)
            if scheme == .dark {
                return classicBase(accent: darkAccent)
            }
            return themedLightBase(
                background: Color(red: 255.0 / 255.0, green: 232.0 / 255.0, blue: 216.0 / 255.0),
                surface: Color(red: 255.0 / 255.0, green: 244.0 / 255.0, blue: 230.0 / 255.0),
                surfaceAlt: Color(red: 255.0 / 255.0, green: 169.0 / 255.0, blue: 118.0 / 255.0),
                accent: lightAccent,
                textPrimary: Color.black,
                textSecondary: Color(red: 0.24, green: 0.10, blue: 0.05)
            )
        }
    )

    // MARK: - Appassionato
    static let appassionato = PBTheme(
        id: "appassionato",
        name: "Appassionato",
        access: .free,
        palette: classicBase(accent: Color(red: 0.98, green: 0.18, blue: 0.32)),
        dynamicPalette: { scheme in
            let lightAccent = Color(red: 0.95, green: 0.10, blue: 0.28)
            let darkAccent = Color(red: 1.00, green: 0.36, blue: 0.48)
            if scheme == .dark {
                return classicBase(accent: darkAccent)
            }
            return themedLightBase(
                background: Color(red: 255.0 / 255.0, green: 220.0 / 255.0, blue: 228.0 / 255.0),
                surface: Color(red: 255.0 / 255.0, green: 236.0 / 255.0, blue: 241.0 / 255.0),
                surfaceAlt: Color(red: 177.0 / 255.0, green: 222.0 / 255.0, blue: 255.0 / 255.0),
                accent: lightAccent,
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
            background: Color(red: 252.0 / 255.0, green: 218.0 / 255.0, blue: 234.0 / 255.0),
            surface: Color(red: 255.0 / 255.0, green: 235.0 / 255.0, blue: 245.0 / 255.0),
            surfaceAlt: Color(red: 245.0 / 255.0, green: 188.0 / 255.0, blue: 218.0 / 255.0),
            textPrimary: Color.black,
            textSecondary: Color(red: 0.20, green: 0.10, blue: 0.18),
            accent: Color(red: 0.96, green: 0.28, blue: 0.62)
        ),
        dynamicPalette: { scheme in
            if scheme == .dark {
                return .init(
                    background: Color(red: 0.100, green: 0.045, blue: 0.132),
                    surface: Color(red: 0.170, green: 0.072, blue: 0.205),
                    surfaceAlt: Color(red: 0.255, green: 0.105, blue: 0.315),
                    textPrimary: Color(red: 1.000, green: 0.965, blue: 0.985),
                    textSecondary: Color(red: 0.965, green: 0.820, blue: 0.910),
                    accent: Color(red: 1.00, green: 0.46, blue: 0.78)
                )
            }
            return .init(
                background: Color(red: 255.0 / 255.0, green: 224.0 / 255.0, blue: 241.0 / 255.0),
                surface: Color(red: 255.0 / 255.0, green: 240.0 / 255.0, blue: 250.0 / 255.0),
                surfaceAlt: Color(red: 190.0 / 255.0, green: 214.0 / 255.0, blue: 255.0 / 255.0),
                textPrimary: Color.black,
                textSecondary: Color(red: 0.20, green: 0.10, blue: 0.18),
                accent: Color(red: 0.96, green: 0.28, blue: 0.62)
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
