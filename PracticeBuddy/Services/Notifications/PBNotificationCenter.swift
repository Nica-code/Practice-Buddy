import Foundation
import UserNotifications
import UIKit

enum PBNotificationPreferenceKey {
    static let duels = "pb.notifications.duels"
    static let messages = "pb.notifications.messages"
    static let goals = "pb.notifications.goals"
    static let friendRequests = "pb.notifications.friendRequests"
    static let buddies = "pb.notifications.buddies"
}

enum PBNotificationCategoryID {
    static let duel = "pb.duel"
    static let message = "pb.message"
    static let goal = "pb.goal"
    static let friendRequest = "pb.friend_request"
}

enum PBNotificationPayloadKey {
    static let route = "pb_route"
    static let type = "pb_type"
    static let challengeID = "challengeId"
    static let threadID = "threadId"
    static let friendUID = "friendUid"
    static let momentID = "momentId"
    static let profileUID = "profileUid"
}

enum PBNotificationRoute: Equatable {
    case playDuel(challengeID: String?)
    case socialFriendRequests
    case socialChat(friendUID: String?, threadID: String?)
    case homeGoals
    case practiceMoment(momentID: String)
    case publicProfile(userID: String)
}

extension Notification.Name {
    static let pbNotificationRouteRequested = Notification.Name("pb.notification.route.requested")
}

@MainActor
enum PBNotificationCenter {
    private static var pendingRoute: PBNotificationRoute?

    static func registerCategories() {
        let categories: Set<UNNotificationCategory> = [
            UNNotificationCategory(
                identifier: PBNotificationCategoryID.duel,
                actions: [],
                intentIdentifiers: [],
                options: [.customDismissAction]
            ),
            UNNotificationCategory(
                identifier: PBNotificationCategoryID.message,
                actions: [],
                intentIdentifiers: [],
                options: [.customDismissAction]
            ),
            UNNotificationCategory(
                identifier: PBNotificationCategoryID.goal,
                actions: [],
                intentIdentifiers: [],
                options: [.customDismissAction]
            ),
            UNNotificationCategory(
                identifier: PBNotificationCategoryID.friendRequest,
                actions: [],
                intentIdentifiers: [],
                options: [.customDismissAction]
            ),
        ]
        UNUserNotificationCenter.current().setNotificationCategories(categories)
    }

    static func authorizationStatus() async -> UNAuthorizationStatus {
        await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    static func requestAuthorizationIfNeeded() async -> Bool {
        let center = UNUserNotificationCenter.current()
        let status = await center.notificationSettings().authorizationStatus
        switch status {
        case .authorized, .provisional, .ephemeral:
            UIApplication.shared.registerForRemoteNotifications()
            return true
        case .denied:
            return false
        case .notDetermined:
            do {
                let granted = try await center.requestAuthorization(options: [.alert, .badge, .sound])
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

    static func openSystemNotificationSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    static func maybeScheduleGoalReachedNotification(eventKey: String) {
        guard UserDefaults.standard.object(forKey: PBNotificationPreferenceKey.goals) as? Bool ?? true else {
            return
        }
        Task {
            let status = await authorizationStatus()
            guard status == .authorized || status == .provisional || status == .ephemeral else { return }

            let content = UNMutableNotificationContent()
            content.title = "Goal Reached"
            content.body = "Great work. You reached your practice goal."
            content.sound = .default
            content.categoryIdentifier = PBNotificationCategoryID.goal
            content.userInfo = [
                PBNotificationPayloadKey.route: "home_goal",
                "pb_event_key": eventKey
            ]

            let request = UNNotificationRequest(
                identifier: "pb.goal.\(eventKey)",
                content: content,
                trigger: nil
            )
            try? await UNUserNotificationCenter.current().add(request)
        }
    }

    static func maybeScheduleDuelNotification(title: String, body: String, challengeID: String?) {
        guard UserDefaults.standard.object(forKey: PBNotificationPreferenceKey.duels) as? Bool ?? true else {
            return
        }
        Task {
            guard await canPresentLocalNotifications() else { return }
            var userInfo: [AnyHashable: Any] = [
                PBNotificationPayloadKey.route: "play_duel",
                PBNotificationPayloadKey.type: "duel"
            ]
            if let challengeID, !challengeID.isEmpty {
                userInfo[PBNotificationPayloadKey.challengeID] = challengeID
            }
            await enqueueLocalNotification(
                identifier: "pb.duel.\(challengeID ?? UUID().uuidString)",
                title: title,
                body: body,
                category: PBNotificationCategoryID.duel,
                userInfo: userInfo
            )
        }
    }

    static func maybeScheduleFriendRequestNotification(fromDisplayName: String, friendUID: String?) {
        guard UserDefaults.standard.object(forKey: PBNotificationPreferenceKey.friendRequests) as? Bool ?? true else {
            return
        }
        Task {
            guard await canPresentLocalNotifications() else { return }
            var userInfo: [AnyHashable: Any] = [
                PBNotificationPayloadKey.route: "social_friend_requests",
                PBNotificationPayloadKey.type: "friend_request"
            ]
            if let friendUID, !friendUID.isEmpty {
                userInfo[PBNotificationPayloadKey.friendUID] = friendUID
            }
            await enqueueLocalNotification(
                identifier: "pb.friend_request.\(friendUID ?? UUID().uuidString)",
                title: "New Friend Request",
                body: "\(fromDisplayName) sent you a request.",
                category: PBNotificationCategoryID.friendRequest,
                userInfo: userInfo
            )
        }
    }

    static func maybeScheduleChatNotification(title: String, body: String, threadID: String?, friendUID: String?) {
        guard UserDefaults.standard.object(forKey: PBNotificationPreferenceKey.messages) as? Bool ?? true else {
            return
        }
        Task {
            guard await canPresentLocalNotifications() else { return }
            var userInfo: [AnyHashable: Any] = [
                PBNotificationPayloadKey.route: "social_chat",
                PBNotificationPayloadKey.type: "chat_message"
            ]
            if let threadID, !threadID.isEmpty {
                userInfo[PBNotificationPayloadKey.threadID] = threadID
            }
            if let friendUID, !friendUID.isEmpty {
                userInfo[PBNotificationPayloadKey.friendUID] = friendUID
            }
            await enqueueLocalNotification(
                identifier: "pb.chat.\(threadID ?? UUID().uuidString)",
                title: "New Message",
                body: "You received a new message.",
                category: PBNotificationCategoryID.message,
                userInfo: userInfo
            )
        }
    }

    static func route(for response: UNNotificationResponse) -> PBNotificationRoute? {
        route(
            categoryIdentifier: response.notification.request.content.categoryIdentifier,
            userInfo: response.notification.request.content.userInfo
        )
    }

    static func route(categoryIdentifier: String, userInfo: [AnyHashable: Any]) -> PBNotificationRoute? {
        let explicit = (userInfo["pb_route"] as? String ?? "").lowercased()
        let challengeID = stringValue(in: userInfo, keys: ["challengeId", "challengeID", "duelId", "duelID"])
        let threadID = stringValue(in: userInfo, keys: ["threadId", "threadID", "chatThreadId", "chatThreadID"])
        let friendUID = stringValue(in: userInfo, keys: ["friendUid", "friendUID", "fromUid", "senderUid", "userUid"])
        let momentID = stringValue(in: userInfo, keys: ["momentId", "momentID"])
        let profileUID = stringValue(in: userInfo, keys: ["profileUid", "profileUID", "userUid"])
        switch explicit {
        case "play_duel": return .playDuel(challengeID: challengeID)
        case "social_friend_requests": return .socialFriendRequests
        case "home_goal": return .homeGoals
        case "social_chat":
            return .socialChat(friendUID: friendUID, threadID: threadID)
        case "practice_moment":
            return momentID.map(PBNotificationRoute.practiceMoment)
        case "public_profile":
            return profileUID.map(PBNotificationRoute.publicProfile)
        default:
            break
        }

        let rawType = (
            userInfo["pb_type"] as? String
            ?? userInfo["type"] as? String
            ?? userInfo["kind"] as? String
            ?? categoryIdentifier
        ).lowercased()

        if rawType.contains("duel") {
            return .playDuel(challengeID: challengeID)
        }
        if rawType.contains("friend") && rawType.contains("request") {
            return .socialFriendRequests
        }
        if rawType.contains("goal") {
            return .homeGoals
        }
        if rawType.contains("message") || rawType.contains("chat") {
            return .socialChat(friendUID: friendUID, threadID: threadID)
        }
        if rawType.contains("moment"), let momentID {
            return .practiceMoment(momentID: momentID)
        }
        if rawType.contains("profile"), let profileUID {
            return .publicProfile(userID: profileUID)
        }
        return nil
    }

    private static func stringValue(in userInfo: [AnyHashable: Any], keys: [String]) -> String? {
        for key in keys {
            if let value = userInfo[key] as? String {
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    return trimmed
                }
            }
        }
        return nil
    }

    private static func canPresentLocalNotifications() async -> Bool {
        let status = await authorizationStatus()
        return status == .authorized || status == .provisional || status == .ephemeral
    }

    private static func enqueueLocalNotification(
        identifier: String,
        title: String,
        body: String,
        category: String,
        userInfo: [AnyHashable: Any]
    ) async {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.categoryIdentifier = category
        content.userInfo = userInfo
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: nil)
        try? await UNUserNotificationCenter.current().add(request)
    }

    static func cachePendingRoute(_ route: PBNotificationRoute) {
        pendingRoute = route
    }

    static func consumePendingRoute() -> PBNotificationRoute? {
        defer { pendingRoute = nil }
        return pendingRoute
    }
}
