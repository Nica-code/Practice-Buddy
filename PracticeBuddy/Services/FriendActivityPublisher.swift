import Foundation
import Combine

@MainActor
final class FriendActivityPublisher: ObservableObject {
    private let repository: FirebaseBuddiesRepository
    private var lastPublicationKey = ""

    init(repository: FirebaseBuddiesRepository? = nil) {
        self.repository = repository ?? FirebaseBuddiesRepository()
    }

    func update(
        currentUserID: String?,
        isAnonymous: Bool,
        buddyIDs: [String],
        latestSessionDate: Date?,
        sharingEnabled: Bool
    ) {
        guard let currentUserID,
              !currentUserID.isEmpty,
              !isAnonymous else { return }

        let sharedDate = sharingEnabled ? latestSessionDate : nil
        let key = [
            currentUserID,
            buddyIDs.sorted().joined(separator: ","),
            sharedDate.map { String($0.timeIntervalSince1970) } ?? "cleared"
        ].joined(separator: "|")
        guard key != lastPublicationKey else { return }
        lastPublicationKey = key

        Task {
            try? await repository.publishFriendActivity(
                from: currentUserID,
                to: buddyIDs,
                lastPracticedAt: sharedDate
            )
        }
    }
}
