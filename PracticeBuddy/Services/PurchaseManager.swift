import SwiftUI
import Combine

@MainActor
final class PurchaseManager: ObservableObject {
    @Published private(set) var ownedProductIDs: Set<String> = []

    init() {}

    func owns(productID: String) -> Bool {
        ownedProductIDs.contains(productID)
    }

    func buy(productID: String) async {
        // StoreKit 2 will be implemented later
    }

    func restore() async {
        // StoreKit 2 will be implemented later
    }
}
