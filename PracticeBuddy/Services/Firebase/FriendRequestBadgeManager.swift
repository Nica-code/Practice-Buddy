import Foundation
import Combine
import FirebaseFirestore

@MainActor
final class FriendRequestBadgeManager: ObservableObject {
    @Published private(set) var incomingCount: Int = 0

    private let repository: FirebaseBuddiesRepository
    private var listener: ListenerRegistration?
    private var configuredUID: String?
    private var didReceiveInitialSnapshot = false
    private var previousInviteIDs: Set<String> = []

    init(repository: FirebaseBuddiesRepository? = nil) {
        self.repository = repository ?? FirebaseBuddiesRepository()
    }

    func start(uid: String) {
        guard !uid.isEmpty else {
            stop()
            return
        }
        if configuredUID == uid, listener != nil { return }

        stop()
        configuredUID = uid
        didReceiveInitialSnapshot = false
        previousInviteIDs = []
        listener = repository.listenToIncomingInvites(uid: uid) { [weak self] invites in
            guard let self else { return }
            self.incomingCount = invites.count
            let currentIDs = Set(invites.map(\.id))
            if self.didReceiveInitialSnapshot {
                let newIDs = currentIDs.subtracting(self.previousInviteIDs)
                if let newInvite = invites.first(where: { newIDs.contains($0.id) }) {
                    PBNotificationCenter.maybeScheduleFriendRequestNotification(
                        fromDisplayName: newInvite.fromDisplayName,
                        friendUID: newInvite.fromUid
                    )
                }
            } else {
                self.didReceiveInitialSnapshot = true
            }
            self.previousInviteIDs = currentIDs
        }
    }

    func stop() {
        listener?.remove()
        listener = nil
        configuredUID = nil
        incomingCount = 0
        didReceiveInitialSnapshot = false
        previousInviteIDs = []
    }
}
