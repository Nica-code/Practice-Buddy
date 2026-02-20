import SwiftUI
import UIKit

struct TabBarAppearanceConfigurator: UIViewControllerRepresentable {
    let palette: PBTheme.Palette

    func makeUIViewController(context: Context) -> UIViewController {
        // Empty host VC that lives inside the SwiftUI hierarchy.
        UIViewController()
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {
        // Find the nearest UITabBarController in the hierarchy.
        let tabBarController =
            uiViewController.tabBarController ??
            uiViewController.parent?.tabBarController ??
            uiViewController.parent?.parent?.tabBarController

        guard let tbc = tabBarController else { return }

        let appearance = UITabBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = UIColor(palette.surface)

        let normalColor = UIColor(palette.textSecondary)
        let selectedColor = UIColor(palette.accent)

        appearance.stackedLayoutAppearance.normal.iconColor = normalColor
        appearance.stackedLayoutAppearance.normal.titleTextAttributes = [
            .foregroundColor: normalColor
        ]

        appearance.stackedLayoutAppearance.selected.iconColor = selectedColor
        appearance.stackedLayoutAppearance.selected.titleTextAttributes = [
            .foregroundColor: selectedColor
        ]

        // Apply directly to the live tab bar (not just the global appearance proxy).
        tbc.tabBar.standardAppearance = appearance
        tbc.tabBar.scrollEdgeAppearance = appearance

        // Force UIKit to redraw immediately.
        tbc.tabBar.setNeedsLayout()
        tbc.tabBar.layoutIfNeeded()
    }
}
