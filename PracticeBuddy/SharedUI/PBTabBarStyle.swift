import SwiftUI
import UIKit

enum PBTabBarStyle {

    /// Updates UITabBar appearance reliably by applying to *existing visible tab bars*,
    /// not only the global UIAppearance proxy (which can be sticky on newer iOS).
    @MainActor
    static func apply(colorScheme: ColorScheme, accent: UIColor) {
        let appearance = makeAppearance(colorScheme: colorScheme, accent: accent)

        // 1) Set UIAppearance defaults for any future tab bars that get created.
        let proxy = UITabBar.appearance()
        proxy.standardAppearance = appearance
        if #available(iOS 15.0, *) {
            proxy.scrollEdgeAppearance = appearance
        }

        proxy.tintColor = accent
        proxy.unselectedItemTintColor = UIColor.secondaryLabel

        // 2) Apply directly to all visible tab bars right now (critical part).
        applyToVisibleTabBars(appearance: appearance, accent: accent)
    }

    @MainActor
    private static func makeAppearance(colorScheme: ColorScheme, accent: UIColor) -> UITabBarAppearance {
        let appearance = UITabBarAppearance()
        appearance.configureWithDefaultBackground()

        appearance.backgroundEffect = UIBlurEffect(
            style: colorScheme == .dark ? .systemChromeMaterialDark : .systemChromeMaterialLight
        )
        appearance.shadowColor = UIColor.separator.withAlphaComponent(colorScheme == .dark ? 0.25 : 0.15)

        let selected = accent
        let unselected = UIColor.secondaryLabel

        func configure(_ itemAppearance: UITabBarItemAppearance) {
            // Selected
            itemAppearance.selected.iconColor = selected
            itemAppearance.selected.titleTextAttributes = [.foregroundColor: selected]

            // Unselected
            itemAppearance.normal.iconColor = unselected
            itemAppearance.normal.titleTextAttributes = [.foregroundColor: unselected]
        }

        // ✅ IMPORTANT: Configure all layouts so titles never “disappear”
        configure(appearance.stackedLayoutAppearance)
        configure(appearance.inlineLayoutAppearance)
        configure(appearance.compactInlineLayoutAppearance)

        return appearance
    }

    @MainActor
    private static func applyToVisibleTabBars(appearance: UITabBarAppearance, accent: UIColor) {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }

        for scene in scenes {
            for window in scene.windows {
                guard let root = window.rootViewController else { continue }
                applyToTabBars(in: root, appearance: appearance, accent: accent)
            }
        }
    }

    @MainActor
    private static func applyToTabBars(in vc: UIViewController, appearance: UITabBarAppearance, accent: UIColor) {
        if let tab = vc as? UITabBarController {
            tab.tabBar.standardAppearance = appearance
            if #available(iOS 15.0, *) {
                tab.tabBar.scrollEdgeAppearance = appearance
            }

            tab.tabBar.tintColor = accent
            tab.tabBar.unselectedItemTintColor = UIColor.secondaryLabel

            tab.tabBar.setNeedsLayout()
            tab.tabBar.layoutIfNeeded()
        }

        for child in vc.children {
            applyToTabBars(in: child, appearance: appearance, accent: accent)
        }

        if let presented = vc.presentedViewController {
            applyToTabBars(in: presented, appearance: appearance, accent: accent)
        }
    }
}
