import SwiftUI
import UIKit

/// The app ships a single typeface pairing: Space Grotesk for display roles and
/// the system font for body and numerals.
///
/// This used to be a four-entry catalogue backed by a Settings font picker. The
/// picker is gone, and the previous implementation had a quiet bug — once it
/// resolved a custom family it returned `.custom(name:size:)` and dropped the
/// requested weight entirely, so every headline in the practice tools rendered
/// at Regular. Weight is now honoured by selecting the file that is actually cut
/// at that weight.
struct PBFontChoice: Equatable {

    /// Body and numerals stay on the system font deliberately: Space Grotesk has
    /// no Hangul, and PractiQuest ships Korean.
    enum Role: Equatable {
        case display
        case body
        case number

        var fallbackDesign: Font.Design {
            switch self {
            case .display, .body: .default
            case .number: .monospaced
            }
        }
    }

    static let systemDefault = PBFontChoice()

    // MARK: - Display face resolution

    private static func displayFaceName(for weight: Font.Weight) -> String? {
        let name: String
        switch weight {
        case .black, .heavy, .bold: name = "SpaceGrotesk-Bold"
        case .semibold: name = "SpaceGrotesk-SemiBold"
        case .medium: name = "SpaceGrotesk-Medium"
        default: name = "SpaceGrotesk-Regular"
        }
        // Fall back to the system font rather than letting CoreText synthesize
        // a face if the resource is ever missing from the bundle.
        return UIFont(name: name, size: 14) != nil ? name : nil
    }

    private func font(for role: Role, size: CGFloat, weight: Font.Weight) -> Font {
        guard role == .display, let name = Self.displayFaceName(for: weight) else {
            return .system(size: size, weight: weight, design: role.fallbackDesign)
        }
        return .custom(name, size: size)
    }

    // MARK: - Font builders (by role)

    func homeTitleFont(size: CGFloat) -> Font {
        font(for: .display, size: size, weight: .bold)
    }

    func headlineFont(size: CGFloat? = nil, weight: Font.Weight = .semibold) -> Font {
        font(for: .display, size: size ?? 17, weight: weight)
    }

    func bodyFont() -> Font {
        font(for: .body, size: 17, weight: .regular)
    }

    func bodyFont(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        font(for: .body, size: size, weight: weight)
    }

    func numberFont(size: CGFloat, weight: Font.Weight = .semibold) -> Font {
        font(for: .number, size: size, weight: weight)
    }

    /// No global font override: only display roles diverge from the system face.
    func globalOverrideFont() -> Font? { nil }

    // MARK: - UIKit bridge (tab bar)

    func uiTabBarSelectedFont(size: CGFloat = 10) -> UIFont {
        uiFont(size: size, weight: .semibold)
    }

    func uiTabBarNormalFont(size: CGFloat = 10) -> UIFont {
        uiFont(size: size, weight: .medium)
    }

    private func uiFont(size: CGFloat, weight: UIFont.Weight) -> UIFont {
        .systemFont(ofSize: size, weight: weight)
    }
}
