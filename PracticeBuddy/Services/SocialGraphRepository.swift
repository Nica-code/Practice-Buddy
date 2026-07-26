import Foundation
import Combine
import FirebaseAuth

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

/// All relationship writes pass through Cloud Functions. This keeps the app
/// client content-free and leaves age, block, and private-account policy on
/// the server rather than relying on a screen to enforce it.
final class SocialGraphRepository {
    private let session: URLSession

    nonisolated init(session: URLSession = .shared) {
        self.session = session
    }

    func act(
        _ action: StudioQuestSocialAction,
        targetUID: String,
        reason: [String: String]? = nil
    ) async throws -> String {
        var payload: [String: Any] = ["action": action.rawValue, "targetUID": targetUID]
        if let reason { payload["reason"] = reason }
        let response = try await post(path: "socialAction", payload: payload)
        guard response["ok"] as? Bool == true else {
            throw SocialGraphError.server(response["error"] as? String ?? "That community action could not be completed.")
        }
        return response["status"] as? String ?? "updated"
    }

    func connections(section: CommunityConnectionsSection) async throws -> [StudioQuestSocialConnection] {
        let response = try await post(path: "socialConnections", payload: ["section": section.rawValue])
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

    private func post(path: String, payload: [String: Any]) async throws -> [String: Any] {
        guard let baseURL = AppInfo.duelFunctionsBaseURL,
              let user = Auth.auth().currentUser else {
            throw SocialGraphError.unavailable
        }
        let token = try await user.getIDToken()
        var request = URLRequest(url: baseURL.appendingPathComponent(path))
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw SocialGraphError.unavailable }
        let body = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        guard (200..<300).contains(http.statusCode) else {
            throw SocialGraphError.server(body["error"] as? String ?? "Community service failed (\(http.statusCode)).")
        }
        return body
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
    @Published private(set) var isLoading = false
    @Published var statusMessage: String?

    private let repository: SocialGraphRepository

    init(repository: SocialGraphRepository = .init()) {
        self.repository = repository
    }

    func load(section: CommunityConnectionsSection) async {
        isLoading = true
        defer { isLoading = false }
        do {
            rows = try await repository.connections(section: section)
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func perform(
        _ action: StudioQuestSocialAction,
        targetUID: String,
        reason: [String: String]? = nil
    ) async -> Bool {
        do {
            let status = try await repository.act(action, targetUID: targetUID, reason: reason)
            statusMessage = socialStatusMessage(status)
            return true
        } catch {
            statusMessage = error.localizedDescription
            return false
        }
    }

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
