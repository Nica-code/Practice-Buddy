import Foundation
import Combine
import FirebaseFirestore

struct StudioLeaderboardRow: Identifiable, Equatable {
    let id: String
    let name: String
    let minutes: Int
    let isMe: Bool
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
    }

    func sendInvite(friendCode: String) async -> String? {
        guard let myProfile else {
            statusMessage = "Profile is not ready yet."
            return nil
        }

        do {
            let newBuddyUID = try await repository.sendInvite(from: myProfile, friendCode: friendCode)
            statusMessage = "Buddy added."
            return newBuddyUID
        } catch {
            statusMessage = error.localizedDescription
            return nil
        }
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
        do {
            try await repository.updatePracticeTotalMinutes(uid: uid, minutes: minutes)
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func refreshLeaderboard(myTotalMinutes: Int) async {
        guard let profile = myProfile else { return }
        let buddyIDs = buddies.map(\.id)

        do {
            let totals = try await repository.fetchPracticeMinutes(forUIDs: [profile.uid] + buddyIDs)
            var rows: [StudioLeaderboardRow] = [
                StudioLeaderboardRow(
                    id: profile.uid,
                    name: "\(profile.displayName) (You)",
                    minutes: max(myTotalMinutes, totals[profile.uid] ?? 0),
                    isMe: true
                )
            ]

            rows += buddies.map { buddy in
                StudioLeaderboardRow(
                    id: buddy.id,
                    name: buddy.displayName,
                    minutes: totals[buddy.id] ?? 0,
                    isMe: false
                )
            }

            leaderboardRows = rows.sorted {
                if $0.minutes == $1.minutes { return $0.name < $1.name }
                return $0.minutes > $1.minutes
            }
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
