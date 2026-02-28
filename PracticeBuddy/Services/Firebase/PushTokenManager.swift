import Foundation
import FirebaseAuth
import FirebaseFirestore
import CryptoKit
import UserNotifications
import UIKit

@MainActor
final class PushTokenManager {
    static let shared = PushTokenManager()

    private var db: Firestore { Firestore.firestore() }
    private var pendingToken: String?
    private var lastPersistedTokenByUID: [String: String] = [:]
    private var lastNotificationPrefsFingerprintByUID: [String: String] = [:]

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

    func updateNotificationPreferences(
        duelsEnabled: Bool,
        messagesEnabled: Bool,
        goalsEnabled: Bool,
        friendRequestsEnabled: Bool,
        studioInvitesEnabled: Bool,
        assignmentsEnabled: Bool,
        buddiesEnabled: Bool
    ) async {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        let fingerprint = [
            duelsEnabled ? "1" : "0",
            messagesEnabled ? "1" : "0",
            goalsEnabled ? "1" : "0",
            friendRequestsEnabled ? "1" : "0",
            studioInvitesEnabled ? "1" : "0",
            assignmentsEnabled ? "1" : "0",
            buddiesEnabled ? "1" : "0"
        ].joined(separator: "|")
        if lastNotificationPrefsFingerprintByUID[uid] == fingerprint {
            return
        }
        do {
            try await db.collection("users").document(uid).setData([
                "notificationDuels": duelsEnabled,
                "notificationMessages": messagesEnabled,
                "notificationGoals": goalsEnabled,
                "notificationFriendRequests": friendRequestsEnabled,
                "notificationStudioInvites": studioInvitesEnabled,
                "notificationAssignments": assignmentsEnabled,
                "notificationBuddies": buddiesEnabled,
                "updatedAt": FieldValue.serverTimestamp()
            ], merge: true)
            lastNotificationPrefsFingerprintByUID[uid] = fingerprint
        } catch {
            // no-op for now; UI doesn't need a blocking error here
        }
    }

    func requestSystemNotificationPermissionIfNeeded() async -> Bool {
        let status = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
        switch status {
        case .authorized, .provisional, .ephemeral:
            UIApplication.shared.registerForRemoteNotifications()
            return true
        case .denied:
            return false
        case .notDetermined:
            do {
                let granted = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound])
                if granted {
                    UIApplication.shared.registerForRemoteNotifications()
                }
                return granted
            } catch {
                return false
            }
        @unknown default:
            return false
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
