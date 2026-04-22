import SwiftUI
import Combine
import os
#if canImport(FirebaseAuth)
import FirebaseAuth
#endif

#if canImport(GoogleMobileAds)
import GoogleMobileAds
#endif

enum PBAdPlacement: String, CaseIterable, Identifiable {
    case playBottomBanner = "play.bottom.banner"
    case socialBottomBanner = "social.bottom.banner"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .playBottomBanner:
            return "Play Banner"
        case .socialBottomBanner:
            return "Social Banner"
        }
    }
}

@MainActor
final class PBAdsManager: ObservableObject {
    private enum Keys {
        static let consentAllowsAds = "pb.ads.consentAllowsAds"
        static let showPlaceholders = "pb.ads.showPlaceholders"
        static let enableBanners = "pb.ads.enableBanners"
        static let enableRewardedDuels = "pb.ads.enableRewardedDuels"
        static let enableRealSDK = "pb.ads.enableRealSDK"
        static let killSwitchOverride = "pb.ads.killSwitchOverride"
        static let claimedDuelRewardIDs = "pb.ads.claimedDuelRewardIDs"
    }

    static let testBannerAdUnitID = "ca-app-pub-3940256099942544/2435281174"
    static let testRewardedAdUnitID = "ca-app-pub-3940256099942544/1712485313"

    @Published private(set) var isAdFreeActive: Bool = false
    @Published private(set) var consentAllowsAds: Bool
    @Published private(set) var showPlaceholders: Bool
    @Published private(set) var enableBannerAds: Bool
    @Published private(set) var enableRewardedDuels: Bool
    @Published private(set) var enableRealAdSDK: Bool
    @Published private(set) var killSwitchEnabled: Bool
    @Published private(set) var claimedDuelRewardIDs: Set<String>

    let duelRewardTokenBonus: Int = 5

    #if DEBUG
    private let isDebugBuild = true
    #else
    private let isDebugBuild = false
    #endif

    var adsEnabled: Bool {
        !isAdFreeActive && consentAllowsAds && !killSwitchEnabled
    }

    var canRequestNetworkAds: Bool {
        guard adsEnabled else { return false }
        guard sdkAvailable else { return false }
        if isDebugBuild {
            return enableRealAdSDK
        }
        return true
    }

    var sdkAvailable: Bool {
        #if canImport(GoogleMobileAds)
        true
        #else
        false
        #endif
    }

    var sdkStatusLine: String {
        if killSwitchEnabled {
            return "Ads are disabled by kill switch."
        }
        if !sdkAvailable {
            return "Google Mobile Ads SDK not linked yet."
        }
        if isDebugBuild && !enableRealAdSDK {
            return "SDK linked, real test ads disabled."
        }
        if useTestAdUnits {
            return "SDK linked, using test ad units."
        }
        if AppInfo.productionBannerAdUnitID == nil || AppInfo.productionRewardedAdUnitID == nil {
            return "SDK linked, missing production ad unit IDs."
        }
        return "SDK linked, using production ad units."
    }

    var shouldLogAdDebug: Bool {
        guard let user = currentAuthUser() else { return false }
        return AppInfo.isMasterAccount(uid: user.uid, email: user.email)
    }

    init() {
        let defaults = UserDefaults.standard
        consentAllowsAds = defaults.object(forKey: Keys.consentAllowsAds) as? Bool ?? true
        showPlaceholders = defaults.object(forKey: Keys.showPlaceholders) as? Bool ?? isDebugBuild
        enableBannerAds = defaults.object(forKey: Keys.enableBanners) as? Bool ?? true
        enableRewardedDuels = defaults.object(forKey: Keys.enableRewardedDuels) as? Bool ?? true
        enableRealAdSDK = defaults.object(forKey: Keys.enableRealSDK) as? Bool ?? !isDebugBuild
        let localKillSwitch = defaults.object(forKey: Keys.killSwitchOverride) as? Bool ?? false
        killSwitchEnabled = AppInfo.adsKillSwitchEnabled || localKillSwitch
        claimedDuelRewardIDs = Set(defaults.stringArray(forKey: Keys.claimedDuelRewardIDs) ?? [])

        maybeStartSDK()
    }

    func syncAdFreeStatus(_ hasAdFree: Bool) {
        if isAdFreeActive != hasAdFree {
            isAdFreeActive = hasAdFree
        }
    }

    func setConsentAllowsAds(_ value: Bool) {
        consentAllowsAds = value
        UserDefaults.standard.set(value, forKey: Keys.consentAllowsAds)
    }

    func setShowPlaceholders(_ value: Bool) {
        showPlaceholders = value
        UserDefaults.standard.set(value, forKey: Keys.showPlaceholders)
    }

    func setEnableBannerAds(_ value: Bool) {
        enableBannerAds = value
        UserDefaults.standard.set(value, forKey: Keys.enableBanners)
    }

    func setEnableRewardedDuels(_ value: Bool) {
        enableRewardedDuels = value
        UserDefaults.standard.set(value, forKey: Keys.enableRewardedDuels)
    }

    func setEnableRealAdSDK(_ value: Bool) {
        enableRealAdSDK = value
        UserDefaults.standard.set(value, forKey: Keys.enableRealSDK)
        maybeStartSDK()
    }

    func shouldRenderPlaceholder(for placement: PBAdPlacement) -> Bool {
        guard isDebugBuild else { return false }
        guard showPlaceholders else { return false }
        guard placement == .playBottomBanner || placement == .socialBottomBanner else { return false }
        if canRequestNetworkAds, bannerAdUnitID(for: placement) != nil {
            return false
        }
        return true
    }

    func shouldShowBanner(_ placement: PBAdPlacement) -> Bool {
        guard adsEnabled && enableBannerAds else { return false }
        if shouldRenderPlaceholder(for: placement) {
            return true
        }
        return bannerAdUnitID(for: placement) != nil
    }

    func shouldShowRewardedDuelButton(challengeID: String) -> Bool {
        adsEnabled
            && enableRewardedDuels
            && !claimedDuelRewardIDs.contains(challengeID)
            && rewardedAdUnitID() != nil
    }

    func bannerAdUnitID(for placement: PBAdPlacement) -> String? {
        guard canRequestNetworkAds else { return nil }
        switch placement {
        case .playBottomBanner:
            if useTestAdUnits {
                return Self.testBannerAdUnitID
            }
            return AppInfo.productionBannerAdUnitID
        case .socialBottomBanner:
            if useTestAdUnits {
                return Self.testBannerAdUnitID
            }
            return AppInfo.productionBannerSocialAdUnitID ?? AppInfo.productionBannerAdUnitID
        }
    }

    func markDuelRewardClaimed(challengeID: String) {
        guard !challengeID.isEmpty else { return }
        claimedDuelRewardIDs.insert(challengeID)
        persistClaimedDuelRewards()
    }

    @discardableResult
    func presentRewardedDuelAd(challengeID: String) async -> Bool {
        guard shouldShowRewardedDuelButton(challengeID: challengeID) else { return false }

        #if canImport(GoogleMobileAds)
        guard let adUnitID = rewardedAdUnitID() else {
            logAdDebugInfo("Rewarded ad unit unavailable for challenge \(challengeID)")
            return false
        }
        do {
            logAdDebugInfo("Loading rewarded ad for challenge \(challengeID)")
            let ad = try await RewardedAd.load(with: adUnitID, request: Request())
            guard let root = PBAdRootResolver.rootViewController() else {
                logAdDebugError("Rewarded ad presentation skipped: no root view controller")
                return false
            }
            return await withCheckedContinuation { continuation in
                let bridge = PBRewardedBridge(
                    ad: ad,
                    continuation: continuation,
                    onFinish: { [weak self] in
                        self?.rewardedBridge = nil
                    },
                    shouldLogDebug: shouldLogAdDebug
                )
                self.rewardedBridge = bridge
                bridge.present(from: root)
            }
        } catch {
            logAdDebugError("Rewarded ad load failed: \(error.localizedDescription)")
            return false
        }
        #else
        // SDK unavailable: keep explicit opt-in placeholder path for debug-only testing.
        guard isDebugBuild, showPlaceholders else { return false }
        try? await Task.sleep(for: .milliseconds(850))
        return true
        #endif
    }

    private func persistClaimedDuelRewards() {
        UserDefaults.standard.set(Array(claimedDuelRewardIDs).sorted(), forKey: Keys.claimedDuelRewardIDs)
    }

    private var useTestAdUnits: Bool {
        if AppInfo.useTestAdsOverride {
            return true
        }
        return isDebugBuild || AppInfo.isTestFlightBuild
    }

    private func rewardedAdUnitID() -> String? {
        guard canRequestNetworkAds else { return nil }
        if useTestAdUnits {
            return Self.testRewardedAdUnitID
        }
        return AppInfo.productionRewardedAdUnitID
    }

    private func maybeStartSDK() {
        guard canRequestNetworkAds else { return }
        #if canImport(GoogleMobileAds)
        logAdDebugInfo("Starting Google Mobile Ads SDK")
        MobileAds.shared.start(completionHandler: nil)
        #endif
    }

    private func logAdDebugInfo(_ message: String) {
        guard shouldLogAdDebug else { return }
        PBLog.firebase.info("\(message, privacy: .public)")
    }

    private func logAdDebugError(_ message: String) {
        guard shouldLogAdDebug else { return }
        PBLog.firebase.error("\(message, privacy: .public)")
    }

    #if canImport(FirebaseAuth)
    private func currentAuthUser() -> User? {
        Auth.auth().currentUser
    }
    #else
    private func currentAuthUser() -> Any? {
        nil
    }
    #endif

    #if canImport(GoogleMobileAds)
    private var rewardedBridge: PBRewardedBridge?
    #endif
}

#if canImport(GoogleMobileAds)
private enum PBAdRootResolver {
    static func rootViewController() -> UIViewController? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)?
            .rootViewController
    }
}

@MainActor
private final class PBRewardedBridge: NSObject, FullScreenContentDelegate {
    private let ad: RewardedAd
    private var continuation: CheckedContinuation<Bool, Never>?
    private let onFinish: () -> Void
    private var didEarnReward = false
    private var didResume = false
    private let shouldLogDebug: Bool

    init(
        ad: RewardedAd,
        continuation: CheckedContinuation<Bool, Never>,
        onFinish: @escaping () -> Void,
        shouldLogDebug: Bool
    ) {
        self.ad = ad
        self.continuation = continuation
        self.onFinish = onFinish
        self.shouldLogDebug = shouldLogDebug
        super.init()
        self.ad.fullScreenContentDelegate = self
    }

    func present(from root: UIViewController) {
        ad.present(from: root) { [weak self] in
            self?.didEarnReward = true
        }
    }

    func adDidDismissFullScreenContent(_ ad: FullScreenPresentingAd) {
        finish(result: didEarnReward)
    }

    func ad(_ ad: FullScreenPresentingAd, didFailToPresentFullScreenContentWithError error: any Error) {
        if shouldLogDebug {
            PBLog.firebase.error("Rewarded ad failed to present: \(error.localizedDescription, privacy: .public)")
        }
        finish(result: false)
    }

    private func finish(result: Bool) {
        guard !didResume else { return }
        didResume = true
        continuation?.resume(returning: result)
        continuation = nil
        onFinish()
    }
}
#endif
