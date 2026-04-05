import Foundation
import SwiftUI
import Observation

#if canImport(UIKit)
import UIKit
#endif

enum PBAppIcon: String, CaseIterable, Identifiable {
    case primary

    var id: String { rawValue }

    var displayName: String {
        "Default"
    }

    var assetIconName: String? {
        nil
    }

    var previewImageName: String {
        "IconPreviewDefault"
    }

    static func fromUIKitAlternateName(_ name: String?) -> PBAppIcon {
        _ = name
        return .primary
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

                        Check that AppIcon2 is an iOS App Icon asset with a 1024×1024 image (no transparency).
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
