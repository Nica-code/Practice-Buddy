import SwiftUI
import Combine
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
enum PBPrimaryFocus: String, CaseIterable, Identifiable {
    case student
    case teacher
    case both

    var id: String { rawValue }

    var title: String {
        switch self {
        case .student: return "Student"
        case .teacher: return "Teacher"
        case .both: return "Both"
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
    static let primaryFocusKey = "pb.tools.primaryFocus"
    static let showStudentToolsKey = "pb.tools.visibility.student"
    static let showTeacherToolsKey = "pb.tools.visibility.teacher"
    static let entitlementTierKey = "pb.pro.entitlementTier"
    static let trialUsedKey = "pb.pro.trialUsed"
    static let trialStartedAtKey = "pb.pro.trialStartedAt"
    static let trialEndsAtKey = "pb.pro.trialEndsAt"

    @Published private(set) var ownedProductIDs: Set<String> = []
    @Published private(set) var isPro: Bool
    @Published private(set) var hasLifetimePro: Bool
    @Published private(set) var entitlementTier: PBEntitlementTier
    @Published private(set) var isProTrialActive: Bool
    @Published private(set) var hasUsedProTrial: Bool
    @Published private(set) var proTrialStartedAt: Date?
    @Published private(set) var proTrialEndsAt: Date?
    @Published private(set) var accountType: PBAccountType
    @Published private(set) var primaryFocus: PBPrimaryFocus
    @Published private(set) var showStudentTools: Bool
    @Published private(set) var showTeacherTools: Bool
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
        let storedTrialUsed = defaults.bool(forKey: Self.trialUsedKey)
        let storedTrialStart = Self.readDateDefault(key: Self.trialStartedAtKey, defaults: defaults)
        let storedTrialEnd = Self.readDateDefault(key: Self.trialEndsAtKey, defaults: defaults)
        let storedTypeRaw = defaults.string(forKey: Self.accountTypeKey) ?? PBAccountType.student.rawValue
        let storedType = PBAccountType(rawValue: storedTypeRaw) ?? .student
        let storedPrimaryFocus: PBPrimaryFocus = {
            guard let raw = defaults.string(forKey: Self.primaryFocusKey),
                  let value = PBPrimaryFocus(rawValue: raw) else {
                return storedType == .teacher ? .teacher : .student
            }
            return value
        }()
        let derivedVisibility = Self.defaultVisibility(for: storedPrimaryFocus)
        let storedShowStudentTools: Bool = {
            if defaults.object(forKey: Self.showStudentToolsKey) == nil { return derivedVisibility.student }
            return defaults.bool(forKey: Self.showStudentToolsKey)
        }()
        let storedShowTeacherTools: Bool = {
            if defaults.object(forKey: Self.showTeacherToolsKey) == nil { return derivedVisibility.teacher }
            return defaults.bool(forKey: Self.showTeacherToolsKey)
        }()
        let normalizedVisibility = Self.normalizedVisibility(
            student: storedShowStudentTools,
            teacher: storedShowTeacherTools,
            fallback: derivedVisibility
        )

        hasLifetimePro = storedLifetimePro
        entitlementTier = storedTier
        hasUsedProTrial = storedTrialUsed
        proTrialStartedAt = storedTrialStart
        proTrialEndsAt = storedTrialEnd
        isProTrialActive = false
        isPro = false
        accountType = storedType
        primaryFocus = storedPrimaryFocus
        showStudentTools = normalizedVisibility.student
        showTeacherTools = normalizedVisibility.teacher
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

                guard let data = snapshot?.data() else {
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

                if let raw = data["primaryFocus"] as? String,
                   let remoteFocus = PBPrimaryFocus(rawValue: raw),
                   remoteFocus != self.primaryFocus {
                    self.applyPrimaryFocus(remoteFocus, syncLegacyAccountType: false)
                }

                if let remoteShowStudent = data["showStudentTools"] as? Bool,
                   let remoteShowTeacher = data["showTeacherTools"] as? Bool {
                    self.applyToolVisibility(showStudent: remoteShowStudent, showTeacher: remoteShowTeacher)
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

    func hasRole(_ role: PBAccountType) -> Bool {
        switch role {
        case .student: return showStudentTools
        case .teacher: return showTeacherTools
        }
    }

    var availableRoleModes: [PBAccountType] {
        PBAccountType.allCases
    }

    var canAccessStudentTools: Bool { showStudentTools }
    var canAccessTeacherTools: Bool { showTeacherTools }

    func setRoleEnabled(_ role: PBAccountType, isEnabled: Bool) {
        switch role {
        case .student:
            setShowStudentTools(isEnabled)
        case .teacher:
            setShowTeacherTools(isEnabled)
        }
    }

    func setPrimaryFocus(_ newFocus: PBPrimaryFocus) {
        guard primaryFocus != newFocus else { return }
        applyPrimaryFocus(newFocus, syncLegacyAccountType: true)
        syncStatus = nil
        Task { await pushLocalStateToFirestore() }
    }

    func setShowStudentTools(_ enabled: Bool) {
        applyToolVisibility(showStudent: enabled, showTeacher: showTeacherTools)
        syncStatus = nil
        Task { await pushLocalStateToFirestore() }
    }

    func setShowTeacherTools(_ enabled: Bool) {
        applyToolVisibility(showStudent: showStudentTools, showTeacher: enabled)
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

    private func applyPrimaryFocus(_ value: PBPrimaryFocus, syncLegacyAccountType: Bool) {
        guard primaryFocus != value else { return }
        primaryFocus = value
        UserDefaults.standard.set(value.rawValue, forKey: Self.primaryFocusKey)

        if syncLegacyAccountType {
            switch value {
            case .student:
                applyAccountType(.student)
            case .teacher:
                applyAccountType(.teacher)
            case .both:
                break
            }
        }

        let defaults = Self.defaultVisibility(for: value)
        applyToolVisibility(showStudent: defaults.student, showTeacher: defaults.teacher)
    }

    private func applyToolVisibility(showStudent: Bool, showTeacher: Bool) {
        let fallback = Self.defaultVisibility(for: primaryFocus)
        let normalized = Self.normalizedVisibility(
            student: showStudent,
            teacher: showTeacher,
            fallback: fallback
        )
        if showStudentTools != normalized.student {
            showStudentTools = normalized.student
            UserDefaults.standard.set(normalized.student, forKey: Self.showStudentToolsKey)
        }
        if showTeacherTools != normalized.teacher {
            showTeacherTools = normalized.teacher
            UserDefaults.standard.set(normalized.teacher, forKey: Self.showTeacherToolsKey)
        }
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
                "trialUsed": hasUsedProTrial,
                "accountType": accountType.rawValue,
                "primaryFocus": primaryFocus.rawValue,
                "showStudentTools": showStudentTools,
                "showTeacherTools": showTeacherTools,
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
        let trialStart = proTrialStartedAt?.timeIntervalSince1970 ?? 0
        let trialEnd = proTrialEndsAt?.timeIntervalSince1970 ?? 0
        return [
            isPro ? "1" : "0",
            hasLifetimePro ? "1" : "0",
            entitlementTier.rawValue,
            hasUsedProTrial ? "1" : "0",
            "\(Int(trialStart))",
            "\(Int(trialEnd))",
            accountType.rawValue,
            primaryFocus.rawValue,
            showStudentTools ? "1" : "0",
            showTeacherTools ? "1" : "0"
        ].joined(separator: "|")
    }

    private static func defaultVisibility(for focus: PBPrimaryFocus) -> (student: Bool, teacher: Bool) {
        switch focus {
        case .student: return (true, false)
        case .teacher: return (false, true)
        case .both: return (true, true)
        }
    }

    private static func normalizedVisibility(
        student: Bool,
        teacher: Bool,
        fallback: (student: Bool, teacher: Bool)
    ) -> (student: Bool, teacher: Bool) {
        if student || teacher {
            return (student, teacher)
        }
        return fallback
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
