import SwiftUI
import UIKit

struct PBFontChoice: Identifiable, Equatable {

    struct RoleSpec: Equatable {
        let preferredNames: [String]
        let fileStems: [String]
        let fallbackDesign: Font.Design
    }

    // MARK: - Palette roles

    let id: String
    let name: String
    let subtitle: String

    let titleRole: RoleSpec
    let headlineRole: RoleSpec
    let bodyRole: RoleSpec
    let numberRole: RoleSpec

    // MARK: - Storage

    static let selectionKey = "pb.settings.fontID"

    // MARK: - Catalog (Google Fonts)

    static let elegant = PBFontChoice(
        id: "font_google_elegant",
        name: "Elegant",
        subtitle: "Playfair + Lora + IBM Plex Mono",
        titleRole: .init(
            preferredNames: ["PlayfairDisplay-Regular", "Playfair Display"],
            fileStems: ["PlayfairDisplay-Regular"],
            fallbackDesign: .serif
        ),
        headlineRole: .init(
            preferredNames: ["PlayfairDisplay-Regular", "Playfair Display"],
            fileStems: ["PlayfairDisplay-Regular"],
            fallbackDesign: .serif
        ),
        bodyRole: .init(
            preferredNames: ["Lora-Regular", "Lora"],
            fileStems: ["Lora-Regular"],
            fallbackDesign: .serif
        ),
        numberRole: .init(
            preferredNames: ["IBMPlexMono-Regular", "IBM Plex Mono"],
            fileStems: ["IBMPlexMono-Regular"],
            fallbackDesign: .monospaced
        )
    )

    static let minimalistic = PBFontChoice(
        id: "font_google_minimalistic",
        name: "Minimalistic",
        subtitle: "Manrope + Manrope + Roboto Mono",
        titleRole: .init(
            preferredNames: ["Manrope-Regular", "Manrope"],
            fileStems: ["Manrope-Regular"],
            fallbackDesign: .monospaced
        ),
        headlineRole: .init(
            preferredNames: ["Manrope-Regular", "Manrope"],
            fileStems: ["Manrope-Regular"],
            fallbackDesign: .monospaced
        ),
        bodyRole: .init(
            preferredNames: ["Manrope-Regular", "Manrope"],
            fileStems: ["Manrope-Regular"],
            fallbackDesign: .monospaced
        ),
        numberRole: .init(
            preferredNames: ["RobotoMono-Regular", "Roboto Mono"],
            fileStems: ["RobotoMono-Regular"],
            fallbackDesign: .monospaced
        )
    )

    static let modern = PBFontChoice(
        id: "font_google_modern",
        name: "Modern",
        subtitle: "Space Grotesk + Outfit + Space Mono",
        titleRole: .init(
            preferredNames: ["SpaceGrotesk-Regular", "Space Grotesk"],
            fileStems: ["SpaceGrotesk-Regular"],
            fallbackDesign: .default
        ),
        headlineRole: .init(
            preferredNames: ["SpaceGrotesk-Regular", "Space Grotesk"],
            fileStems: ["SpaceGrotesk-Regular"],
            fallbackDesign: .default
        ),
        bodyRole: .init(
            preferredNames: ["Outfit-Regular", "Outfit"],
            fileStems: ["Outfit-Regular"],
            fallbackDesign: .default
        ),
        numberRole: .init(
            preferredNames: ["SpaceMono-Regular", "Space Mono"],
            fileStems: ["SpaceMono-Regular"],
            fallbackDesign: .monospaced
        )
    )

    static let playful = PBFontChoice(
        id: "font_google_playful",
        name: "Playful",
        subtitle: "Bina",
        titleRole: .init(
            preferredNames: ["BinaRegularCalligraphr", "Bina Regular", "Bina-Regular"],
            fileStems: ["Bina"],
            fallbackDesign: .rounded
        ),
        headlineRole: .init(
            preferredNames: ["BinaRegularCalligraphr", "Bina Regular", "Bina-Regular"],
            fileStems: ["Bina"],
            fallbackDesign: .rounded
        ),
        bodyRole: .init(
            preferredNames: ["BinaRegularCalligraphr", "Bina Regular", "Bina-Regular"],
            fileStems: ["Bina"],
            fallbackDesign: .rounded
        ),
        numberRole: .init(
            preferredNames: ["BinaRegularCalligraphr", "Bina Regular", "Bina-Regular"],
            fileStems: ["Bina"],
            fallbackDesign: .rounded
        )
    )

    static let all: [PBFontChoice] = [
        elegant,
        minimalistic,
        modern,
        playful
    ]

    static let systemDefault = modern

    var isPlayful: Bool { id == PBFontChoice.playful.id }

    static func byID(_ id: String) -> PBFontChoice {
        if let found = all.first(where: { $0.id == id }) {
            return found
        }

        // Migrate legacy IDs to nearest new palette.
        switch id {
        case "font_system_default", "font_presto_sans", "font_chamber_sans", "font_studio_sans":
            return minimalistic
        case "font_rounded", "font_pizzicato", "font_rounded_play":
            return playful
        case "font_serif", "font_overture_didot", "font_sonata_book", "font_maestro_palatino", "font_brass_caps", "font_concert_script", "font_editorial_serif", "font_elegant_contrast":
            return elegant
        case "font_studio_type", "font_mono_lab":
            return modern
        default:
            return systemDefault
        }
    }

    // MARK: - Global design hint

    var globalBodyDesign: Font.Design {
        // Keep global design neutral so custom family choices are not overridden.
        .default
    }

    // MARK: - Font builders (by role)

    func homeTitleFont(size: CGFloat) -> Font {
        font(for: titleRole, size: size, weight: .bold)
    }

    func headlineFont(size: CGFloat? = nil, weight: Font.Weight = .semibold) -> Font {
        let s = size ?? 17
        return font(for: headlineRole, size: s, weight: weight)
    }

    func bodyFont() -> Font {
        font(for: bodyRole, size: 17, weight: .regular)
    }

    func bodyFont(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        font(for: bodyRole, size: size, weight: weight)
    }

    func numberFont(size: CGFloat, weight: Font.Weight = .semibold) -> Font {
        font(for: numberRole, size: size, weight: weight)
    }

    func globalOverrideFont() -> Font? {
        guard isPlayful, let customName = resolvedFontName(from: bodyRole.preferredNames) else {
            return nil
        }
        return .custom(customName, size: UIFont.preferredFont(forTextStyle: .body).pointSize)
    }

    // MARK: - UIKit bridge (Tab bar / UIKit surfaces)

    func uiTabBarSelectedFont(size: CGFloat = 10) -> UIFont {
        uiFont(for: headlineRole, size: size, fallbackWeight: .semibold)
    }

    func uiTabBarNormalFont(size: CGFloat = 10) -> UIFont {
        uiFont(for: headlineRole, size: size, fallbackWeight: .medium)
    }

    func resolvedRoleDebugText() -> String {
        let title = resolvedNameOrFallback(for: titleRole)
        let body = resolvedNameOrFallback(for: bodyRole)
        let number = resolvedNameOrFallback(for: numberRole)
        return "title: \(title) | body: \(body) | number: \(number)"
    }

    // MARK: - Internals

    private func font(for role: RoleSpec, size: CGFloat, weight: Font.Weight) -> Font {
        if let customName = resolvedFontName(from: role.preferredNames) {
            return .custom(customName, size: size)
        }

        return .system(size: size, weight: weight, design: role.fallbackDesign)
    }

    private func resolvedNameOrFallback(for role: RoleSpec) -> String {
        if let customName = resolvedFontName(from: role.preferredNames) {
            return customName
        }
        return "fallback-\(role.fallbackDesign)"
    }

    private func resolvedFontName(from preferredNames: [String]) -> String? {
        for name in preferredNames where UIFont(name: name, size: 14) != nil {
            return name
        }

        return nil
    }

    private func uiFont(for role: RoleSpec, size: CGFloat, fallbackWeight: UIFont.Weight) -> UIFont {
        if let customName = resolvedFontName(from: role.preferredNames),
           let font = UIFont(name: customName, size: size) {
            return font
        }
        return UIFont.systemFont(ofSize: size, weight: fallbackWeight)
    }
}
