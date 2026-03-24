import SwiftUI
import UIKit
import os

#if canImport(GoogleMobileAds)
import GoogleMobileAds
#endif

struct PBAdBannerSlot: View {
    let placement: PBAdPlacement

    @EnvironmentObject private var adsManager: PBAdsManager
    @Environment(\.pbTheme) private var theme
    @Environment(\.pbTypography) private var type
    @Environment(\.colorScheme) private var colorScheme

    private var palette: PBTheme.Palette { theme.resolvedPalette(for: colorScheme) }

    var body: some View {
        if adsManager.shouldShowBanner(placement) {
            VStack(spacing: 6) {
                if adsManager.shouldRenderPlaceholder(for: placement) {
                    placeholder
                } else if let adUnitID = adsManager.bannerAdUnitID(for: placement) {
                    #if canImport(GoogleMobileAds)
                    PBAdMobBannerRepresentable(adUnitID: adUnitID)
                        .frame(height: 50)
                    #else
                    placeholder
                    #endif
                } else {
                    EmptyView()
                }
            }
            .padding(.horizontal, PBLayout.padSM)
            .padding(.vertical, 6)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    private var placeholder: some View {
        VStack(spacing: 4) {
            Text("Ad Placeholder")
                .font(type.footnote.weight(.semibold))
                .foregroundStyle(palette.textPrimary)
            Text(placement.title)
                .font(type.footnote)
                .foregroundStyle(palette.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 50)
        .background(
            RoundedRectangle(cornerRadius: PBLayout.radiusControl, style: .continuous)
                .fill(palette.surfaceAlt.opacity(0.95))
                .overlay(
                    RoundedRectangle(cornerRadius: PBLayout.radiusControl, style: .continuous)
                        .stroke(palette.accent.opacity(0.22), style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
                )
        )
    }
}

#if canImport(GoogleMobileAds)
private struct PBAdMobBannerRepresentable: UIViewRepresentable {
    let adUnitID: String

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> BannerView {
        let banner = BannerView(adSize: AdSizeBanner)
        banner.adUnitID = adUnitID
        banner.rootViewController = PBAdRootViewControllerResolver.resolve()
        banner.delegate = context.coordinator
        PBLog.firebase.info("Loading banner ad unit=\(adUnitID, privacy: .public)")
        banner.load(Request())
        return banner
    }

    func updateUIView(_ uiView: BannerView, context: Context) {
        uiView.rootViewController = PBAdRootViewControllerResolver.resolve()
        uiView.delegate = context.coordinator
        if uiView.adUnitID != adUnitID {
            uiView.adUnitID = adUnitID
            PBLog.firebase.info("Reloading banner ad unit=\(adUnitID, privacy: .public)")
            uiView.load(Request())
        }
    }

    final class Coordinator: NSObject, BannerViewDelegate {
        func bannerViewDidReceiveAd(_ bannerView: BannerView) {
            PBLog.firebase.info("Banner ad loaded unit=\(bannerView.adUnitID ?? "", privacy: .public)")
        }

        func bannerView(_ bannerView: BannerView, didFailToReceiveAdWithError error: any Error) {
            PBLog.firebase.error("Banner ad failed unit=\(bannerView.adUnitID ?? "", privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
    }
}

private enum PBAdRootViewControllerResolver {
    static func resolve() -> UIViewController? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)?
            .rootViewController
    }
}
#endif
