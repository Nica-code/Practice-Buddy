import Foundation
import Combine

struct StudioQuestSocialConnection: Identifiable, Hashable {
    let id: String
    let displayName: String
    let handle: String
    let profilePhotoURL: String
    let instrument: String
    let avatarID: String
    let isIncoming: Bool
}

enum StudioQuestSocialAction: String {
    case follow
    case unfollow
    case acceptFollow
    case declineFollow
    case removeFollower
    case block
    case unblock
    case reportProfile
    case reportMoment
    case mute
}

enum StudioQuestProfileRelationshipState: String, Equatable, Sendable {
    case none
    case requested
    case following
    case followsYou
    case mutualFollowing
    case blocked
}

/// All relationship writes pass through Cloud Functions. This keeps the app
/// client content-free and leaves age, block, and private-account policy on
/// the server rather than relying on a screen to enforce it.
final class SocialGraphRepository {
    private let callable: FirebaseCallableTransport

    init(callable: FirebaseCallableTransport = FirebaseCallableClient()) {
        self.callable = callable
    }

    func act(
        _ action: StudioQuestSocialAction,
        targetUID: String,
        reason: [String: String]? = nil
    ) async throws -> String {
        var payload: [String: Any] = ["action": action.rawValue, "targetUID": targetUID]
        if let reason { payload["reason"] = reason }
        let response = try await callable.call("socialActionV2", data: payload)
        guard response["ok"] as? Bool == true else {
            throw SocialGraphError.server(response["error"] as? String ?? "That community action could not be completed.")
        }
        return response["status"] as? String ?? "updated"
    }

    func connections(section: CommunityConnectionsSection) async throws -> [StudioQuestSocialConnection] {
        let response = try await callable.call(
            "socialConnectionsV2",
            data: ["section": section.rawValue]
        )
        guard response["ok"] as? Bool == true else {
            throw SocialGraphError.server(response["error"] as? String ?? "Connections are unavailable right now.")
        }
        let rows = response["rows"] as? [[String: Any]] ?? []
        return rows.compactMap { row in
            guard let id = row["id"] as? String, !id.isEmpty else { return nil }
            return StudioQuestSocialConnection(
                id: id,
                displayName: row["displayName"] as? String ?? "Musician",
                handle: row["handle"] as? String ?? "",
                profilePhotoURL: row["profilePhotoURL"] as? String ?? "",
                instrument: row["instrument"] as? String ?? "Musician",
                avatarID: row["avatarID"] as? String ?? "avatar_note",
                isIncoming: row["isIncoming"] as? Bool ?? false
            )
        }
    }

    func relationship(targetUID: String) async throws -> StudioQuestProfileRelationshipState {
        let response = try await callable.call(
            "socialRelationshipV2",
            data: ["targetUID": targetUID]
        )
        guard response["ok"] as? Bool == true else {
            throw SocialGraphError.server(response["error"] as? String ?? "This relationship is unavailable right now.")
        }
        guard let rawState = response["state"] as? String,
              let state = StudioQuestProfileRelationshipState(rawValue: rawState) else {
            throw SocialGraphError.server("This relationship could not be read.")
        }
        return state
    }

}

enum SocialGraphError: LocalizedError {
    case unavailable
    case server(String)

    var errorDescription: String? {
        switch self {
        case .unavailable: "Community actions are unavailable right now."
        case .server(let message): message
        }
    }
}

@MainActor
final class StudioQuestSocialGraphCoordinator: ObservableObject {
    @Published private(set) var rows: [StudioQuestSocialConnection] = []
    @Published private(set) var profileRelationship: StudioQuestProfileRelationshipState = .none
    @Published private(set) var hasLoadedRelationship = false
    @Published private(set) var isLoading = false
    @Published private(set) var isPerformingAction = false
    @Published var statusMessage: String?
    @Published private(set) var errorMessage: String?

    private let repository: SocialGraphRepository

    init(repository: SocialGraphRepository? = nil) {
        self.repository = repository ?? SocialGraphRepository()
    }

    func load(section: CommunityConnectionsSection) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            rows = try await repository.connections(section: section)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func loadRelationship(targetUID: String) async {
        hasLoadedRelationship = false
        #if DEBUG
        if let fixture = Self.fixtureRelationship(targetUID: targetUID) {
            profileRelationship = fixture
            statusMessage = nil
            errorMessage = nil
            hasLoadedRelationship = true
            return
        }
        #endif
        isLoading = true
        errorMessage = nil
        defer {
            isLoading = false
            hasLoadedRelationship = true
        }
        do {
            profileRelationship = try await repository.relationship(targetUID: targetUID)
            statusMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func perform(
        _ action: StudioQuestSocialAction,
        targetUID: String,
        reason: [String: String]? = nil
    ) async -> Bool {
        isPerformingAction = true
        errorMessage = nil
        defer { isPerformingAction = false }
        #if DEBUG
        if Self.fixtureRelationship(targetUID: targetUID) != nil {
            applyFixtureAction(action)
            statusMessage = socialStatusMessage(profileRelationship.rawValue)
            return true
        }
        #endif
        do {
            let status = try await repository.act(action, targetUID: targetUID, reason: reason)
            statusMessage = socialStatusMessage(status)
            applyReturnedStatus(status)
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    private func applyReturnedStatus(_ status: String) {
        switch status {
        case "following": profileRelationship = .following
        case "requested": profileRelationship = .requested
        case "unfollowed", "declined", "removed": profileRelationship = .none
        case "blocked": profileRelationship = .blocked
        case "unblocked": profileRelationship = .none
        default: break
        }
    }

    #if DEBUG
    private static func fixtureRelationship(targetUID: String) -> StudioQuestProfileRelationshipState? {
        switch targetUID {
        case "fixture-none": .some(.none)
        case "fixture-requested": .requested
        case "fixture-following": .following
        case "fixture-follower": .followsYou
        case "fixture-mutual": .mutualFollowing
        case "fixture-blocked": .blocked
        case "fixture-aya": .mutualFollowing
        default: nil
        }
    }

    private func applyFixtureAction(_ action: StudioQuestSocialAction) {
        switch action {
        case .follow: profileRelationship = .following
        case .unfollow, .declineFollow, .removeFollower: profileRelationship = .none
        case .acceptFollow: profileRelationship = .following
        case .block: profileRelationship = .blocked
        case .unblock: profileRelationship = .none
        case .reportProfile, .reportMoment, .mute: break
        }
    }
    #endif

    private func socialStatusMessage(_ status: String) -> String {
        switch status {
        case "following": "Following request accepted."
        case "requested": "Follow request sent."
        case "unfollowed": "You are no longer following this musician."
        case "removed": "Follower removed."
        case "blocked": "Musician blocked."
        case "unblocked": "Musician unblocked."
        case "reported": "Report sent. Thank you for helping keep PractiQuest safe."
        case "muted": "Moments from this musician are muted."
        case "declined": "Follow request declined."
        default: "Community preferences updated."
        }
    }
}
