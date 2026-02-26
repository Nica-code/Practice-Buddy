import Foundation
import Combine
import FirebaseFirestore

enum BuddyRelationshipState: Equatable {
    case me
    case friends
    case incoming(BuddyInvite)
    case outgoing(BuddyInvite)
    case notFriends
}

struct StudioLeaderboardRow: Identifiable, Equatable {
    let id: String
    let name: String
    let minutes: Int
    let isMe: Bool
    let avatarID: String
    let publicLevel: Int
}

@MainActor
final class BuddiesViewModel: ObservableObject {
    @Published private(set) var myProfile: FirebaseUserProfile?
    @Published private(set) var incomingInvites: [BuddyInvite] = []
    @Published private(set) var outgoingInvites: [BuddyInvite] = []
    @Published private(set) var buddies: [BuddySummary] = []
    @Published private(set) var leaderboardRows: [StudioLeaderboardRow] = []
    @Published private(set) var isLoading = false
    @Published var statusMessage: String?

    private let repository: FirebaseBuddiesRepository
    private var listeners: [ListenerRegistration] = []
    private var configuredUID: String?
    private var lastSyncedPracticeMinutes: Int?
    private var lastSyncedPublicLevel: Int?
    private var lastLeaderboardKey: String?
    private var lastLeaderboardRefreshAt: Date?
    private let leaderboardRefreshCooldown: TimeInterval = 15

    init(repository: FirebaseBuddiesRepository? = nil) {
        self.repository = repository ?? FirebaseBuddiesRepository()
    }

    convenience init() {
        self.init(repository: nil)
    }

    deinit {
        listeners.forEach { $0.remove() }
    }

    func start(for uid: String) async {
        if configuredUID == uid { return }

        stop()
        configuredUID = uid
        isLoading = true
        statusMessage = nil

        do {
            myProfile = try await repository.ensureCurrentUserProfile()
            attachListeners(uid: uid)
        } catch {
            statusMessage = error.localizedDescription
        }

        isLoading = false
    }

    func stop() {
        listeners.forEach { $0.remove() }
        listeners = []
        configuredUID = nil
        myProfile = nil
        incomingInvites = []
        outgoingInvites = []
        buddies = []
        leaderboardRows = []
        lastSyncedPracticeMinutes = nil
        lastSyncedPublicLevel = nil
        lastLeaderboardKey = nil
        lastLeaderboardRefreshAt = nil
    }

    func sendInvite(friendCode: String) async -> String? {
        guard let myProfile else {
            statusMessage = "Profile is not ready yet."
            return nil
        }

        do {
            let newBuddyUID = try await repository.sendInvite(from: myProfile, friendCode: friendCode)
            statusMessage = "Friend request sent."
            return newBuddyUID
        } catch {
            statusMessage = error.localizedDescription
            return nil
        }
    }

    func sendInvite(to targetUID: String) async {
        guard let myProfile else {
            statusMessage = "Profile is not ready yet."
            return
        }

        do {
            try await repository.sendInvite(from: myProfile, to: targetUID)
            statusMessage = "Friend request sent."
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func loadUserProfile(uid: String) async -> FirebaseUserProfile? {
        do {
            return try await repository.fetchUserProfile(uid: uid)
        } catch {
            statusMessage = error.localizedDescription
            return nil
        }
    }

    func relationshipState(with targetUID: String) -> BuddyRelationshipState {
        guard let myUID = configuredUID else { return .notFriends }
        if myUID == targetUID { return .me }

        if buddies.contains(where: { $0.id == targetUID }) {
            return .friends
        }
        if let incoming = incomingInvites.first(where: { $0.fromUid == targetUID && $0.toUid == myUID }) {
            return .incoming(incoming)
        }
        if let outgoing = outgoingInvites.first(where: { $0.toUid == targetUID && $0.fromUid == myUID }) {
            return .outgoing(outgoing)
        }
        return .notFriends
    }

    func saveDisplayName(_ rawName: String) async {
        guard let uid = configuredUID else { return }

        do {
            try await repository.updateDisplayName(uid: uid, rawDisplayName: rawName)
            statusMessage = "Name updated."
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func updateProfile(avatarID: String, bio: String, instrument: String) async {
        guard let uid = configuredUID else { return }
        do {
            try await repository.updateProfileDetails(
                uid: uid,
                avatarID: avatarID,
                rawBio: bio,
                rawInstrument: instrument
            )
            statusMessage = "Profile updated."
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func syncPublicLevel(_ level: Int) async {
        guard let uid = configuredUID else { return }
        if lastSyncedPublicLevel == level { return }
        do {
            try await repository.updatePublicLevel(uid: uid, level: level)
            lastSyncedPublicLevel = level
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func acceptInvite(_ invite: BuddyInvite) async {
        guard let uid = configuredUID else { return }
        do {
            try await repository.acceptInvite(invite, myUID: uid)
            statusMessage = "Invite accepted."
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func declineInvite(_ invite: BuddyInvite) async {
        do {
            try await repository.declineInvite(invite)
            statusMessage = "Invite declined."
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func removeBuddy(_ buddy: BuddySummary) async {
        guard let uid = configuredUID else { return }
        do {
            try await repository.removeBuddy(myUID: uid, buddyUID: buddy.id)
            statusMessage = "Buddy removed."
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func syncPracticeTotal(minutes: Int) async {
        guard let uid = configuredUID else { return }
        let safeMinutes = max(0, minutes)
        if lastSyncedPracticeMinutes == safeMinutes { return }
        do {
            try await repository.updatePracticeTotalMinutes(uid: uid, minutes: safeMinutes)
            lastSyncedPracticeMinutes = safeMinutes
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func refreshLeaderboard(myTotalMinutes: Int, force: Bool = false) async {
        guard let profile = myProfile else { return }
        let buddyIDs = buddies.map(\.id)
        let key = [profile.uid, "\(max(0, myTotalMinutes))", buddyIDs.sorted().joined(separator: ",")].joined(separator: "|")
        if !force,
           lastLeaderboardKey == key,
           let lastLeaderboardRefreshAt,
           Date().timeIntervalSince(lastLeaderboardRefreshAt) < leaderboardRefreshCooldown {
            return
        }

        do {
            let totals = try await repository.fetchPracticeMinutes(forUIDs: [profile.uid] + buddyIDs)
            var rows: [StudioLeaderboardRow] = [
                StudioLeaderboardRow(
                    id: profile.uid,
                    name: "\(profile.displayName) (You)",
                    minutes: max(myTotalMinutes, totals[profile.uid] ?? 0),
                    isMe: true,
                    avatarID: profile.avatarID,
                    publicLevel: profile.publicLevel
                )
            ]

            rows += buddies.map { buddy in
                StudioLeaderboardRow(
                    id: buddy.id,
                    name: buddy.displayName,
                    minutes: totals[buddy.id] ?? 0,
                    isMe: false,
                    avatarID: buddy.avatarID,
                    publicLevel: buddy.publicLevel
                )
            }

            leaderboardRows = rows.sorted {
                if $0.minutes == $1.minutes { return $0.name < $1.name }
                return $0.minutes > $1.minutes
            }
            lastLeaderboardKey = key
            lastLeaderboardRefreshAt = Date()
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    private func attachListeners(uid: String) {
        let profileListener = repository.listenToMyProfile(uid: uid) { [weak self] profile in
            self?.myProfile = profile
        }

        let incomingListener = repository.listenToIncomingInvites(uid: uid) { [weak self] invites in
            self?.incomingInvites = invites
        }

        let outgoingListener = repository.listenToOutgoingInvites(uid: uid) { [weak self] invites in
            self?.outgoingInvites = invites
        }

        let buddiesListener = repository.listenToBuddies(uid: uid) { [weak self] rows in
            self?.buddies = rows
        }

        listeners = [profileListener, incomingListener, outgoingListener, buddiesListener]
    }
}
