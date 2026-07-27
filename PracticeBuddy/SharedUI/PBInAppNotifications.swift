import SwiftUI
import Combine

struct PBInAppNotification: Identifiable, Codable, Equatable {
    enum Kind: String, Codable {
        case duelInvite
        case friendRequest
        case chatMessage
    }

    var id: String
    var kind: Kind
    var title: String
    var message: String
    var createdAt: Date
    var isRead: Bool
    var challengeID: String?
    var threadID: String?
    var friendUID: String?
}

@MainActor
final class PBNotificationStore: ObservableObject {
    static let shared = PBNotificationStore()

    @Published private(set) var items: [PBInAppNotification] = []

    private let key = "pb.notifications.inapp.items"

    var unreadCount: Int {
        items.filter { !$0.isRead }.count
    }

    private init() {
        load()
    }

    func markAllRead() {
        guard items.contains(where: { !$0.isRead }) else { return }
        items = items.map {
            var copy = $0
            copy.isRead = true
            return copy
        }
        save()
    }

    func markRead(id: String) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        guard items[index].isRead == false else { return }
        items[index].isRead = true
        save()
    }

    func remove(id: String) {
        items.removeAll { $0.id == id }
        save()
    }

    func syncDuelInvites(_ invites: [DuelChallenge], cachedNames: [String: String]) {
        let existingInviteIDs = Set(invites.map(\.id))
        let inviteMap = Dictionary(uniqueKeysWithValues: invites.map { ($0.id, $0) })

        items.removeAll { notification in
            notification.kind == .duelInvite && !existingInviteIDs.contains(notification.id)
        }

        for invite in invites {
            if items.contains(where: { $0.id == invite.id && $0.kind == .duelInvite }) {
                continue
            }
            let fromName = cachedNames[invite.createdByUID] ?? invite.createdByUID
            let created = invite.createdAt
            items.append(
                PBInAppNotification(
                    id: invite.id,
                    kind: .duelInvite,
                    title: "Duel Invitation",
                    message: "\(fromName) invited you to duel (\(invite.objective)).",
                    createdAt: created,
                    isRead: false,
                    challengeID: invite.id,
                    threadID: nil,
                    friendUID: invite.createdByUID
                )
            )
        }

        items.sort { lhs, rhs in
            if lhs.createdAt == rhs.createdAt {
                return lhs.id > rhs.id
            }
            return lhs.createdAt > rhs.createdAt
        }

        // Keep store bounded for performance.
        if items.count > 120 {
            items = Array(items.prefix(120))
        }

        if !inviteMap.isEmpty || items.contains(where: { $0.kind != .duelInvite }) {
            save()
        }
    }

    func syncFriendRequests(_ invites: [BuddyInvite]) {
        let pendingIDs = Set(invites.map(\.id))

        items.removeAll { notification in
            notification.kind == .friendRequest && !pendingIDs.contains(notification.id)
        }

        for invite in invites {
            if let index = items.firstIndex(where: { $0.kind == .friendRequest && $0.id == invite.id }) {
                // Keep unread flag as-is; refresh content/timestamp.
                items[index].title = "Friend Request"
                items[index].message = "\(invite.fromDisplayName) sent you a friend request."
                items[index].createdAt = invite.createdAt
                items[index].friendUID = invite.fromUid
                continue
            }
            items.append(
                PBInAppNotification(
                    id: invite.id,
                    kind: .friendRequest,
                    title: "Friend Request",
                    message: "\(invite.fromDisplayName) sent you a friend request.",
                    createdAt: invite.createdAt,
                    isRead: false,
                    challengeID: nil,
                    threadID: nil,
                    friendUID: invite.fromUid
                )
            )
        }

        items.sort(by: { $0.createdAt > $1.createdAt })
        save()
    }

    func syncChatThreads(_ threads: [SocialChatThread]) {
        let unreadThreads = threads.filter { $0.unreadCount > 0 }
        let unreadIDs = Set(unreadThreads.map(\.id))

        items.removeAll { notification in
            notification.kind == .chatMessage && !unreadIDs.contains(notification.id)
        }

        for thread in unreadThreads {
            let createdAt = thread.lastMessageAt > .distantPast ? thread.lastMessageAt : Date()
            let messageText = thread.lastMessageText.isEmpty ? "You received a new message." : thread.lastMessageText

            if let index = items.firstIndex(where: { $0.kind == .chatMessage && $0.id == thread.id }) {
                items[index].title = "New Message"
                items[index].message = "\(thread.title): \(messageText)"
                items[index].createdAt = createdAt
                items[index].threadID = thread.id
                items[index].friendUID = thread.friendUID
                continue
            }

            items.append(
                PBInAppNotification(
                    id: thread.id,
                    kind: .chatMessage,
                    title: "New Message",
                    message: "\(thread.title): \(messageText)",
                    createdAt: createdAt,
                    isRead: false,
                    challengeID: nil,
                    threadID: thread.id,
                    friendUID: thread.friendUID
                )
            )
        }

        items.sort(by: { $0.createdAt > $1.createdAt })
        save()
    }

    private func load() {
        guard
            let data = UserDefaults.standard.data(forKey: key),
            let decoded = try? JSONDecoder().decode([PBInAppNotification].self, from: data)
        else {
            items = []
            return
        }
        items = decoded.sorted(by: { $0.createdAt > $1.createdAt })
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(items) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}
