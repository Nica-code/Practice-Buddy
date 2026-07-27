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
        proxy.unselectedItemTintColor = accent.withAlphaComponent(0.7)

        // 2) Apply directly to all visible tab bars right now (critical part).
        applyToVisibleTabBars(appearance: appearance, accent: accent)
    }

    @MainActor
    private static func makeAppearance(colorScheme: ColorScheme, accent: UIColor) -> UITabBarAppearance {
        let appearance = UITabBarAppearance()
        appearance.configureWithTransparentBackground()

        appearance.backgroundEffect = UIBlurEffect(
            style: colorScheme == .dark ? .systemUltraThinMaterialDark : .systemUltraThinMaterialLight
        )

        let baseBackground = colorScheme == .dark
            ? UIColor(red: 0.06, green: 0.065, blue: 0.09, alpha: 0.82)
            : UIColor.systemBackground.withAlphaComponent(0.78)
        let accentOverlay = accent.withAlphaComponent(colorScheme == .dark ? 0.20 : 0.14)
        appearance.backgroundColor = blendedColor(base: baseBackground, overlay: accentOverlay)
        appearance.shadowColor = accent.withAlphaComponent(colorScheme == .dark ? 0.28 : 0.18)

        let selected = accent
        let unselected = accent.withAlphaComponent(colorScheme == .dark ? 0.58 : 0.62)
        let selectedTextFont = UIFont.systemFont(ofSize: 10, weight: .semibold)
        let normalTextFont = UIFont.systemFont(ofSize: 10, weight: .medium)

        func configure(_ itemAppearance: UITabBarItemAppearance) {
            // Selected
            itemAppearance.selected.iconColor = selected
            itemAppearance.selected.titleTextAttributes = [
                .foregroundColor: selected,
                .font: selectedTextFont
            ]

            // Unselected
            itemAppearance.normal.iconColor = unselected
            itemAppearance.normal.titleTextAttributes = [
                .foregroundColor: unselected,
                .font: normalTextFont
            ]
            itemAppearance.disabled.iconColor = UIColor.secondaryLabel
            itemAppearance.disabled.titleTextAttributes = [
                .foregroundColor: UIColor.secondaryLabel,
                .font: normalTextFont
            ]

            itemAppearance.selected.badgeBackgroundColor = selected.withAlphaComponent(0.96)
            itemAppearance.normal.badgeBackgroundColor = selected.withAlphaComponent(0.74)
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
            tab.tabBar.unselectedItemTintColor = accent.withAlphaComponent(0.7)
            tab.tabBar.isTranslucent = true

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

    private static func blendedColor(base: UIColor, overlay: UIColor) -> UIColor {
        var baseR: CGFloat = 0
        var baseG: CGFloat = 0
        var baseB: CGFloat = 0
        var baseA: CGFloat = 0
        var overR: CGFloat = 0
        var overG: CGFloat = 0
        var overB: CGFloat = 0
        var overA: CGFloat = 0

        base.getRed(&baseR, green: &baseG, blue: &baseB, alpha: &baseA)
        overlay.getRed(&overR, green: &overG, blue: &overB, alpha: &overA)

        let outA = overA + baseA * (1 - overA)
        guard outA > 0 else { return .clear }

        let outR = (overR * overA + baseR * baseA * (1 - overA)) / outA
        let outG = (overG * overA + baseG * baseA * (1 - overA)) / outA
        let outB = (overB * overA + baseB * baseA * (1 - overA)) / outA
        return UIColor(red: outR, green: outG, blue: outB, alpha: outA)
    }
}
