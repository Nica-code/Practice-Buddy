import SwiftUI
import Combine
import FirebaseFirestore
import StoreKit

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
final class PurchaseManager: ObservableObject {
    static let proProductID = "practicebuddy.pro.lifetime"
    static let proKey = "pb.pro.isUnlocked"
    static let accountTypeKey = "pb.pro.accountType"
    static let accountTypeSetKey = "pb.pro.accountTypeSet"
    static let accountTypeChangeUsedKey = "pb.pro.accountTypeChangeUsed"

    @Published private(set) var ownedProductIDs: Set<String> = []
    @Published private(set) var isPro: Bool
    @Published private(set) var accountType: PBAccountType
    @Published private(set) var hasCompletedInitialRoleSelection: Bool
    @Published private(set) var accountTypeChangeUsed: Bool
    @Published private(set) var syncStatus: String?
    @Published private(set) var availableProducts: [Product] = []

    private let db = Firestore.firestore()
    private var userListener: ListenerRegistration?
    private var linkedUID: String?
    private var updatesTask: Task<Void, Never>?

    init() {
        let defaults = UserDefaults.standard
        let storedPro = defaults.bool(forKey: Self.proKey)
        let storedTypeRaw = defaults.string(forKey: Self.accountTypeKey) ?? PBAccountType.student.rawValue
        let storedType = PBAccountType(rawValue: storedTypeRaw) ?? .student
        let storedTypeSet = defaults.bool(forKey: Self.accountTypeSetKey)
        let storedTypeChangeUsed = defaults.bool(forKey: Self.accountTypeChangeUsedKey)

        isPro = storedPro
        accountType = storedType
        hasCompletedInitialRoleSelection = storedTypeSet
        accountTypeChangeUsed = storedTypeChangeUsed
        if storedPro {
            ownedProductIDs = [Self.proProductID]
        }

        updatesTask = observeTransactionUpdates()
        Task {
            await loadProducts()
            await refreshEntitlements()
        }
    }

    deinit {
        userListener?.remove()
        updatesTask?.cancel()
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

                if let remotePro = data["isPro"] as? Bool, remotePro != self.isPro {
                    self.applyProState(remotePro)
                }
                if let raw = data["accountType"] as? String,
                   let remoteType = PBAccountType(rawValue: raw),
                   remoteType != self.accountType {
                    self.applyAccountType(remoteType)
                }

                let remoteTypeSet = (data["accountTypeSet"] as? Bool) ?? ((data["accountType"] as? String) != nil)
                if remoteTypeSet != self.hasCompletedInitialRoleSelection {
                    self.applyHasCompletedInitialRoleSelection(remoteTypeSet)
                }

                let remoteChangeUsed = (data["accountTypeChangeUsed"] as? Bool) ?? false
                if remoteChangeUsed != self.accountTypeChangeUsed {
                    self.applyAccountTypeChangeUsed(remoteChangeUsed)
                }
            }
        }

        Task {
            await pushLocalStateToFirestore()
        }
    }

    func setAccountType(_ newType: PBAccountType) {
        guard newType != accountType else { return }

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
        applyAccountType(type)
        applyHasCompletedInitialRoleSelection(true)
        applyAccountTypeChangeUsed(false)
        syncStatus = nil
        Task { await pushLocalStateToFirestore() }
    }

    func debugUnlockPro() {
        applyProState(true)
        Task {
            await pushLocalStateToFirestore()
        }
    }

    func debugLockPro() {
        applyProState(false)
        Task {
            await pushLocalStateToFirestore()
        }
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
        var hasPro = false
        for await result in StoreKit.Transaction.currentEntitlements {
            guard case .verified(let transaction) = result else { continue }
            if transaction.productID == Self.proProductID {
                hasPro = true
            }
        }

        applyProState(hasPro)
        await pushLocalStateToFirestore()
    }

    private func applyProState(_ value: Bool) {
        isPro = value
        if value {
            ownedProductIDs.insert(Self.proProductID)
        } else {
            ownedProductIDs.remove(Self.proProductID)
        }
        UserDefaults.standard.set(value, forKey: Self.proKey)
    }

    private func applyAccountType(_ value: PBAccountType) {
        accountType = value
        UserDefaults.standard.set(value.rawValue, forKey: Self.accountTypeKey)
    }

    private func applyHasCompletedInitialRoleSelection(_ value: Bool) {
        hasCompletedInitialRoleSelection = value
        UserDefaults.standard.set(value, forKey: Self.accountTypeSetKey)
    }

    private func applyAccountTypeChangeUsed(_ value: Bool) {
        accountTypeChangeUsed = value
        UserDefaults.standard.set(value, forKey: Self.accountTypeChangeUsedKey)
    }

    private func pushLocalStateToFirestore() async {
        guard let uid = linkedUID else { return }
        do {
            var payload: [String: Any] = [
                "isPro": isPro,
                "accountType": accountType.rawValue,
                "accountTypeSet": hasCompletedInitialRoleSelection,
                "accountTypeChangeUsed": accountTypeChangeUsed,
                "updatedAt": FieldValue.serverTimestamp()
            ]
            if isPro {
                payload["proSince"] = FieldValue.serverTimestamp()
            }
            try await db.collection("users").document(uid).setData(payload, merge: true)
            syncStatus = nil
        } catch {
            syncStatus = "Pro sync failed: \(error.localizedDescription)"
        }
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
            applyProState(true)
            await pushLocalStateToFirestore()
        }
    }
}
