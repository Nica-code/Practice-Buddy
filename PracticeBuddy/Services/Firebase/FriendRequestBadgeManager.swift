import Foundation
import Combine
import FirebaseFirestore

@MainActor
final class FriendRequestBadgeManager: ObservableObject {
    @Published private(set) var incomingCount: Int = 0

    private let repository: FirebaseBuddiesRepository
    private var listener: ListenerRegistration?
    private var configuredUID: String?

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
        listener = repository.listenToIncomingInvites(uid: uid) { [weak self] invites in
            self?.incomingCount = invites.count
        }
    }

    func stop() {
        listener?.remove()
        listener = nil
        configuredUID = nil
        incomingCount = 0
    }
}
