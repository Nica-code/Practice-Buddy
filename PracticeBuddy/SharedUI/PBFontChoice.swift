import SwiftUI
import UIKit
import CoreText

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
            fallbackDesign: .default
        ),
        headlineRole: .init(
            preferredNames: ["Manrope-Regular", "Manrope"],
            fileStems: ["Manrope-Regular"],
            fallbackDesign: .default
        ),
        bodyRole: .init(
            preferredNames: ["Manrope-Regular", "Manrope"],
            fileStems: ["Manrope-Regular"],
            fallbackDesign: .default
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
        subtitle: "Fredoka + Quicksand + Nunito Sans",
        titleRole: .init(
            preferredNames: ["Fredoka-Regular", "Fredoka"],
            fileStems: ["Fredoka-Regular"],
            fallbackDesign: .rounded
        ),
        headlineRole: .init(
            preferredNames: ["Fredoka-Regular", "Fredoka"],
            fileStems: ["Fredoka-Regular"],
            fallbackDesign: .rounded
        ),
        bodyRole: .init(
            preferredNames: ["Quicksand-Regular", "Quicksand"],
            fileStems: ["Quicksand-Regular"],
            fallbackDesign: .rounded
        ),
        numberRole: .init(
            preferredNames: [
                "NunitoSans-Regular",
                "NunitoSans",
                "NunitoSans10pt-Regular",
                "Nunito Sans"
            ],
            fileStems: ["NunitoSans-VariableFont_YTLC,opsz,wdth,wght"],
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

    func numberFont(size: CGFloat, weight: Font.Weight = .semibold) -> Font {
        font(for: numberRole, size: size, weight: weight)
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

        if let registeredName = PBFontBundleIndex.shared.firstPostScriptName(matchingAnyStem: role.fileStems) {
            return .custom(registeredName, size: size)
        }

        return .system(size: size, weight: weight, design: role.fallbackDesign)
    }

    private func resolvedNameOrFallback(for role: RoleSpec) -> String {
        if let customName = resolvedFontName(from: role.preferredNames) {
            return customName
        }
        if let registeredName = PBFontBundleIndex.shared.firstPostScriptName(matchingAnyStem: role.fileStems) {
            return registeredName
        }
        return "fallback-\(role.fallbackDesign)"
    }

    private func resolvedFontName(from preferredNames: [String]) -> String? {
        for name in preferredNames where UIFont(name: name, size: 14) != nil {
            return name
        }

        return nil
    }
}

private final class PBFontBundleIndex {
    static let shared = PBFontBundleIndex()

    private let postScriptNamesByStem: [String: [String]]

    private init() {
        var map: [String: [String]] = [:]
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: Bundle.main.bundleURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            postScriptNamesByStem = [:]
            return
        }

        for case let fileURL as URL in enumerator {
            let ext = fileURL.pathExtension.lowercased()
            guard ext == "ttf" || ext == "otf" else { continue }

            let stem = fileURL.deletingPathExtension().lastPathComponent.lowercased()
            let names = Self.extractPostScriptNames(from: fileURL)
            if names.isEmpty { continue }
            map[stem] = names
        }

        postScriptNamesByStem = map
    }

    func firstPostScriptName(matchingAnyStem stems: [String]) -> String? {
        for stem in stems {
            if let names = postScriptNamesByStem[stem.lowercased()], let first = names.first {
                return first
            }
        }
        return nil
    }

    private static func extractPostScriptNames(from fileURL: URL) -> [String] {
        guard let descriptors = CTFontManagerCreateFontDescriptorsFromURL(fileURL as CFURL) as? [CTFontDescriptor] else {
            return []
        }

        var names: [String] = []
        for descriptor in descriptors {
            if let name = CTFontDescriptorCopyAttribute(descriptor, kCTFontNameAttribute) as? String, !name.isEmpty {
                if !names.contains(name) {
                    names.append(name)
                }
            }
        }
        return names
    }
}
