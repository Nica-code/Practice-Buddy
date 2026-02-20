import SwiftUI

/// Theme + FontPack-aware typography rules.
/// Goal: slick + clean, with distinct "vibes" per theme without sacrificing readability.
struct PBTypography {

    enum Style {
        case classic
        case mint
        case concertHall
        case warm // fallback for the 4th theme (whatever you name it)
    }

    let style: Style
    let fontChoice: PBFontChoice

    // MARK: - Tracking (subtle polish)

    /// Slightly elegant tracking for big headers (kept subtle)
    var heroTracking: CGFloat {
        switch style {
        case .concertHall: return 0.6
        default: return 0.2
        }
    }

    // MARK: - App Title

    /// Big home title (“Practice Buddy”)
    var appTitle: Font {
        fontChoice.homeTitleFont(size: 34)
    }

    // MARK: - Card / Section Titles

    var sectionTitle: Font {
        fontChoice.headlineFont(weight: .semibold)
    }

    var cardTitle: Font {
        fontChoice.headlineFont(size: UIFont.preferredFont(forTextStyle: .headline).pointSize + 1, weight: .semibold)
    }

    var sheetTitle: Font {
        fontChoice.headlineFont(size: UIFont.preferredFont(forTextStyle: .title3).pointSize, weight: .bold)
    }

    var button: Font {
        switch style {
        case .concertHall:
            return .system(.headline, design: .default)
        default:
            return .system(.headline, design: .rounded)
        }
    }

    var statusLabel: Font {
        fontChoice.bodyFont()
    }

    var body: Font {
        fontChoice.bodyFont()
    }

    var footnote: Font {
        .footnote
    }

    // MARK: - Numbers

    var timer: Font {
        fontChoice.numberFont(size: 28, weight: .bold)
    }

    var number: Font {
        fontChoice.numberFont(size: 16, weight: .semibold)
    }

    // MARK: - Foregrounds (Classic model: text stays textPrimary/textSecondary)

    func appTitleForeground(palette: PBTheme.Palette) -> Color { palette.textPrimary }
    func timerForeground(palette: PBTheme.Palette) -> Color { palette.textPrimary }
    func numberForeground(palette: PBTheme.Palette) -> Color { palette.textPrimary }
    func sectionTitleForeground(palette: PBTheme.Palette) -> Color { palette.textPrimary }

    // MARK: - Factory

    static func forTheme(_ theme: PBTheme, fontChoice: PBFontChoice) -> PBTypography {
        let style: Style
        switch theme.id {
        case PBTheme.classic.id:
            style = .classic
        case PBTheme.midnight.id:
            style = .mint
        case PBTheme.concertHall.id:
            style = .concertHall
        default:
            style = .warm
        }

        return PBTypography(style: style, fontChoice: fontChoice)
    }
}
