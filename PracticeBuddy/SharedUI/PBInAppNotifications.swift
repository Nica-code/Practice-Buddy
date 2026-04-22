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

struct PBNotificationsInboxView: View {
    @EnvironmentObject private var duelLeague: DuelLeagueManager
    @Environment(\.pbTheme) private var theme
    @Environment(\.pbTypography) private var type
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss
    @StateObject private var store = PBNotificationStore.shared

    private var palette: PBTheme.Palette { theme.resolvedPalette(for: colorScheme) }

    var body: some View {
        NavigationStack {
            Group {
                if store.items.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "bell.slash")
                            .font(.system(size: 26, weight: .semibold))
                            .foregroundStyle(palette.textSecondary)
                        Text("No notifications yet.")
                            .font(type.body)
                            .foregroundStyle(palette.textSecondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        ForEach(store.items) { notification in
                            notificationRow(notification)
                        }
                        .onDelete { offsets in
                            for index in offsets {
                                store.remove(id: store.items[index].id)
                            }
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                    .background(PBBackdropView(palette: palette))
                }
            }
            .navigationTitle("Notifications")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if !store.items.isEmpty {
                        Button("Mark all read") {
                            store.markAllRead()
                        }
                        .font(type.footnote)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .font(type.button)
                }
            }
        }
        .onAppear {
            store.markAllRead()
        }
    }

    @ViewBuilder
    private func notificationRow(_ notification: PBInAppNotification) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                openNotification(notification)
            } label: {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: iconName(for: notification.kind))
                        .foregroundStyle(palette.accent)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(notification.title)
                            .font(type.body.weight(.semibold))
                            .foregroundStyle(palette.textPrimary)
                        Text(notification.message)
                            .font(type.footnote)
                            .foregroundStyle(palette.textSecondary)
                    }
                    Spacer()
                    Text(notification.createdAt, style: .time)
                        .font(type.footnote)
                        .foregroundStyle(palette.textSecondary)
                }
            }
            .buttonStyle(.plain)

            if notification.kind == .duelInvite,
               let challengeID = notification.challengeID,
               let challenge = duelLeague.incomingInvites.first(where: { $0.id == challengeID }) {
                HStack(spacing: 10) {
                    Button("Accept") {
                        Task {
                            await duelLeague.acceptInvite(challengeID: challenge.id)
                            store.remove(id: notification.id)
                        }
                    }
                    .buttonStyle(PBActionButtonStyle(variant: .primary, palette: palette))

                    Button("Decline") {
                        Task {
                            await duelLeague.declineInvite(challengeID: challenge.id)
                            store.remove(id: notification.id)
                        }
                    }
                    .buttonStyle(PBActionButtonStyle(variant: .secondary, palette: palette))
                }
            }

            if notification.kind == .friendRequest {
                Text("Open Social > Friends to respond.")
                    .font(type.footnote)
                    .foregroundStyle(palette.textSecondary)
            }
        }
        .padding(.vertical, 4)
    }

    private func iconName(for kind: PBInAppNotification.Kind) -> String {
        switch kind {
        case .duelInvite:
            return "bolt.horizontal.circle.fill"
        case .friendRequest:
            return "person.badge.plus"
        case .chatMessage:
            return "bubble.left.and.bubble.right.fill"
        }
    }

    private func openNotification(_ notification: PBInAppNotification) {
        let route: PBNotificationRoute
        switch notification.kind {
        case .duelInvite:
            route = .playDuel(challengeID: notification.challengeID)
        case .friendRequest:
            route = .socialFriendRequests
        case .chatMessage:
            route = .socialChat(friendUID: notification.friendUID, threadID: notification.threadID)
        }
        NotificationCenter.default.post(name: .pbNotificationRouteRequested, object: route)
        store.markRead(id: notification.id)
        dismiss()
    }
}
