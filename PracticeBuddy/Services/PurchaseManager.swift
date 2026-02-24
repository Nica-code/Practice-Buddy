import SwiftUI
import Combine
import FirebaseFirestore
import FirebaseAuth
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
    static let proProductID = "practicebuddy.pro.lifetime"
    static let proTrialDurationDays = 7
    static let proKey = "pb.pro.isUnlocked"
    static let accountTypeKey = "pb.pro.accountType"
    static let enabledRolesKey = "pb.pro.enabledRoles"
    static let accountTypeSetKey = "pb.pro.accountTypeSet"
    static let accountTypeChangeUsedKey = "pb.pro.accountTypeChangeUsed"
    static let entitlementTierKey = "pb.pro.entitlementTier"
    static let canSwitchRoleFreelyKey = "pb.pro.canSwitchRoleFreely"
    static let isMasterAccountKey = "pb.pro.isMasterAccount"
    static let trialUsedKey = "pb.pro.trialUsed"
    static let trialStartedAtKey = "pb.pro.trialStartedAt"
    static let trialEndsAtKey = "pb.pro.trialEndsAt"

    @Published private(set) var ownedProductIDs: Set<String> = []
    @Published private(set) var isPro: Bool
    @Published private(set) var hasLifetimePro: Bool
    @Published private(set) var entitlementTier: PBEntitlementTier
    @Published private(set) var canSwitchRoleFreely: Bool
    @Published private(set) var isMasterAccount: Bool
    @Published private(set) var isProTrialActive: Bool
    @Published private(set) var hasUsedProTrial: Bool
    @Published private(set) var proTrialStartedAt: Date?
    @Published private(set) var proTrialEndsAt: Date?
    @Published private(set) var accountType: PBAccountType
    @Published private(set) var enabledRoles: Set<PBAccountType>
    @Published private(set) var hasCompletedInitialRoleSelection: Bool
    @Published private(set) var accountTypeChangeUsed: Bool
    @Published private(set) var syncStatus: String?
    @Published private(set) var availableProducts: [Product] = []

    private var db: Firestore { Firestore.firestore() }
    private var userListener: ListenerRegistration?
    private var linkedUID: String?
    private var updatesTask: Task<Void, Never>?
    private var foregroundCancellable: AnyCancellable?
    private var lastSyncedUID: String?
    private var lastSyncedStateFingerprint: String?

    init() {
        let defaults = UserDefaults.standard
        let storedLifetimePro = defaults.bool(forKey: Self.proKey)
        let storedTier = PBEntitlementTier(rawValue: defaults.string(forKey: Self.entitlementTierKey) ?? "") ?? .free
        let storedCanSwitch = defaults.bool(forKey: Self.canSwitchRoleFreelyKey)
        let storedIsMaster = defaults.bool(forKey: Self.isMasterAccountKey)
        let storedTrialUsed = defaults.bool(forKey: Self.trialUsedKey)
        let storedTrialStart = Self.readDateDefault(key: Self.trialStartedAtKey, defaults: defaults)
        let storedTrialEnd = Self.readDateDefault(key: Self.trialEndsAtKey, defaults: defaults)
        let storedTypeRaw = defaults.string(forKey: Self.accountTypeKey) ?? PBAccountType.student.rawValue
        let storedType = PBAccountType(rawValue: storedTypeRaw) ?? .student
        let storedRolesRaw = defaults.array(forKey: Self.enabledRolesKey) as? [String] ?? []
        var storedRoles = Set(storedRolesRaw.compactMap(PBAccountType.init(rawValue:)))
        if storedRoles.isEmpty {
            storedRoles = [storedType]
        } else if !storedRoles.contains(storedType) {
            storedRoles.insert(storedType)
        }
        let storedTypeSet = defaults.bool(forKey: Self.accountTypeSetKey)
        let storedTypeChangeUsed = defaults.bool(forKey: Self.accountTypeChangeUsedKey)

        hasLifetimePro = storedLifetimePro
        entitlementTier = storedTier
        canSwitchRoleFreely = storedCanSwitch
        isMasterAccount = storedIsMaster
        hasUsedProTrial = storedTrialUsed
        proTrialStartedAt = storedTrialStart
        proTrialEndsAt = storedTrialEnd
        isProTrialActive = false
        isPro = false
        accountType = storedType
        enabledRoles = storedRoles
        hasCompletedInitialRoleSelection = storedTypeSet
        accountTypeChangeUsed = storedTypeChangeUsed
        if storedLifetimePro {
            ownedProductIDs = [Self.proProductID]
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
        guard productID == Self.proProductID else { return }

        do {
            if availableProducts.isEmpty {
                await loadProducts()
            }
            guard let product = availableProducts.first(where: { $0.id == productID }) else {
                syncStatus = "Pro product is not available right now."
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

    func linkToUser(uid: String?) {
        guard linkedUID != uid else { return }
        linkedUID = uid
        userListener?.remove()
        userListener = nil

        guard let uid else { return }
        let ref = db.collection("users").document(uid)

        userListener = ref.addSnapshotListener { [weak self] snapshot, error in
            guard let self else { return }
            Task { @MainActor in
                if let error {
                    self.syncStatus = "Pro sync error: \(error.localizedDescription)"
                    return
                }

                self.applyMasterAccount(self.resolveMasterStatus(for: uid))

                guard let data = snapshot?.data() else {
                    self.applyLaunchProgramPolicy()
                    await self.pushLocalStateToFirestore()
                    return
                }

                let remoteLifetime = (data["hasLifetimePro"] as? Bool) ?? (data["isPro"] as? Bool)
                if let remoteLifetime, remoteLifetime != self.hasLifetimePro {
                    self.applyLifetimeProState(remoteLifetime)
                }

                if let tierRaw = data["entitlementTier"] as? String,
                   let tier = PBEntitlementTier(rawValue: tierRaw),
                   tier != self.entitlementTier {
                    self.applyEntitlementTier(tier)
                }

                let remoteCanSwitch = (data["canSwitchRoleFreely"] as? Bool) ?? false
                if remoteCanSwitch != self.canSwitchRoleFreely {
                    self.applyCanSwitchRoleFreely(remoteCanSwitch)
                }

                let remoteMaster = (data["isMasterAccount"] as? Bool) ?? self.isMasterAccount
                if remoteMaster != self.isMasterAccount {
                    self.applyMasterAccount(remoteMaster)
                }

                let remoteTrialUsed = (data["trialUsed"] as? Bool) ?? self.hasUsedProTrial
                let remoteTrialStart = Self.firestoreDate(data["trialStartedAt"])
                let remoteTrialEnd = Self.firestoreDate(data["trialEndsAt"])
                self.applyTrialState(
                    used: remoteTrialUsed,
                    startedAt: remoteTrialStart ?? self.proTrialStartedAt,
                    endsAt: remoteTrialEnd ?? self.proTrialEndsAt
                )

                if let trialMessage = self.expiredTrialMessageIfNeeded() {
                    self.syncStatus = trialMessage
                }

                if let raw = data["accountType"] as? String,
                   let remoteType = PBAccountType(rawValue: raw),
                   remoteType != self.accountType {
                    self.applyAccountType(remoteType)
                }

                if let rawRoles = data["enabledRoles"] as? [String] {
                    let remoteRoles = Set(rawRoles.compactMap(PBAccountType.init(rawValue:)))
                    if !remoteRoles.isEmpty, remoteRoles != self.enabledRoles {
                        self.applyEnabledRoles(remoteRoles)
                    }
                } else if (data["accountType"] as? String) != nil {
                    self.applyEnabledRoles([self.accountType])
                }

                let remoteTypeSet = (data["accountTypeSet"] as? Bool) ?? ((data["accountType"] as? String) != nil)
                // Never downgrade local completion from true -> false based on remote lag/cache.
                if remoteTypeSet, !self.hasCompletedInitialRoleSelection {
                    self.applyHasCompletedInitialRoleSelection(true)
                }

                let remoteChangeUsed = (data["accountTypeChangeUsed"] as? Bool) ?? false
                if remoteChangeUsed != self.accountTypeChangeUsed {
                    self.applyAccountTypeChangeUsed(remoteChangeUsed)
                }

                self.applyLaunchProgramPolicy()
            }
        }

        Task {
            applyMasterAccount(resolveMasterStatus(for: uid))
            applyLaunchProgramPolicy()
            await pushLocalStateToFirestore()
        }
    }

    func setAccountType(_ newType: PBAccountType) {
        guard newType != accountType else { return }
        if canSwitchRoleFreely {
            if !enabledRoles.contains(newType) {
                var next = enabledRoles
                next.insert(newType)
                applyEnabledRoles(next)
            }
            applyAccountType(newType)
            applyHasCompletedInitialRoleSelection(true)
            syncStatus = "Switched to \(newType.title) mode."
            Task { await pushLocalStateToFirestore() }
            return
        }

        guard enabledRoles.contains(newType) else {
            syncStatus = "Enable \(newType.title) role first."
            return
        }

        if enabledRoles.count > 1 {
            applyAccountType(newType)
            syncStatus = "Switched to \(newType.title) mode."
            Task { await pushLocalStateToFirestore() }
            return
        }

        if !hasCompletedInitialRoleSelection {
            completeInitialAccountSetup(as: newType)
            return
        }

        guard !accountTypeChangeUsed else {
            syncStatus = "Account type can only be changed once."
            return
        }

        applyAccountType(newType)
        applyAccountTypeChangeUsed(true)
        syncStatus = "Account type updated."
        Task { await pushLocalStateToFirestore() }
    }

    func completeInitialAccountSetup(as type: PBAccountType) {
        applyEnabledRoles([type])
        applyAccountType(type)
        applyHasCompletedInitialRoleSelection(true)
        applyAccountTypeChangeUsed(false)
        syncStatus = nil
        Task { await pushLocalStateToFirestore() }
    }

    func hasRole(_ role: PBAccountType) -> Bool {
        enabledRoles.contains(role)
    }

    var availableRoleModes: [PBAccountType] {
        if canSwitchRoleFreely { return PBAccountType.allCases }
        return PBAccountType.allCases.filter { enabledRoles.contains($0) }
    }

    func setRoleEnabled(_ role: PBAccountType, isEnabled: Bool) {
        var next = enabledRoles
        if isEnabled {
            next.insert(role)
        } else {
            guard next.count > 1 else {
                syncStatus = "At least one role must remain enabled."
                return
            }
            next.remove(role)
            if accountType == role, let fallback = next.first {
                applyAccountType(fallback)
            }
        }

        applyEnabledRoles(next)
        applyHasCompletedInitialRoleSelection(true)
        syncStatus = nil
        Task { await pushLocalStateToFirestore() }
    }

    func debugUnlockPro() {
        applyEntitlementTier(.allAccess)
        applyLifetimeProState(true)
        Task {
            await pushLocalStateToFirestore()
        }
    }

    func debugLockPro() {
        applyEntitlementTier(.free)
        applyLifetimeProState(false)
        Task {
            await pushLocalStateToFirestore()
        }
    }

    func startFreeTrial() async {
        guard !entitlementTier.isUnlocked else {
            syncStatus = "Pro is already unlocked."
            return
        }
        guard !hasLifetimePro else {
            syncStatus = "Pro is already unlocked."
            return
        }
        guard !hasUsedProTrial else {
            syncStatus = "Free trial already used."
            return
        }

        let now = Date()
        let end = Calendar.current.date(byAdding: .day, value: Self.proTrialDurationDays, to: now) ?? now
        applyTrialState(used: true, startedAt: now, endsAt: end)
        syncStatus = "7-day free trial started."
        await pushLocalStateToFirestore()
    }

    func loadProducts() async {
        do {
            let products = try await Product.products(for: [Self.proProductID])
            availableProducts = products.sorted(by: { $0.id < $1.id })
        } catch {
            syncStatus = "Could not load products: \(error.localizedDescription)"
        }
    }

    func refreshEntitlements() async {
        var hasProPurchase = false
        for await result in StoreKit.Transaction.currentEntitlements {
            guard case .verified(let transaction) = result else { continue }
            if transaction.productID == Self.proProductID {
                hasProPurchase = true
            }
        }

        applyLifetimeProState(hasProPurchase)
        if hasProPurchase && entitlementTier == .free {
            applyEntitlementTier(.pro)
        }
        await pushLocalStateToFirestore()
    }

    private func applyLifetimeProState(_ value: Bool) {
        guard hasLifetimePro != value else { return }
        hasLifetimePro = value
        if value {
            ownedProductIDs.insert(Self.proProductID)
        } else {
            ownedProductIDs.remove(Self.proProductID)
        }
        UserDefaults.standard.set(value, forKey: Self.proKey)
        recalculateProAccess()
    }

    private func applyEntitlementTier(_ value: PBEntitlementTier) {
        guard entitlementTier != value else { return }
        entitlementTier = value
        UserDefaults.standard.set(value.rawValue, forKey: Self.entitlementTierKey)
        recalculateProAccess()
    }

    private func applyCanSwitchRoleFreely(_ value: Bool) {
        guard canSwitchRoleFreely != value else { return }
        canSwitchRoleFreely = value
        UserDefaults.standard.set(value, forKey: Self.canSwitchRoleFreelyKey)
    }

    private func applyMasterAccount(_ value: Bool) {
        guard isMasterAccount != value else { return }
        isMasterAccount = value
        UserDefaults.standard.set(value, forKey: Self.isMasterAccountKey)
    }

    private func applyTrialState(used: Bool, startedAt: Date?, endsAt: Date?) {
        guard hasUsedProTrial != used || proTrialStartedAt != startedAt || proTrialEndsAt != endsAt else { return }
        hasUsedProTrial = used
        proTrialStartedAt = startedAt
        proTrialEndsAt = endsAt
        let defaults = UserDefaults.standard
        defaults.set(used, forKey: Self.trialUsedKey)
        Self.writeDateDefault(startedAt, key: Self.trialStartedAtKey, defaults: defaults)
        Self.writeDateDefault(endsAt, key: Self.trialEndsAtKey, defaults: defaults)
        recalculateProAccess()
    }

    private func recalculateProAccess(now: Date = Date()) {
        let newTrialActive: Bool
        if let end = proTrialEndsAt {
            newTrialActive = end > now
        } else {
            newTrialActive = false
        }
        let newPro = entitlementTier.isUnlocked || hasLifetimePro || newTrialActive
        if isProTrialActive != newTrialActive { isProTrialActive = newTrialActive }
        if isPro != newPro { isPro = newPro }
    }

    private func expiredTrialMessageIfNeeded(now: Date = Date()) -> String? {
        guard hasUsedProTrial, !hasLifetimePro, !entitlementTier.isUnlocked else { return nil }
        guard let end = proTrialEndsAt, end <= now else { return nil }
        return "Free trial ended. Unlock Practice Buddy Pro to continue."
    }

    private func applyAccountType(_ value: PBAccountType) {
        guard accountType != value else { return }
        accountType = value
        UserDefaults.standard.set(value.rawValue, forKey: Self.accountTypeKey)
    }

    private func applyEnabledRoles(_ roles: Set<PBAccountType>) {
        var safe = roles
        if safe.isEmpty {
            safe = [accountType]
        }
        if !safe.contains(accountType), let fallback = safe.first {
            applyAccountType(fallback)
        }
        guard enabledRoles != safe else { return }
        enabledRoles = safe
        UserDefaults.standard.set(Array(safe.map(\.rawValue)), forKey: Self.enabledRolesKey)
    }

    private func applyHasCompletedInitialRoleSelection(_ value: Bool) {
        guard hasCompletedInitialRoleSelection != value else { return }
        hasCompletedInitialRoleSelection = value
        UserDefaults.standard.set(value, forKey: Self.accountTypeSetKey)
    }

    private func applyAccountTypeChangeUsed(_ value: Bool) {
        guard accountTypeChangeUsed != value else { return }
        accountTypeChangeUsed = value
        UserDefaults.standard.set(value, forKey: Self.accountTypeChangeUsedKey)
    }

    private func pushLocalStateToFirestore() async {
        guard let uid = linkedUID else { return }
        let fingerprint = localStateFingerprint()
        if lastSyncedUID == uid, lastSyncedStateFingerprint == fingerprint {
            return
        }
        do {
            var payload: [String: Any] = [
                "isPro": isPro,
                "hasLifetimePro": hasLifetimePro,
                "entitlementTier": entitlementTier.rawValue,
                "canSwitchRoleFreely": canSwitchRoleFreely,
                "isMasterAccount": isMasterAccount,
                "trialUsed": hasUsedProTrial,
                "accountType": accountType.rawValue,
                "enabledRoles": enabledRoles.map(\.rawValue),
                "accountTypeSet": hasCompletedInitialRoleSelection,
                "accountTypeChangeUsed": accountTypeChangeUsed,
                "updatedAt": FieldValue.serverTimestamp()
            ]
            if hasLifetimePro {
                payload["proSince"] = FieldValue.serverTimestamp()
            }
            if let proTrialStartedAt {
                payload["trialStartedAt"] = Timestamp(date: proTrialStartedAt)
            }
            if let proTrialEndsAt {
                payload["trialEndsAt"] = Timestamp(date: proTrialEndsAt)
            }
            try await db.collection("users").document(uid).setData(payload, merge: true)
            lastSyncedUID = uid
            lastSyncedStateFingerprint = fingerprint
            if syncStatus?.contains("trial ended") != true {
                syncStatus = nil
            }
        } catch {
            syncStatus = "Pro sync failed: \(error.localizedDescription)"
        }
    }

    private func localStateFingerprint() -> String {
        let roles = enabledRoles.map(\.rawValue).sorted().joined(separator: ",")
        let trialStart = proTrialStartedAt?.timeIntervalSince1970 ?? 0
        let trialEnd = proTrialEndsAt?.timeIntervalSince1970 ?? 0
        return [
            isPro ? "1" : "0",
            hasLifetimePro ? "1" : "0",
            entitlementTier.rawValue,
            canSwitchRoleFreely ? "1" : "0",
            isMasterAccount ? "1" : "0",
            hasUsedProTrial ? "1" : "0",
            "\(Int(trialStart))",
            "\(Int(trialEnd))",
            accountType.rawValue,
            roles,
            hasCompletedInitialRoleSelection ? "1" : "0",
            accountTypeChangeUsed ? "1" : "0"
        ].joined(separator: "|")
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
        if transaction.productID == Self.proProductID {
            if entitlementTier == .free {
                applyEntitlementTier(.pro)
            }
            applyLifetimeProState(true)
            await pushLocalStateToFirestore()
        }
    }

    private func resolveMasterStatus(for uid: String) -> Bool {
        let info = Bundle.main.infoDictionary
        let masterUIDs = (info?["PBMasterUIDs"] as? [String]) ?? []
        if masterUIDs.contains(uid) { return true }

        let configuredEmails = (info?["PBMasterEmails"] as? [String])?.map { $0.lowercased() } ?? ["nicaviolin@icloud.com"]
        guard let currentUser = Auth.auth().currentUser else { return false }
        let directEmail = currentUser.email?.lowercased()
        let providerEmails = currentUser.providerData.compactMap { $0.email?.lowercased() }
        let allEmails = Set(([directEmail].compactMap { $0 }) + providerEmails)
        return !allEmails.intersection(configuredEmails).isEmpty
    }

    private func applyLaunchProgramPolicy() {
        if isMasterAccount {
            applyCanSwitchRoleFreely(true)
            applyAccountTypeChangeUsed(false)
            applyHasCompletedInitialRoleSelection(true)
            applyEnabledRoles([.student, .teacher])
            if accountType != .teacher {
                applyAccountType(.teacher)
            }
            if entitlementTier != .allAccess {
                applyEntitlementTier(.allAccess)
            }
            if !hasLifetimePro {
                applyLifetimeProState(true)
            }
            return
        }

        applyCanSwitchRoleFreely(false)
        if !enabledRoles.contains(accountType) || enabledRoles.isEmpty {
            applyEnabledRoles([accountType])
        }
    }

    private static func readDateDefault(key: String, defaults: UserDefaults) -> Date? {
        let value = defaults.double(forKey: key)
        guard value > 0 else { return nil }
        return Date(timeIntervalSince1970: value)
    }

    private static func writeDateDefault(_ value: Date?, key: String, defaults: UserDefaults) {
        if let value {
            defaults.set(value.timeIntervalSince1970, forKey: key)
        } else {
            defaults.removeObject(forKey: key)
        }
    }

    private static func firestoreDate(_ value: Any?) -> Date? {
        if let ts = value as? Timestamp {
            return ts.dateValue()
        }
        if let d = value as? Date {
            return d
        }
        return nil
    }
}
