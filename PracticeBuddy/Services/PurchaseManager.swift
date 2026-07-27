import SwiftUI
import Combine
import os
import FirebaseFirestore
import StoreKit
import UIKit

@MainActor
enum PBEntitlementTier: String, CaseIterable {
    case free
    case pro
    case allAccess = "all_access"
}

@MainActor
enum PBEntitlementAccessPolicy {
    static func tier(
        activeProductIDs: Set<String>,
        trialEndsAt: Date?,
        hasServerAllAccess: Bool,
        hasLocalMasterAccess: Bool,
        simulatesFreeMode: Bool,
        now: Date = .now
    ) -> PBEntitlementTier {
        if simulatesFreeMode {
            return .free
        }
        if hasServerAllAccess || hasLocalMasterAccess {
            return .allAccess
        }
        if !activeProductIDs.isDisjoint(with: Set(PurchaseManager.proSubscriptionProductIDs)) {
            return .pro
        }
        if let trialEndsAt, trialEndsAt > now {
            return .pro
        }
        return .free
    }
}

struct PBTrialEntitlementState: Equatable {
    let trialUsed: Bool
    let trialEndsAt: Date?
    let trialStartedNow: Bool
    let serverAllAccess: Bool
}

final class PBTrialEntitlementRepository {
    private let callable: FirebaseCallableTransport

    init(callable: FirebaseCallableTransport = FirebaseCallableClient()) {
        self.callable = callable
    }

    func claim() async throws -> PBTrialEntitlementState {
        let response = try await callable.call(
            "entitlementTrialV2",
            data: ["requestTrial": true]
        )
        guard response["ok"] as? Bool == true else {
            throw FirebaseCallableError.invalidResponse
        }
        let trialEndsAt: Date?
        if let ms = response["trialEndsAtMs"] as? NSNumber {
            trialEndsAt = Date(timeIntervalSince1970: ms.doubleValue / 1000.0)
        } else {
            trialEndsAt = nil
        }
        return PBTrialEntitlementState(
            trialUsed: response["trialUsed"] as? Bool ?? false,
            trialEndsAt: trialEndsAt,
            trialStartedNow: response["trialStartedNow"] as? Bool ?? false,
            serverAllAccess: response["serverAllAccess"] as? Bool ?? false
        )
    }
}

@MainActor
final class PurchaseManager: ObservableObject {
    static let adFreeMonthlyProductID = "com.alexmalaimare.practicebuddy.adfree.monthly"
    static let proMonthlyProductID = "com.alexmalaimare.practiquest.pro.monthly"
    // The legacy Ad-Free SKU remains an equivalent Pro entitlement so existing
    // subscribers are grandfathered without an account or receipt migration.
    static let adFreeSubscriptionProductIDs = [proMonthlyProductID, adFreeMonthlyProductID]
    static let proSubscriptionProductIDs = adFreeSubscriptionProductIDs
    static let subscriptionActiveKey = "pb.pro.subscriptionActive"
    static let subscriptionProductIDsKey = "pb.pro.subscriptionProductIDs"
    static let entitlementTierKey = "pb.pro.entitlementTier"
    static let masterSimulateFreeModeKey = "pb.master.simulateFreeMode"

    @Published private(set) var ownedProductIDs: Set<String> = []
    @Published private(set) var isPro: Bool
    @Published private(set) var hasActiveSubscription: Bool
    @Published private(set) var entitlementTier: PBEntitlementTier
    @Published private(set) var masterSimulateFreeMode: Bool
    @Published private(set) var trialUsed: Bool = false
    @Published private(set) var trialEndsAt: Date?
    @Published private(set) var syncStatus: String?
    @Published private(set) var availableProducts: [Product] = []

    /// Subscription state used for ad removal.
    var hasAdFree: Bool { isPro }
    /// Advanced insights, exports, and unlimited presets are Pro benefits.
    /// Core practice, verification, messaging, duels, and progression remain free.
    var featuresUnlocked: Bool { isPro }

    private var db: Firestore { Firestore.firestore() }
    private lazy var trialRepository = PBTrialEntitlementRepository()
    private var userListener: ListenerRegistration?
    private var linkedUID: String?
    private var linkedEmail: String?
    private var isMasterOverride = false
    private var hasServerAllAccess = false
    private var updatesTask: Task<Void, Never>?
    private var foregroundCancellable: AnyCancellable?

    init() {
        let defaults = UserDefaults.standard
        let storedSubscriptionActive = defaults.bool(forKey: Self.subscriptionActiveKey)
        let storedSubscriptionIDs = Set(defaults.stringArray(forKey: Self.subscriptionProductIDsKey) ?? [])
        let storedMasterSimulateFree = defaults.bool(forKey: Self.masterSimulateFreeModeKey)

        hasActiveSubscription = storedSubscriptionActive
        entitlementTier = .free
        isPro = false
        masterSimulateFreeMode = storedMasterSimulateFree
        ownedProductIDs = storedSubscriptionIDs
        if hasActiveSubscription && ownedProductIDs.isEmpty {
            ownedProductIDs = Set(Self.adFreeSubscriptionProductIDs)
        }
        recalculateProAccess()

        updatesTask = observeTransactionUpdates()
        foregroundCancellable = NotificationCenter.default
            .publisher(for: UIApplication.willEnterForegroundNotification)
            .sink { [weak self] _ in
                self?.recalculateProAccess()
            }
        Task {
            await loadProducts()
            await refreshEntitlements()
        }
    }

    deinit {
        userListener?.remove()
        updatesTask?.cancel()
        foregroundCancellable?.cancel()
    }

    func owns(productID: String) -> Bool {
        ownedProductIDs.contains(productID)
    }

    func buy(productID: String) async {
        guard Self.adFreeSubscriptionProductIDs.contains(productID) else { return }

        do {
            if availableProducts.isEmpty {
                await loadProducts()
            }
            guard let product = availableProducts.first(where: { $0.id == productID }) else {
                syncStatus = "PractiQuest Pro is not available right now."
                return
            }

            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                guard case .verified(let transaction) = verification else {
                    syncStatus = "Purchase verification failed."
                    return
                }
                await applyVerifiedTransaction(transaction)
                await transaction.finish()
                await refreshEntitlements()
            case .pending:
                syncStatus = "Purchase pending approval."
            case .userCancelled:
                syncStatus = "Purchase cancelled."
            @unknown default:
                syncStatus = "Unknown purchase result."
            }
        } catch {
            syncStatus = "Purchase failed: \(error.localizedDescription)"
        }
    }

    func restore() async {
        do {
            try await AppStore.sync()
            await refreshEntitlements()
            syncStatus = "Restore completed."
        } catch {
            syncStatus = "Restore failed: \(error.localizedDescription)"
        }
    }

    func linkToUser(uid: String?, email: String? = nil) {
        let normalizedEmail = email?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard linkedUID != uid || linkedEmail != normalizedEmail else { return }
        linkedUID = uid
        linkedEmail = normalizedEmail
        applyMasterOverride(AppInfo.isMasterAccount(uid: uid, email: normalizedEmail))
        userListener?.remove()
        userListener = nil

        guard let uid else { return }
        let ref = db.collection("users").document(uid)

        userListener = ref.addSnapshotListener { [weak self] snapshot, error in
            guard let self else { return }
            Task { @MainActor in
                if let error {
                    self.syncStatus = "Subscription sync error: \(error.localizedDescription)"
                    return
                }

                guard let data = snapshot?.data() else {
                    return
                }

                self.trialUsed = data["trialUsed"] as? Bool ?? self.trialUsed
                if let trialTimestamp = data["trialEndsAt"] as? Timestamp {
                    self.trialEndsAt = trialTimestamp.dateValue()
                } else {
                    self.trialEndsAt = nil
                }
                self.hasServerAllAccess =
                    data["isMasterAccount"] as? Bool == true ||
                    data["entitlementTier"] as? String == PBEntitlementTier.allAccess.rawValue
                self.recalculateProAccess()
            }
        }
    }

    func setMasterSimulateFreeMode(_ enabled: Bool) {
        guard masterSimulateFreeMode != enabled else { return }
        masterSimulateFreeMode = enabled
        UserDefaults.standard.set(enabled, forKey: Self.masterSimulateFreeModeKey)
        recalculateProAccess()
    }

    func debugUnlockPro() {
        hasServerAllAccess = true
        recalculateProAccess()
    }

    func debugLockPro() {
        hasServerAllAccess = false
        applySubscriptionState(false, productIDs: [])
        trialEndsAt = nil
        recalculateProAccess()
    }

    func loadProducts() async {
        do {
            let products = try await Product.products(for: Self.adFreeSubscriptionProductIDs)
            availableProducts = products.sorted(by: { $0.id < $1.id })
        } catch {
            syncStatus = "Could not load products: \(error.localizedDescription)"
        }
    }

    func refreshEntitlements() async {
        let now = Date()
        var activeProductIDs: Set<String> = []
        for await result in StoreKit.Transaction.currentEntitlements {
            guard case .verified(let transaction) = result else { continue }
            guard Self.adFreeSubscriptionProductIDs.contains(transaction.productID) else { continue }
            if let expiration = transaction.expirationDate, expiration <= now { continue }
            if transaction.revocationDate != nil { continue }
            activeProductIDs.insert(transaction.productID)
        }

        if isMasterOverride {
            recalculateProAccess()
            return
        }

        // Verified StoreKit 2 transactions are the paid-entitlement source of
        // truth. Product identifiers are never posted to a server endpoint that
        // could accidentally trust client-supplied ownership.
        applySubscriptionState(!activeProductIDs.isEmpty, productIDs: activeProductIDs)
        recalculateProAccess()
        syncStatus = nil
    }

    @discardableResult
    func startServerTrialIfEligible() async -> Bool {
        do {
            let server = try await trialRepository.claim()
            trialUsed = server.trialUsed
            trialEndsAt = server.trialEndsAt
            hasServerAllAccess = server.serverAllAccess
            recalculateProAccess()
            return server.trialStartedNow || (server.trialEndsAt?.timeIntervalSinceNow ?? 0) > 0
        } catch {
            syncStatus = "Could not start trial right now."
            return false
        }
    }

    private func applySubscriptionState(_ active: Bool, productIDs: Set<String>) {
        guard hasActiveSubscription != active || ownedProductIDs != productIDs else { return }
        hasActiveSubscription = active
        ownedProductIDs = productIDs
        UserDefaults.standard.set(active, forKey: Self.subscriptionActiveKey)
        UserDefaults.standard.set(Array(productIDs).sorted(), forKey: Self.subscriptionProductIDsKey)
        recalculateProAccess()
    }

    private func recalculateProAccess(now: Date = Date()) {
        let nextTier = PBEntitlementAccessPolicy.tier(
            activeProductIDs: ownedProductIDs,
            trialEndsAt: trialEndsAt,
            hasServerAllAccess: hasServerAllAccess,
            hasLocalMasterAccess: isMasterOverride,
            simulatesFreeMode: masterSimulateFreeMode,
            now: now
        )
        if entitlementTier != nextTier {
            entitlementTier = nextTier
            UserDefaults.standard.set(nextTier.rawValue, forKey: Self.entitlementTierKey)
        }
        let newPro = nextTier != .free
        if isPro != newPro { isPro = newPro }
    }

    private func applyMasterOverride(_ enabled: Bool) {
        guard enabled != isMasterOverride else { return }
        isMasterOverride = enabled
        if enabled {
            syncStatus = nil
        }
        recalculateProAccess()
    }

    private func observeTransactionUpdates() -> Task<Void, Never> {
        Task(priority: .background) { [weak self] in
            guard let self else { return }
            for await result in StoreKit.Transaction.updates {
                guard case .verified(let transaction) = result else { continue }
                await self.applyVerifiedTransaction(transaction)
                await transaction.finish()
                await self.refreshEntitlements()
            }
        }
    }

    private func applyVerifiedTransaction(_ transaction: StoreKit.Transaction) async {
        if Self.adFreeSubscriptionProductIDs.contains(transaction.productID) {
            applySubscriptionState(true, productIDs: [transaction.productID])
        }
    }
}
