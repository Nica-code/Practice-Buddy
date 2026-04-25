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
    let duelRating: Int
    let isMe: Bool
    let avatarID: String
    let profilePhotoURL: String
    let publicLevel: Int
}

@MainActor
final class BuddiesViewModel: ObservableObject {
    @Published private(set) var myProfile: FirebaseUserProfile?
    @Published private(set) var incomingInvites: [BuddyInvite] = []
    @Published private(set) var outgoingInvites: [BuddyInvite] = []
    @Published private(set) var buddies: [BuddySummary] = []
    @Published private(set) var presenceByUID: [String: BuddyPresenceState] = [:]
    @Published private(set) var buddyStatsByUID: [String: BuddyPublicStats] = [:]
    @Published private(set) var leaderboardRows: [StudioLeaderboardRow] = []
    @Published private(set) var isLoading = false
    @Published var statusMessage: String?

    private let repository: FirebaseBuddiesRepository
    private var listeners: [ListenerRegistration] = []
    private var presenceListenerByUID: [String: ListenerRegistration] = [:]
    private var buddyStatsListenerByUID: [String: ListenerRegistration] = [:]
    private var presenceClockCancellable: AnyCancellable?
    private var configuredUID: String?
    private var lastSyncedPublicLevel: Int?
    private var lastLeaderboardKey: String?
    private var lastLeaderboardRefreshAt: Date?
    private let leaderboardRefreshCooldown: TimeInterval = 60 * 60 * 24

    init(repository: FirebaseBuddiesRepository? = nil) {
        self.repository = repository ?? FirebaseBuddiesRepository()
    }

    convenience init() {
        self.init(repository: nil)
    }

    deinit {
        listeners.forEach { $0.remove() }
        presenceListenerByUID.values.forEach { $0.remove() }
        buddyStatsListenerByUID.values.forEach { $0.remove() }
        presenceClockCancellable?.cancel()
    }

    func start(for uid: String) async {
        if configuredUID == uid { return }

        stop()
        configuredUID = uid
        isLoading = true
        statusMessage = nil
        startPresenceClock()

        do {
            myProfile = try await repository.ensureCurrentUserProfile()
            attachListeners(uid: uid)
            try? await repository.repairLocalBuddyDirectory(uid: uid)
        } catch {
            statusMessage = error.localizedDescription
        }

        isLoading = false
    }

    func stop() {
        listeners.forEach { $0.remove() }
        presenceListenerByUID.values.forEach { $0.remove() }
        buddyStatsListenerByUID.values.forEach { $0.remove() }
        listeners = []
        presenceListenerByUID = [:]
        buddyStatsListenerByUID = [:]
        presenceClockCancellable?.cancel()
        presenceClockCancellable = nil
        configuredUID = nil
        myProfile = nil
        incomingInvites = []
        outgoingInvites = []
        buddies = []
        presenceByUID = [:]
        buddyStatsByUID = [:]
        leaderboardRows = []
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

    func updateProfile(avatarID: String, profilePhotoURL: String? = nil, bio: String, instrument: String) async {
        guard let uid = configuredUID else { return }
        do {
            try await repository.updateProfileDetails(
                uid: uid,
                avatarID: avatarID,
                profilePhotoURL: profilePhotoURL,
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

    func cancelOutgoingInvite(_ invite: BuddyInvite) async {
        do {
            try await repository.declineInvite(invite)
            statusMessage = "Request canceled."
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

    func refreshLeaderboard(force: Bool = false) async {
        guard let profile = myProfile else { return }
        let buddyIDs = buddies.map(\.id)
        let key = [profile.uid, buddyIDs.sorted().joined(separator: ",")].joined(separator: "|")
        if !force,
           lastLeaderboardKey == key,
           let lastLeaderboardRefreshAt,
           Date().timeIntervalSince(lastLeaderboardRefreshAt) < leaderboardRefreshCooldown {
            return
        }

        do {
            let stats = try await repository.fetchPublicStats(forUIDs: [profile.uid] + buddyIDs)
            let myStats = stats[profile.uid] ?? BuddyPublicStats(
                publicLevel: profile.publicLevel,
                duelLeague: "Bronze",
                duelRating: 0,
                profilePhotoURL: profile.profilePhotoURL
            )
            var rows: [StudioLeaderboardRow] = [
                StudioLeaderboardRow(
                    id: profile.uid,
                    name: "\(profile.displayName) (You)",
                    duelRating: myStats.duelRating,
                    isMe: true,
                    avatarID: profile.avatarID,
                    profilePhotoURL: myStats.profilePhotoURL,
                    publicLevel: myStats.publicLevel
                )
            ]

            rows += buddies.map { buddy in
                let buddyStats = stats[buddy.id] ?? BuddyPublicStats(
                    publicLevel: buddy.publicLevel,
                    duelLeague: "Bronze",
                    duelRating: 0,
                    profilePhotoURL: buddy.profilePhotoURL
                )
                return StudioLeaderboardRow(
                    id: buddy.id,
                    name: buddy.displayName,
                    duelRating: buddyStats.duelRating,
                    isMe: false,
                    avatarID: buddy.avatarID,
                    profilePhotoURL: buddyStats.profilePhotoURL,
                    publicLevel: buddyStats.publicLevel
                )
            }

            leaderboardRows = rows.sorted {
                if $0.publicLevel != $1.publicLevel { return $0.publicLevel > $1.publicLevel }
                if $0.duelRating != $1.duelRating { return $0.duelRating > $1.duelRating }
                return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
            lastLeaderboardKey = key
            lastLeaderboardRefreshAt = Date()
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func isBuddyOnline(_ uid: String) -> Bool {
        guard let presence = presenceByUID[uid] else { return false }
        guard presence.state == .online else { return false }
        return Date().timeIntervalSince(presence.lastChanged) <= 120
    }

    func buddyDisplayLevel(_ uid: String) -> Int {
        buddyStatsByUID[uid]?.publicLevel ?? 1
    }

    func buddyDisplayLeague(_ uid: String) -> String {
        buddyStatsByUID[uid]?.duelLeague ?? "Bronze"
    }

    func buddyProfilePhotoURL(_ uid: String, fallback: String = "") -> String {
        let resolved = (buddyStatsByUID[uid]?.profilePhotoURL ?? fallback).trimmingCharacters(in: .whitespacesAndNewlines)
        return resolved
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
            self?.attachPresenceListeners(for: rows.map(\.id))
            self?.attachBuddyStatsListeners(for: rows.map(\.id))
        }

        listeners = [profileListener, incomingListener, outgoingListener, buddiesListener]
    }

    private func attachPresenceListeners(for uids: [String]) {
        let targetUIDs = Set(uids.filter { !$0.isEmpty })
        let existingUIDs = Set(presenceListenerByUID.keys)

        let toRemove = existingUIDs.subtracting(targetUIDs)
        for uid in toRemove {
            presenceListenerByUID[uid]?.remove()
            presenceListenerByUID[uid] = nil
            presenceByUID[uid] = nil
        }

        let toAdd = targetUIDs.subtracting(existingUIDs)
        for uid in toAdd {
            presenceListenerByUID[uid] = repository.listenToPresence(uid: uid) { [weak self] state in
                self?.presenceByUID[uid] = state
            }
        }

    }

    private func attachBuddyStatsListeners(for uids: [String]) {
        let targetUIDs = Set(uids.filter { !$0.isEmpty })
        let existingUIDs = Set(buddyStatsListenerByUID.keys)

        let toRemove = existingUIDs.subtracting(targetUIDs)
        for uid in toRemove {
            buddyStatsListenerByUID[uid]?.remove()
            buddyStatsListenerByUID[uid] = nil
            buddyStatsByUID[uid] = nil
        }

        let toAdd = targetUIDs.subtracting(existingUIDs)
        for uid in toAdd {
            buddyStatsListenerByUID[uid] = repository.listenToPublicStats(uid: uid) { [weak self] stats in
                self?.buddyStatsByUID[uid] = stats
            }
        }

    }

    private func startPresenceClock() {
        presenceClockCancellable?.cancel()
        presenceClockCancellable = Timer.publish(every: 30, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                // Trigger lightweight UI refresh so stale "online" states age out.
                self?.objectWillChange.send()
            }
    }
}
