import Foundation
import os
import FirebaseAuth
import FirebaseFirestore
import CryptoKit
import UserNotifications
import UIKit
#if canImport(FirebaseMessaging)
import FirebaseMessaging
#endif

@MainActor
final class PushTokenManager {
    enum TokenKind: String {
        case apns
        case fcm
    }

    static let shared = PushTokenManager()

    private var db: Firestore { Firestore.firestore() }
    private let urlSession = URLSession.shared
    private var pendingToken: (value: String, kind: TokenKind)?
    private var lastPersistedTokenByUIDAndKind: [String: String] = [:]
    private var lastNotificationPrefsFingerprintByUID: [String: String] = [:]

    private init() {}

    func upsertCurrentToken(_ token: String, kind: TokenKind = .apns) async {
        pendingToken = (token, kind)
        guard let uid = Auth.auth().currentUser?.uid else { return }
        await persistToken(token, for: uid, kind: kind)
    }

    func syncPendingTokenIfPossible() async {
        guard let pendingToken, let uid = Auth.auth().currentUser?.uid else { return }
        await persistToken(pendingToken.value, for: uid, kind: pendingToken.kind)
        await syncFCMRegistrationTokenIfPossible()
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
            PBLog.firebase.info("Updated notification prefs for uid=\(uid, privacy: .private)")
        } catch {
            PBLog.firebase.error("Failed to update notification prefs: \(error.localizedDescription, privacy: .public)")
        }
    }

    func updateServerBadgeCount(_ count: Int) async {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        do {
            try await db.collection("users").document(uid).setData([
                "notificationBadgeCount": max(0, min(count, 99)),
                "notificationBadgeUpdatedAt": FieldValue.serverTimestamp()
            ], merge: true)
        } catch {
            PBLog.firebase.error("Failed to update server notification badge count: \(error.localizedDescription, privacy: .public)")
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

    func registerForRemoteNotificationsIfAuthorized() async {
        let status = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
        switch status {
        case .authorized, .provisional, .ephemeral:
            UIApplication.shared.registerForRemoteNotifications()
            PBLog.firebase.info("Registered for remote notifications (already authorized)")
            await syncFCMRegistrationTokenIfPossible()
        default:
            break
        }
    }

    func syncFCMRegistrationTokenIfPossible() async {
#if canImport(FirebaseMessaging)
        guard Auth.auth().currentUser?.uid != nil else { return }
        do {
            let token: String? = try await withCheckedThrowingContinuation { continuation in
                Messaging.messaging().token { token, error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume(returning: token)
                    }
                }
            }
            guard let token, !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                PBLog.firebase.error("FCM registration token fetch returned empty token")
                return
            }
            await upsertCurrentToken(token, kind: .fcm)
        } catch {
            PBLog.firebase.error("Failed to fetch FCM registration token: \(error.localizedDescription, privacy: .public)")
        }
#endif
    }

    func sendTestPushNotification(route: String = "social_chat") async throws {
        guard let baseURL = AppInfo.duelFunctionsBaseURL else {
            throw NSError(
                domain: "PracticeBuddy.Push",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Cloud Functions URL is missing."]
            )
        }
        guard let user = Auth.auth().currentUser else {
            throw NSError(
                domain: "PracticeBuddy.Push",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "No authenticated Firebase user."]
            )
        }

        let token = try await user.getIDToken()
        let endpoint = baseURL.appendingPathComponent("pushTestNotification")
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["route": route], options: [])

        let (data, response) = try await urlSession.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw NSError(
                domain: "PracticeBuddy.Push",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Invalid push test response."]
            )
        }
        let json = (try? JSONSerialization.jsonObject(with: data, options: [])) as? [String: Any]
        guard (200..<300).contains(http.statusCode), (json?["ok"] as? Bool) == true else {
            let message = (json?["error"] as? String) ?? "Push test failed (\(http.statusCode))."
            throw NSError(
                domain: "PracticeBuddy.Push",
                code: http.statusCode,
                userInfo: [NSLocalizedDescriptionKey: message]
            )
        }
        PBLog.firebase.info("Push test notification request succeeded route=\(route, privacy: .public)")
    }

    private func persistToken(_ token: String, for uid: String, kind: TokenKind) async {
        let cacheKey = "\(uid)|\(kind.rawValue)"
        if lastPersistedTokenByUIDAndKind[cacheKey] == token {
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
                    "tokenType": kind.rawValue,
                    "platform": "ios",
                    "updatedAt": FieldValue.serverTimestamp()
                ], merge: true)
            lastPersistedTokenByUIDAndKind[cacheKey] = token
            PBLog.firebase.info("Stored \(kind.rawValue, privacy: .public) push token for uid=\(uid, privacy: .private)")
        } catch {
            PBLog.firebase.error("Failed to store \(kind.rawValue, privacy: .public) push token: \(error.localizedDescription, privacy: .public)")
        }
    }

    private static func tokenDocumentID(for token: String) -> String {
        let digest = SHA256.hash(data: Data(token.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
