import Foundation
import FirebaseAuth
import FirebaseFirestore
import CryptoKit

@MainActor
final class PushTokenManager {
    static let shared = PushTokenManager()

    private var db: Firestore { Firestore.firestore() }
    private var pendingToken: String?
    private var lastPersistedTokenByUID: [String: String] = [:]
    private var lastNotificationPrefsByUID: [String: (assignments: Bool, buddies: Bool)] = [:]

    private init() {}

    func upsertCurrentToken(_ token: String) async {
        pendingToken = token
        guard let uid = Auth.auth().currentUser?.uid else { return }
        await persistToken(token, for: uid)
    }

    func syncPendingTokenIfPossible() async {
        guard let token = pendingToken, let uid = Auth.auth().currentUser?.uid else { return }
        await persistToken(token, for: uid)
    }

    func updateNotificationPreferences(assignmentsEnabled: Bool, buddiesEnabled: Bool) async {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        if let cached = lastNotificationPrefsByUID[uid],
           cached.assignments == assignmentsEnabled,
           cached.buddies == buddiesEnabled {
            return
        }
        do {
            try await db.collection("users").document(uid).setData([
                "notificationAssignments": assignmentsEnabled,
                "notificationBuddies": buddiesEnabled,
                "updatedAt": FieldValue.serverTimestamp()
            ], merge: true)
            lastNotificationPrefsByUID[uid] = (assignmentsEnabled, buddiesEnabled)
        } catch {
            // no-op for now; UI doesn't need a blocking error here
        }
    }

    private func persistToken(_ token: String, for uid: String) async {
        if lastPersistedTokenByUID[uid] == token {
            return
        }
        let tokenID = Self.tokenDocumentID(for: token)
        do {
            try await db.collection("users")
                .document(uid)
                .collection("devices")
                .document(tokenID)
                .setData([
                    "token": token,
                    "platform": "ios",
                    "updatedAt": FieldValue.serverTimestamp()
                ], merge: true)
            lastPersistedTokenByUID[uid] = token
        } catch {
            // no-op for now
        }
    }

    private static func tokenDocumentID(for token: String) -> String {
        let digest = SHA256.hash(data: Data(token.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
