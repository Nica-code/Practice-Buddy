import Foundation
import SwiftUI
import Observation

#if canImport(UIKit)
import UIKit
#endif

enum PBAppIcon: String, CaseIterable, Identifiable {
    case primary
    case icon2
    case icon3
    case icon4

    var id: String { rawValue }

    // ✅ Change these names to whatever you want
    var displayName: String {
        switch self {
        case .primary: return "Default"
        case .icon2: return "Noir"
        case .icon3: return "Ocean"
        case .icon4: return "Sunrise"
        }
    }

    /// Must match the App Icon set names in Assets.xcassets exactly.
    var assetIconName: String? {
        switch self {
        case .primary: return nil
        case .icon2: return "AppIcon2"
        case .icon3: return "AppIcon3"
        case .icon4: return "AppIcon4"
        }
    }

    /// Thumbnail image set names (Image Sets in Assets.xcassets)
    var previewImageName: String {
        switch self {
        case .primary: return "IconPreviewDefault"
        case .icon2: return "IconPreview2"
        case .icon3: return "IconPreview3"
        case .icon4: return "IconPreview4"
        }
    }

    static func fromUIKitAlternateName(_ name: String?) -> PBAppIcon {
        guard let name else { return .primary }
        switch name {
        case "AppIcon2": return .icon2
        case "AppIcon3": return .icon3
        case "AppIcon4": return .icon4
        default: return .primary
        }
    }
}

struct PBIconSwitchError: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}

@MainActor
@Observable
final class AppIconManager {
    static let selectionKey = "pb.settings.appIconKey"

    private(set) var selectedIcon: PBAppIcon = .primary
    var lastError: PBIconSwitchError? = nil

    var supportsAlternateIcons: Bool {
        #if canImport(UIKit)
        return UIApplication.shared.supportsAlternateIcons
        #else
        return false
        #endif
    }

    init() {
        syncFromSystem()
    }

    func syncFromSystem() {
        #if canImport(UIKit)
        let applied = PBAppIcon.fromUIKitAlternateName(UIApplication.shared.alternateIconName)
        selectedIcon = applied
        UserDefaults.standard.set(applied.rawValue, forKey: Self.selectionKey)
        #else
        selectedIcon = .primary
        UserDefaults.standard.set(PBAppIcon.primary.rawValue, forKey: Self.selectionKey)
        #endif
    }

    func apply(_ icon: PBAppIcon) {
        // Update UI immediately; if iOS fails we’ll revert + show error.
        selectedIcon = icon
        UserDefaults.standard.set(icon.rawValue, forKey: Self.selectionKey)

        #if canImport(UIKit)
        guard UIApplication.shared.supportsAlternateIcons else {
            lastError = PBIconSwitchError(
                title: "Not Supported",
                message: "This device doesn’t support alternate app icons."
            )
            return
        }

        UIApplication.shared.setAlternateIconName(icon.assetIconName) { error in
            DispatchQueue.main.async {
                if let error {
                    // Revert UI to what iOS actually applied
                    self.syncFromSystem()

                    self.lastError = PBIconSwitchError(
                        title: "Couldn’t Change Icon",
                        message: """
                        iOS refused the icon change.

                        Attempted: \(icon.assetIconName ?? "Default")
                        Error: \(error.localizedDescription)

                        Check that AppIcon2/AppIcon3/AppIcon4 are iOS App Icon assets with a 1024×1024 image (no transparency).
                        """
                    )
                } else {
                    // Success: ensure we’re in sync (optional)
                    self.selectedIcon = icon
                }
            }
        }
        #endif
    }
}
