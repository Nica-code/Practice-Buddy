import SwiftUI
import Combine
import os
import FirebaseAuth
import FirebaseFirestore
import StoreKit
import UIKit

@MainActor
enum PBAccountType: String, CaseIterable, Identifiable {
    case student
    case teacher

    var id: String { rawValue }

    var title: String {
        switch self {
        case .student: return "Student"
        case .teacher: return "Teacher"
        }
    }
}

@MainActor
enum PBEntitlementTier: String, CaseIterable {
    case free
    case pro
    case allAccess = "all_access"

    var isUnlocked: Bool {
        switch self {
        case .free: return false
        case .pro, .allAccess: return true
        }
    }
}

@MainActor
final class PurchaseManager: ObservableObject {
    static let adFreeMonthlyProductID = "com.alexmalaimare.practicebuddy.adfree.monthly"
    static let adFreeSubscriptionProductIDs = [adFreeMonthlyProductID]
    // Backward-compatible aliases kept during migration.
    static let proMonthlyProductID = adFreeMonthlyProductID
    static let proSubscriptionProductIDs = adFreeSubscriptionProductIDs
    static let entitlementSyncEndpointName = "syncEntitlements"
    static let subscriptionActiveKey = "pb.pro.subscriptionActive"
    static let subscriptionProductIDsKey = "pb.pro.subscriptionProductIDs"
    static let accountTypeKey = "pb.pro.accountType"
    static let entitlementTierKey = "pb.pro.entitlementTier"

    @Published private(set) var ownedProductIDs: Set<String> = []
    @Published private(set) var isPro: Bool
    @Published private(set) var hasActiveSubscription: Bool
    @Published private(set) var entitlementTier: PBEntitlementTier
    @Published private(set) var accountType: PBAccountType
    @Published private(set) var trialUsed: Bool = false
    @Published private(set) var trialEndsAt: Date?
    @Published private(set) var syncStatus: String?
    @Published private(set) var availableProducts: [Product] = []

    /// Subscription state used for ad removal.
    var hasAdFree: Bool { isPro }
    /// Phase 1 rollout: all app features are currently unlocked for everyone.
    var featuresUnlocked: Bool { true }

    private var db: Firestore { Firestore.firestore() }
    private let urlSession = URLSession.shared
    private var userListener: ListenerRegistration?
    private var linkedUID: String?
    private var linkedEmail: String?
    private var isMasterOverride = false
    private var updatesTask: Task<Void, Never>?
    private var foregroundCancellable: AnyCancellable?
    private var lastSyncedUID: String?
    private var lastSyncedStateFingerprint: String?

    init() {
        let defaults = UserDefaults.standard
        let storedSubscriptionActive = defaults.bool(forKey: Self.subscriptionActiveKey)
        let storedSubscriptionIDs = Set(defaults.stringArray(forKey: Self.subscriptionProductIDsKey) ?? [])
        let storedTier = PBEntitlementTier(rawValue: defaults.string(forKey: Self.entitlementTierKey) ?? "") ?? .free
        let storedTypeRaw = defaults.string(forKey: Self.accountTypeKey) ?? PBAccountType.student.rawValue
        let storedType = PBAccountType(rawValue: storedTypeRaw) ?? .student

        hasActiveSubscription = storedSubscriptionActive
        entitlementTier = storedTier
        isPro = false
        accountType = storedType
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
                syncStatus = "Ad-Free subscription is not available right now."
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
                    await self.pushLocalStateToFirestore()
                    return
                }

                if !self.isMasterOverride {
                    let remoteSubscription = data["subscriptionActive"] as? Bool
                    if let remoteSubscription, remoteSubscription != self.hasActiveSubscription {
                        let remoteProductIDs = Set((data["subscriptionProductIDs"] as? [String]) ?? [])
                        self.applySubscriptionState(remoteSubscription, productIDs: remoteProductIDs)
                    }

                    if let tierRaw = data["entitlementTier"] as? String,
                       let tier = PBEntitlementTier(rawValue: tierRaw),
                       tier != self.entitlementTier {
                        self.applyEntitlementTier(tier)
                    }
                }

                if let raw = data["accountType"] as? String,
                   let remoteType = PBAccountType(rawValue: raw),
                   remoteType != self.accountType {
                    self.applyAccountType(remoteType)
                }

                self.trialUsed = data["trialUsed"] as? Bool ?? self.trialUsed
                if let trialTimestamp = data["trialEndsAt"] as? Timestamp {
                    self.trialEndsAt = trialTimestamp.dateValue()
                } else {
                    self.trialEndsAt = nil
                }

                if self.isMasterOverride {
                    self.enforceMasterAccessValues()
                }
            }
        }

        Task {
            await pushLocalStateToFirestore()
        }
    }

    func setAccountType(_ newType: PBAccountType) {
        guard newType != accountType else { return }
        applyAccountType(newType)
        syncStatus = "Switched to \(newType.title) tools."
        Task { await pushLocalStateToFirestore() }
    }

    func completeInitialAccountSetup(as type: PBAccountType) {
        applyAccountType(type)
        syncStatus = nil
        Task { await pushLocalStateToFirestore() }
    }

    func debugUnlockPro() {
        applyEntitlementTier(.allAccess)
        applySubscriptionState(true, productIDs: Set(Self.adFreeSubscriptionProductIDs))
        Task {
            await pushLocalStateToFirestore()
        }
    }

    func debugLockPro() {
        applyEntitlementTier(.free)
        applySubscriptionState(false, productIDs: [])
        Task {
            await pushLocalStateToFirestore()
        }
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
            enforceMasterAccessValues()
            await pushLocalStateToFirestore()
            return
        }

        do {
            let server = try await syncEntitlementsWithServer(activeProductIDs: activeProductIDs, requestTrial: false)
            applySubscriptionState(server.subscriptionActive, productIDs: server.subscriptionProductIDs)
            applyEntitlementTier(server.entitlementTier)
            trialUsed = server.trialUsed
            trialEndsAt = server.trialEndsAt
            syncStatus = nil
        } catch {
            // Keep local StoreKit-derived access as fallback when endpoint is unreachable.
            applySubscriptionState(!activeProductIDs.isEmpty, productIDs: activeProductIDs)
            if !activeProductIDs.isEmpty && entitlementTier == .free {
                applyEntitlementTier(.pro)
            }
            PBLog.firebase.warning("Entitlement server sync failed; using local fallback: \(error.localizedDescription, privacy: .public)")
        }
        await pushLocalStateToFirestore()
    }

    @discardableResult
    func startServerTrialIfEligible() async -> Bool {
        do {
            let server = try await syncEntitlementsWithServer(
                activeProductIDs: ownedProductIDs,
                requestTrial: true
            )
            applySubscriptionState(server.subscriptionActive, productIDs: server.subscriptionProductIDs)
            applyEntitlementTier(server.entitlementTier)
            trialUsed = server.trialUsed
            trialEndsAt = server.trialEndsAt
            await pushLocalStateToFirestore()
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

    private func applyEntitlementTier(_ value: PBEntitlementTier) {
        guard entitlementTier != value else { return }
        entitlementTier = value
        UserDefaults.standard.set(value.rawValue, forKey: Self.entitlementTierKey)
        recalculateProAccess()
    }

    private func recalculateProAccess(now: Date = Date()) {
        let _ = now
        let newPro = isMasterOverride || entitlementTier.isUnlocked || hasActiveSubscription
        if isPro != newPro { isPro = newPro }
    }

    private func applyMasterOverride(_ enabled: Bool) {
        guard enabled != isMasterOverride else {
            if enabled {
                enforceMasterAccessValues()
            }
            return
        }

        isMasterOverride = enabled
        if enabled {
            enforceMasterAccessValues()
            syncStatus = nil
        } else {
            if entitlementTier == .allAccess {
                applyEntitlementTier(hasActiveSubscription ? .pro : .free)
            }
            recalculateProAccess()
        }
    }

    private func enforceMasterAccessValues() {
        applyEntitlementTier(.allAccess)
        recalculateProAccess()
    }

    private func applyAccountType(_ value: PBAccountType) {
        guard accountType != value else { return }
        accountType = value
        UserDefaults.standard.set(value.rawValue, forKey: Self.accountTypeKey)
    }

    private func pushLocalStateToFirestore() async {
        guard let uid = linkedUID else { return }
        guard let authUID = Auth.auth().currentUser?.uid, authUID == uid else {
            PBLog.firebase.warning("Skipped purchase sync: auth user mismatch or missing. uid=\(uid, privacy: .private)")
            return
        }
        let fingerprint = localStateFingerprint()
        if lastSyncedUID == uid, lastSyncedStateFingerprint == fingerprint {
            return
        }
        do {
            // Keep entitlement/subscription fields server-authoritative.
            let payload: [String: Any] = [
                "accountType": accountType.rawValue,
                "updatedAt": FieldValue.serverTimestamp()
            ]
            try await db.collection("users").document(uid).setData(payload, merge: true)
            lastSyncedUID = uid
            lastSyncedStateFingerprint = fingerprint
            syncStatus = nil
        } catch {
            syncStatus = "Subscription sync failed: \(error.localizedDescription)"
        }
    }

    private func localStateFingerprint() -> String {
        return accountType.rawValue
    }

    private func syncEntitlementsWithServer(
        activeProductIDs: Set<String>,
        requestTrial: Bool
    ) async throws -> EntitlementServerState {
        guard let user = Auth.auth().currentUser else {
            throw NSError(
                domain: "PracticeBuddy.Purchase",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "No authenticated Firebase user."]
            )
        }
        guard let baseURL = AppInfo.duelFunctionsBaseURL else {
            throw NSError(
                domain: "PracticeBuddy.Purchase",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Cloud Functions URL is missing."]
            )
        }
        let token = try await user.getIDToken()
        let endpoint = baseURL.appendingPathComponent(Self.entitlementSyncEndpointName)

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(
            withJSONObject: [
                "activeProductIDs": Array(activeProductIDs).sorted(),
                "requestTrial": requestTrial
            ],
            options: []
        )

        let (data, response) = try await urlSession.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw NSError(
                domain: "PracticeBuddy.Purchase",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Invalid entitlement server response."]
            )
        }
        let json = (try? JSONSerialization.jsonObject(with: data, options: [])) as? [String: Any]
        guard (200..<300).contains(http.statusCode) else {
            let message = (json?["error"] as? String) ?? "Entitlement sync failed (\(http.statusCode))."
            throw NSError(
                domain: "PracticeBuddy.Purchase",
                code: http.statusCode,
                userInfo: [NSLocalizedDescriptionKey: message]
            )
        }
        return EntitlementServerState(payload: json ?? [:], fallbackProductIDs: activeProductIDs)
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
            if entitlementTier == .free {
                applyEntitlementTier(.pro)
            }
            applySubscriptionState(true, productIDs: [transaction.productID])
            await pushLocalStateToFirestore()
        }
    }
}

private struct EntitlementServerState {
    let subscriptionActive: Bool
    let subscriptionProductIDs: Set<String>
    let entitlementTier: PBEntitlementTier
    let trialUsed: Bool
    let trialEndsAt: Date?
    let trialStartedNow: Bool

    init(payload: [String: Any], fallbackProductIDs: Set<String>) {
        if let rawIDs = payload["subscriptionProductIDs"] as? [String] {
            subscriptionProductIDs = Set(rawIDs.filter {
                PurchaseManager.adFreeSubscriptionProductIDs.contains($0)
            })
        } else {
            subscriptionProductIDs = fallbackProductIDs
        }
        subscriptionActive = payload["subscriptionActive"] as? Bool ?? !subscriptionProductIDs.isEmpty
        let tierRaw = (payload["entitlementTier"] as? String ?? PBEntitlementTier.free.rawValue)
        entitlementTier = PBEntitlementTier(rawValue: tierRaw) ?? .free
        trialUsed = payload["trialUsed"] as? Bool ?? false
        if let ms = payload["trialEndsAtMs"] as? NSNumber {
            trialEndsAt = Date(timeIntervalSince1970: ms.doubleValue / 1000.0)
        } else {
            trialEndsAt = nil
        }
        trialStartedNow = payload["trialStartedNow"] as? Bool ?? false
    }
}
