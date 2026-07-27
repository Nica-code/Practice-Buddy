import Foundation
import Combine
import FirebaseAuth
import FirebaseFirestore

final class PracticeMomentRepository {
    private let db = Firestore.firestore()
    private let callable: FirebaseCallableTransport

    init(callable: FirebaseCallableTransport = FirebaseCallableClient()) {
        self.callable = callable
    }

    func fetchFollowingFeed(uid: String, limit: Int = 20) async throws -> MomentFeedPage {
        let inbox = try await db.collection("feedInboxes")
            .document(uid)
            .collection("items")
            .whereField("expiresAt", isGreaterThan: Timestamp(date: .now))
            .order(by: "expiresAt", descending: true)
            .limit(to: min(max(limit, 1), 20))
            .getDocuments()
        let ids = inbox.documents.compactMap { $0.data()["momentID"] as? String }.filter { !$0.isEmpty }
        let moments = try await withThrowingTaskGroup(of: PracticeMoment?.self) { group in
            for id in ids {
                group.addTask { try await self.fetchMoment(id: id) }
            }
            var rows: [PracticeMoment] = []
            for try await result in group {
                if let result, result.isActive { rows.append(result) }
            }
            return rows.sorted { $0.createdAt > $1.createdAt }
        }
        return MomentFeedPage(
            moments: moments,
            nextCursor: inbox.documents.last?.documentID,
            hasMore: inbox.documents.count >= min(max(limit, 1), 20)
        )
    }

    func fetchMoment(id: String) async throws -> PracticeMoment? {
        let snapshot = try await db.collection("practiceMoments").document(id).getDocument()
        return parseMoment(id: snapshot.documentID, data: snapshot.data())
    }

    func publish(
        sessionID: UUID,
        durationSeconds: Int,
        category: String,
        verified: Bool,
        tag: MomentTag,
        audience: MomentAudience,
        loadout: AvatarLoadout
    ) async throws -> PracticeMoment {
        guard Auth.auth().currentUser != nil else {
            throw PracticeMomentRepositoryError.unavailable
        }
        let payload: [String: Any] = [
            "sessionID": sessionID.uuidString,
            "durationSeconds": max(0, durationSeconds),
            "localDayKey": Self.localDayKey(),
            "practiceCategory": String(category.prefix(40)),
            "isVerified": verified,
            "tag": tag.rawValue,
            "audience": audience.rawValue,
            "avatarLoadout": avatarPayload(loadout)
        ]
        let response = try await callable.call("practiceMomentCreateV2", data: payload)
        guard response["ok"] as? Bool == true,
              let id = response["momentID"] as? String,
              let moment = try await fetchMoment(id: id) else {
            throw PracticeMomentRepositoryError.server(response["error"] as? String ?? "Couldn’t publish this Moment.")
        }
        return moment
    }

    func react(momentID: String, kind: MomentReactionKind) async throws {
        guard Auth.auth().currentUser != nil else {
            throw PracticeMomentRepositoryError.unavailable
        }
        let response = try await callable.call(
            "practiceMomentReactV2",
            data: ["momentID": momentID, "reaction": kind.rawValue]
        )
        guard response["ok"] as? Bool == true else {
            throw PracticeMomentRepositoryError.server(response["error"] as? String ?? "Couldn’t save that reaction.")
        }
    }

    private func parseMoment(id: String, data: [String: Any]?) -> PracticeMoment? {
        guard let data,
              let authorUID = data["authorUID"] as? String,
              let displayName = data["displayName"] as? String,
              let handle = data["handle"] as? String,
              let tagRaw = data["tag"] as? String,
              let tag = MomentTag(rawValue: tagRaw),
              let audienceRaw = data["audience"] as? String,
              let audience = MomentAudience(rawValue: audienceRaw),
              let createdAt = (data["createdAt"] as? Timestamp)?.dateValue(),
              let expiresAt = (data["expiresAt"] as? Timestamp)?.dateValue() else {
            return nil
        }
        let loadout = decodeLoadout(data["avatarLoadout"] as? [String: Any])
        var reactionCounts: [MomentReactionKind: Int] = [:]
        for (raw, count) in (data["reactionCounts"] as? [String: Int] ?? [:]) {
            if let kind = MomentReactionKind(rawValue: raw) { reactionCounts[kind] = max(0, count) }
        }
        return PracticeMoment(
            id: id,
            authorUID: authorUID,
            displayName: displayName,
            handle: handle,
            profilePhotoURL: data["profilePhotoURL"] as? String ?? "",
            instrument: data["instrument"] as? String ?? "Musician",
            durationBucket: data["durationBucket"] as? String ?? "Focused practice",
            practiceCategory: data["practiceCategory"] as? String ?? "Practice",
            isVerified: data["isVerified"] as? Bool ?? false,
            tag: tag,
            audience: audience,
            avatarLoadout: loadout,
            createdAt: createdAt,
            expiresAt: expiresAt,
            moderationState: MomentModerationState(rawValue: data["moderationState"] as? String ?? "active") ?? .active,
            reactions: reactionCounts
        )
    }

    private func avatarPayload(_ loadout: AvatarLoadout) -> [String: Any] {
        [
            "version": loadout.version,
            "baseID": loadout.baseID,
            "skinToneID": loadout.skinToneID,
            "hairID": loadout.hairID,
            "outfitID": loadout.outfitID,
            "instrumentID": loadout.instrumentID,
            "accessoryID": loadout.accessoryID as Any,
            "poseID": loadout.poseID,
            "roomID": loadout.roomID,
            "roomLayouts": roomLayoutsPayload(loadout.roomLayouts)
        ]
    }

    private static func localDayKey(now: Date = .now) -> String {
        let formatter = DateFormatter()
        formatter.calendar = .current
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: now)
    }

    private func roomLayoutsPayload(_ layouts: [String: StudioQuestRoomLayout]) -> [String: Any] {
        Dictionary(uniqueKeysWithValues: layouts.map { id, layout in
            (id, [
                "roomID": layout.roomID,
                "updatedAt": layout.updatedAt.timeIntervalSince1970,
                "placements": layout.placements.map { placement in
                    [
                        "id": placement.id,
                        "decorationID": placement.decorationID,
                        "position": ["x": placement.position.x, "y": placement.position.y],
                        "scale": placement.scale,
                        "rotationDegrees": placement.rotationDegrees,
                        "depth": placement.depth
                    ]
                }
            ])
        })
    }

    private func decodeLoadout(_ raw: [String: Any]?) -> AvatarLoadout {
        guard let raw,
              JSONSerialization.isValidJSONObject(raw),
              let data = try? JSONSerialization.data(withJSONObject: raw),
              let decoded = try? JSONDecoder().decode(AvatarLoadout.self, from: data) else {
            return .starter(for: nil)
        }
        return decoded
    }
}

enum PracticeMomentRepositoryError: LocalizedError {
    case unavailable
    case server(String)

    var errorDescription: String? {
        switch self {
        case .unavailable: "Practice Moments are unavailable right now."
        case .server(let message): message
        }
    }
}

@MainActor
final class CommunityCoordinator: ObservableObject {
    @Published private(set) var moments: [PracticeMoment] = []
    @Published private(set) var isLoading = false
    @Published var statusMessage: String?

    private let repository: PracticeMomentRepository
    private var configuredUID: String?

    init(repository: PracticeMomentRepository? = nil) {
        self.repository = repository ?? PracticeMomentRepository()
    }

    func configure(uid: String?, isAnonymous: Bool) async {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--qa-community-populated") {
            configuredUID = "fixture-adult"
            moments = Self.fixtureMoments
            statusMessage = nil
            return
        }
        #endif
        configuredUID = isAnonymous ? nil : uid
        guard let uid = configuredUID else {
            moments = []
            return
        }
        await refresh(uid: uid)
    }

    func refresh() async {
        #if DEBUG
        if configuredUID == "fixture-adult" {
            moments = Self.fixtureMoments
            return
        }
        #endif
        guard let uid = configuredUID else { return }
        await refresh(uid: uid)
    }

    func react(to moment: PracticeMoment, kind: MomentReactionKind) async {
        #if DEBUG
        if configuredUID == "fixture-adult" {
            if let index = moments.firstIndex(where: { $0.id == moment.id }) {
                moments[index].reactions[kind, default: 0] += 1
            }
            return
        }
        #endif
        do {
            try await repository.react(momentID: moment.id, kind: kind)
            if let index = moments.firstIndex(where: { $0.id == moment.id }) {
                moments[index].reactions[kind, default: 0] += 1
            }
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func publish(
        sessionID: UUID,
        durationSeconds: Int,
        category: String,
        verified: Bool,
        tag: MomentTag,
        audience: MomentAudience,
        loadout: AvatarLoadout
    ) async -> Bool {
        do {
            let moment = try await repository.publish(
                sessionID: sessionID,
                durationSeconds: durationSeconds,
                category: category,
                verified: verified,
                tag: tag,
                audience: audience,
                loadout: loadout
            )
            moments.insert(moment, at: 0)
            PracticeAnalytics.record(.practiceMomentPublished)
            return true
        } catch {
            statusMessage = error.localizedDescription
            return false
        }
    }

    private func refresh(uid: String) async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            moments = try await repository.fetchFollowingFeed(uid: uid).moments
        } catch {
            statusMessage = "We couldn’t refresh Moments. Pull to try again."
        }
    }

    #if DEBUG
    private static var fixtureMoments: [PracticeMoment] {
        let now = Date()
        var aya = AvatarLoadout.starter(for: "avatar_note")
        aya.roomID = "room_daylight_studio"
        aya.instrumentID = "instrument_violin"
        var mateo = AvatarLoadout.starter(for: "avatar_guitar")
        mateo.roomID = "room_creative_loft"
        mateo.instrumentID = "instrument_guitar"

        return [
            PracticeMoment(
                id: "fixture-moment-aya",
                authorUID: "fixture-aya",
                displayName: "Aya Chen",
                handle: "ayaplays",
                profilePhotoURL: "",
                instrument: "Violin",
                durationBucket: "45–60 min",
                practiceCategory: "Technique",
                isVerified: true,
                tag: .breakthrough,
                audience: .friends,
                avatarLoadout: aya,
                createdAt: now.addingTimeInterval(-1_800),
                expiresAt: now.addingTimeInterval(82_800),
                moderationState: .active,
                reactions: [.bravo: 4, .inspired: 2]
            ),
            PracticeMoment(
                id: "fixture-moment-mateo",
                authorUID: "fixture-mateo",
                displayName: "Mateo Silva",
                handle: "mateosilva",
                profilePhotoURL: "",
                instrument: "Guitar",
                durationBucket: "20–30 min",
                practiceCategory: "Run-through",
                isVerified: false,
                tag: .performancePrep,
                audience: .friends,
                avatarLoadout: mateo,
                createdAt: now.addingTimeInterval(-7_200),
                expiresAt: now.addingTimeInterval(79_200),
                moderationState: .active,
                reactions: [.strongWork: 3, .practiceTogether: 1]
            )
        ]
    }
    #endif
}
