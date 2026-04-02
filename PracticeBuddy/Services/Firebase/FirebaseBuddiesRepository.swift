import Foundation
import FirebaseAuth
import FirebaseFirestore

struct FirebaseUserProfile: Equatable {
    let uid: String
    let displayName: String
    let friendCode: String
    let nameEditUsed: Bool
    let avatarID: String
    let bio: String
    let instrument: String
    let publicLevel: Int
}

struct BuddySummary: Identifiable, Equatable {
    let id: String
    let displayName: String
    let friendCode: String
    let sinceAt: Date
    let avatarID: String
    let publicLevel: Int
}

enum BuddyPresenceValue: String {
    case online
    case offline
}

struct BuddyPresenceState: Equatable {
    let state: BuddyPresenceValue
    let lastChanged: Date
}

struct BuddyPublicStats: Equatable {
    let publicLevel: Int
    let duelLeague: String
    let duelRating: Int
}

enum BuddyInviteStatus: String {
    case pending
    case accepted
    case declined
}

struct BuddyInvite: Identifiable, Equatable {
    let id: String
    let fromUid: String
    let toUid: String
    let fromDisplayName: String
    let fromFriendCode: String
    let toDisplayName: String
    let toFriendCode: String
    let status: BuddyInviteStatus
    let createdAt: Date
}

enum FirebaseBuddiesError: LocalizedError {
    case missingCurrentUser
    case profileNotFound
    case invalidFriendCode
    case userNotFound
    case cannotInviteSelf
    case alreadyBuddies
    case inviteAlreadySent
    case inviteAlreadyReceived
    case missingInviteTarget
    case invalidDisplayName
    case displayNameLocked

    var errorDescription: String? {
        switch self {
        case .missingCurrentUser: return "No signed-in Firebase user."
        case .profileNotFound: return "Profile not found."
        case .invalidFriendCode: return "Enter a valid friend code."
        case .userNotFound: return "No user found for that code."
        case .cannotInviteSelf: return "You cannot invite yourself."
        case .alreadyBuddies: return "You are already buddies."
        case .inviteAlreadySent: return "Invite already sent."
        case .inviteAlreadyReceived: return "That user already sent you an invite."
        case .missingInviteTarget: return "Invite target not found."
        case .invalidDisplayName: return "Use 2-30 letters/numbers only (no spaces or symbols)."
        case .displayNameLocked: return "Name can only be changed once."
        }
    }
}

final class FirebaseBuddiesRepository {
    private lazy var db = Firestore.firestore()
    private let usersCollection = "users"
    private let invitesCollection = "invites"
    private let friendshipsCollection = "friendships"

    func currentUserID() -> String? {
        Auth.auth().currentUser?.uid
    }

    func ensureCurrentUserProfile() async throws -> FirebaseUserProfile {
        guard let uid = currentUserID() else {
            throw FirebaseBuddiesError.missingCurrentUser
        }

        let ref = db.collection(usersCollection).document(uid)
        let existing = try await ref.getDocument()
        if let profile = parseUserProfile(uid: uid, data: existing.data()) {
            return profile
        }

        let defaultDisplayName = "Player\(uid.prefix(4).uppercased())"

        for _ in 0..<6 {
            let code = makeFriendCode()
            let query = try await db.collection(usersCollection)
                .whereField("friendCode", isEqualTo: code)
                .limit(to: 1)
                .getDocuments()

            if !query.documents.isEmpty { continue }

            try await ref.setData([
                "displayName": defaultDisplayName,
                "friendCode": code,
                "nameEditUsed": false,
                "avatarID": "avatar_note",
                "bio": "",
                "instrument": "",
                "publicLevel": 1,
                "totalPracticeMinutes": 0,
                "createdAt": FieldValue.serverTimestamp(),
                "updatedAt": FieldValue.serverTimestamp()
            ], merge: true)

            return FirebaseUserProfile(
                uid: uid,
                displayName: defaultDisplayName,
                friendCode: code,
                nameEditUsed: false,
                avatarID: "avatar_note",
                bio: "",
                instrument: "",
                publicLevel: 1
            )
        }

        throw FirebaseBuddiesError.invalidFriendCode
    }

    func listenToMyProfile(
        uid: String,
        onChange: @escaping @MainActor (FirebaseUserProfile?) -> Void
    ) -> ListenerRegistration {
        db.collection(usersCollection).document(uid).addSnapshotListener { snap, _ in
            Task { @MainActor in
                let profile = self.parseUserProfile(uid: uid, data: snap?.data())
                onChange(profile)
            }
        }
    }

    func listenToIncomingInvites(
        uid: String,
        onChange: @escaping @MainActor ([BuddyInvite]) -> Void
    ) -> ListenerRegistration {
        db.collection(invitesCollection)
            .whereField("toUid", isEqualTo: uid)
            .whereField("status", isEqualTo: BuddyInviteStatus.pending.rawValue)
            .addSnapshotListener { snap, _ in
                Task { @MainActor in
                    let rows = self.parseInvites(from: snap?.documents ?? [])
                        .sorted(by: { $0.createdAt > $1.createdAt })
                    onChange(rows)
                }
            }
    }

    func listenToOutgoingInvites(
        uid: String,
        onChange: @escaping @MainActor ([BuddyInvite]) -> Void
    ) -> ListenerRegistration {
        db.collection(invitesCollection)
            .whereField("fromUid", isEqualTo: uid)
            .whereField("status", isEqualTo: BuddyInviteStatus.pending.rawValue)
            .addSnapshotListener { snap, _ in
                Task { @MainActor in
                    let rows = self.parseInvites(from: snap?.documents ?? [])
                        .sorted(by: { $0.createdAt > $1.createdAt })
                    onChange(rows)
                }
            }
    }

    func listenToBuddies(
        uid: String,
        onChange: @escaping @MainActor ([BuddySummary]) -> Void
    ) -> ListenerRegistration {
        db.collection(friendshipsCollection)
            .document(uid)
            .collection("buddies")
            .addSnapshotListener { snap, _ in
                Task { @MainActor in
                    let rows = self.parseBuddies(from: snap?.documents ?? [])
                        .sorted(by: { $0.sinceAt > $1.sinceAt })
                    onChange(rows)
                }
            }
    }

    func listenToPresence(
        uid: String,
        onChange: @escaping @MainActor (BuddyPresenceState) -> Void
    ) -> ListenerRegistration {
        db.collection(usersCollection).document(uid).addSnapshotListener { snap, _ in
            Task { @MainActor in
                let data = snap?.data()
                let stateRaw = (data?["presenceState"] as? String) ?? BuddyPresenceValue.offline.rawValue
                let state = BuddyPresenceValue(rawValue: stateRaw) ?? .offline
                let lastChanged = (data?["presenceLastChanged"] as? Timestamp)?.dateValue() ?? .distantPast
                onChange(BuddyPresenceState(state: state, lastChanged: lastChanged))
            }
        }
    }

    func listenToPublicStats(
        uid: String,
        onChange: @escaping @MainActor (BuddyPublicStats) -> Void
    ) -> ListenerRegistration {
        db.collection(usersCollection).document(uid).addSnapshotListener { snap, _ in
            Task { @MainActor in
                let data = snap?.data()
                let level = max(1, (data?["publicLevel"] as? Int) ?? 1)
                let leagueRaw = ((data?["duelLeague"] as? String) ?? "bronze").trimmingCharacters(in: .whitespacesAndNewlines)
                let league = leagueRaw.isEmpty ? "Bronze" : leagueRaw.capitalized
                let rating = max(0, (data?["duelRating"] as? Int) ?? 0)
                onChange(BuddyPublicStats(publicLevel: level, duelLeague: league, duelRating: rating))
            }
        }
    }

    func fetchPublicStats(forUIDs uids: [String]) async throws -> [String: BuddyPublicStats] {
        let unique = Array(Set(uids))
        guard !unique.isEmpty else { return [:] }

        var output: [String: BuddyPublicStats] = [:]
        for chunk in unique.chunked(into: 10) {
            let snapshot = try await db.collection(usersCollection)
                .whereField(FieldPath.documentID(), in: chunk)
                .getDocuments()
            for doc in snapshot.documents {
                let data = doc.data()
                let level = max(1, (data["publicLevel"] as? Int) ?? 1)
                let leagueRaw = ((data["duelLeague"] as? String) ?? "bronze").trimmingCharacters(in: .whitespacesAndNewlines)
                let league = leagueRaw.isEmpty ? "Bronze" : leagueRaw.capitalized
                let rating = max(0, (data["duelRating"] as? Int) ?? 0)
                output[doc.documentID] = BuddyPublicStats(publicLevel: level, duelLeague: league, duelRating: rating)
            }
        }
        return output
    }

    func sendInvite(from myProfile: FirebaseUserProfile, friendCode rawCode: String) async throws -> String {
        let code = rawCode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !code.isEmpty else { throw FirebaseBuddiesError.invalidFriendCode }

        let targetQuery = try await db.collection(usersCollection)
            .whereField("friendCode", isEqualTo: code)
            .limit(to: 1)
            .getDocuments()

        guard let targetDoc = targetQuery.documents.first else {
            throw FirebaseBuddiesError.userNotFound
        }

        let targetUid = targetDoc.documentID
        guard targetUid != myProfile.uid else {
            throw FirebaseBuddiesError.cannotInviteSelf
        }

        guard let targetProfile = parseUserProfile(uid: targetUid, data: targetDoc.data()) else {
            throw FirebaseBuddiesError.missingInviteTarget
        }

        try await createPendingInvite(from: myProfile, to: targetProfile)
        return targetUid
    }

    func sendInvite(from myProfile: FirebaseUserProfile, to targetUID: String) async throws {
        let cleanedUID = targetUID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanedUID.isEmpty else { throw FirebaseBuddiesError.missingInviteTarget }
        guard cleanedUID != myProfile.uid else { throw FirebaseBuddiesError.cannotInviteSelf }

        let targetDoc = try await db.collection(usersCollection).document(cleanedUID).getDocument()
        guard targetDoc.exists else { throw FirebaseBuddiesError.userNotFound }
        guard let targetProfile = parseUserProfile(uid: cleanedUID, data: targetDoc.data()) else {
            throw FirebaseBuddiesError.missingInviteTarget
        }

        try await createPendingInvite(from: myProfile, to: targetProfile)
    }

    func fetchUserProfile(uid: String) async throws -> FirebaseUserProfile {
        let cleanedUID = uid.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanedUID.isEmpty else { throw FirebaseBuddiesError.userNotFound }
        let doc = try await db.collection(usersCollection).document(cleanedUID).getDocument()
        guard let profile = parseUserProfile(uid: cleanedUID, data: doc.data()) else {
            throw FirebaseBuddiesError.profileNotFound
        }
        return profile
    }

    func updateDisplayName(uid: String, rawDisplayName: String) async throws {
        let cleanedRaw = rawDisplayName.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleaned = normalizedDisplayName(from: cleanedRaw)
        guard (2...30).contains(cleaned.count) else {
            throw FirebaseBuddiesError.invalidDisplayName
        }
        guard cleaned == cleanedRaw else {
            throw FirebaseBuddiesError.invalidDisplayName
        }

        let userRef = db.collection(usersCollection).document(uid)
        let snap = try await userRef.getDocument()
        let used = (snap.data()?["nameEditUsed"] as? Bool) ?? false
        if used {
            throw FirebaseBuddiesError.displayNameLocked
        }

        try await db.collection(usersCollection).document(uid).setData([
            "displayName": cleaned,
            "nameEditUsed": true,
            "updatedAt": FieldValue.serverTimestamp()
        ], merge: true)
    }

    func updateProfileDetails(
        uid: String,
        avatarID: String,
        rawBio: String,
        rawInstrument: String
    ) async throws {
        let cleanBio = String(rawBio.trimmingCharacters(in: .whitespacesAndNewlines).prefix(160))
        let cleanInstrument = String(rawInstrument.trimmingCharacters(in: .whitespacesAndNewlines).prefix(40))
        let cleanAvatar = avatarID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "avatar_note" : avatarID

        try await db.collection(usersCollection).document(uid).setData([
            "avatarID": cleanAvatar,
            "bio": cleanBio,
            "instrument": cleanInstrument,
            "updatedAt": FieldValue.serverTimestamp()
        ], merge: true)
    }

    func updatePublicLevel(uid: String, level: Int) async throws {
        try await db.collection(usersCollection).document(uid).setData([
            "publicLevel": max(1, level),
            "updatedAt": FieldValue.serverTimestamp()
        ], merge: true)
    }

    func removeBuddy(myUID: String, buddyUID: String) async throws {
        let meBuddyRef = db.collection(friendshipsCollection)
            .document(myUID)
            .collection("buddies")
            .document(buddyUID)
        let themBuddyRef = db.collection(friendshipsCollection)
            .document(buddyUID)
            .collection("buddies")
            .document(myUID)

        let batch = db.batch()
        batch.deleteDocument(meBuddyRef)
        batch.deleteDocument(themBuddyRef)

        let outboundInvites = try await db.collection(invitesCollection)
            .whereField("fromUid", isEqualTo: myUID)
            .whereField("toUid", isEqualTo: buddyUID)
            .whereField("status", isEqualTo: BuddyInviteStatus.pending.rawValue)
            .getDocuments()

        let inboundInvites = try await db.collection(invitesCollection)
            .whereField("fromUid", isEqualTo: buddyUID)
            .whereField("toUid", isEqualTo: myUID)
            .whereField("status", isEqualTo: BuddyInviteStatus.pending.rawValue)
            .getDocuments()

        for doc in outboundInvites.documents {
            batch.deleteDocument(doc.reference)
        }
        for doc in inboundInvites.documents {
            batch.deleteDocument(doc.reference)
        }

        try await batch.commit()
    }

    func updatePracticeTotalMinutes(uid: String, minutes: Int) async throws {
        try await db.collection(usersCollection).document(uid).setData([
            "totalPracticeMinutes": max(0, minutes),
            "updatedAt": FieldValue.serverTimestamp()
        ], merge: true)
    }

    func fetchPracticeMinutes(forUIDs uids: [String]) async throws -> [String: Int] {
        let unique = Array(Set(uids))
        guard !unique.isEmpty else { return [:] }

        var output: [String: Int] = [:]
        for chunk in unique.chunked(into: 10) {
            let snapshot = try await db.collection(usersCollection)
                .whereField(FieldPath.documentID(), in: chunk)
                .getDocuments()

            for doc in snapshot.documents {
                let minutes = (doc.data()["totalPracticeMinutes"] as? Int) ?? 0
                output[doc.documentID] = max(0, minutes)
            }
        }

        return output
    }

    func acceptInvite(_ invite: BuddyInvite, myUID: String) async throws {
        let now = FieldValue.serverTimestamp()
        let inviteRef = db.collection(invitesCollection).document(invite.id)
        let meBuddyRef = db.collection(friendshipsCollection)
            .document(myUID)
            .collection("buddies")
            .document(invite.fromUid)
        let themBuddyRef = db.collection(friendshipsCollection)
            .document(invite.fromUid)
            .collection("buddies")
            .document(myUID)

        let batch = db.batch()
        batch.updateData([
            "status": BuddyInviteStatus.accepted.rawValue,
            "updatedAt": now
        ], forDocument: inviteRef)
        batch.setData([
            "buddyUid": invite.fromUid,
            "displayName": invite.fromDisplayName,
            "friendCode": invite.fromFriendCode,
            "avatarID": "avatar_note",
            "publicLevel": 1,
            "sinceAt": now
        ], forDocument: meBuddyRef, merge: true)
        batch.setData([
            "buddyUid": myUID,
            "displayName": invite.toDisplayName,
            "friendCode": invite.toFriendCode,
            "avatarID": "avatar_note",
            "publicLevel": 1,
            "sinceAt": now
        ], forDocument: themBuddyRef, merge: true)

        try await batch.commit()
    }

    func declineInvite(_ invite: BuddyInvite) async throws {
        try await db.collection(invitesCollection).document(invite.id).updateData([
            "status": BuddyInviteStatus.declined.rawValue,
            "updatedAt": FieldValue.serverTimestamp()
        ])
    }

    private func createPendingInvite(from myProfile: FirebaseUserProfile, to targetProfile: FirebaseUserProfile) async throws {
        let myUID = myProfile.uid
        let targetUID = targetProfile.uid

        let buddyDoc = try await db.collection(friendshipsCollection)
            .document(myUID)
            .collection("buddies")
            .document(targetUID)
            .getDocument()
        if buddyDoc.exists {
            throw FirebaseBuddiesError.alreadyBuddies
        }

        let outboundPending = try await db.collection(invitesCollection)
            .whereField("fromUid", isEqualTo: myUID)
            .whereField("toUid", isEqualTo: targetUID)
            .whereField("status", isEqualTo: BuddyInviteStatus.pending.rawValue)
            .limit(to: 1)
            .getDocuments()
        if !outboundPending.documents.isEmpty {
            throw FirebaseBuddiesError.inviteAlreadySent
        }

        let inboundPending = try await db.collection(invitesCollection)
            .whereField("fromUid", isEqualTo: targetUID)
            .whereField("toUid", isEqualTo: myUID)
            .whereField("status", isEqualTo: BuddyInviteStatus.pending.rawValue)
            .limit(to: 1)
            .getDocuments()
        if !inboundPending.documents.isEmpty {
            throw FirebaseBuddiesError.inviteAlreadyReceived
        }

        try await db.collection(invitesCollection).document().setData([
            "fromUid": myUID,
            "toUid": targetUID,
            "fromDisplayName": myProfile.displayName,
            "fromFriendCode": myProfile.friendCode,
            "toDisplayName": targetProfile.displayName,
            "toFriendCode": targetProfile.friendCode,
            "status": BuddyInviteStatus.pending.rawValue,
            "createdAt": FieldValue.serverTimestamp(),
            "updatedAt": FieldValue.serverTimestamp()
        ], merge: false)
    }

    private func parseUserProfile(uid: String, data: [String: Any]?) -> FirebaseUserProfile? {
        guard
            let data,
            let displayName = data["displayName"] as? String,
            let friendCode = data["friendCode"] as? String
        else {
            return nil
        }

        return FirebaseUserProfile(
            uid: uid,
            displayName: displayName,
            friendCode: friendCode,
            nameEditUsed: (data["nameEditUsed"] as? Bool) ?? false,
            avatarID: (data["avatarID"] as? String) ?? "avatar_note",
            bio: (data["bio"] as? String) ?? "",
            instrument: (data["instrument"] as? String) ?? "",
            publicLevel: max(1, (data["publicLevel"] as? Int) ?? 1)
        )
    }

    private func parseInvites(from documents: [QueryDocumentSnapshot]) -> [BuddyInvite] {
        documents.compactMap { doc in
            let data = doc.data()
            guard
                let fromUid = data["fromUid"] as? String,
                let toUid = data["toUid"] as? String,
                let fromDisplayName = data["fromDisplayName"] as? String,
                let fromFriendCode = data["fromFriendCode"] as? String,
                let toDisplayName = data["toDisplayName"] as? String,
                let toFriendCode = data["toFriendCode"] as? String,
                let statusRaw = data["status"] as? String,
                let status = BuddyInviteStatus(rawValue: statusRaw)
            else {
                return nil
            }

            let createdAt = (data["createdAt"] as? Timestamp)?.dateValue() ?? .distantPast
            return BuddyInvite(
                id: doc.documentID,
                fromUid: fromUid,
                toUid: toUid,
                fromDisplayName: fromDisplayName,
                fromFriendCode: fromFriendCode,
                toDisplayName: toDisplayName,
                toFriendCode: toFriendCode,
                status: status,
                createdAt: createdAt
            )
        }
    }

    private func parseBuddies(from documents: [QueryDocumentSnapshot]) -> [BuddySummary] {
        documents.compactMap { doc in
            let data = doc.data()
            guard
                let buddyUID = data["buddyUid"] as? String,
                let displayName = data["displayName"] as? String,
                let friendCode = data["friendCode"] as? String
            else {
                return nil
            }

            let sinceAt = (data["sinceAt"] as? Timestamp)?.dateValue() ?? .distantPast
            return BuddySummary(
                id: buddyUID,
                displayName: displayName,
                friendCode: friendCode,
                sinceAt: sinceAt,
                avatarID: (data["avatarID"] as? String) ?? "avatar_note",
                publicLevel: max(1, (data["publicLevel"] as? Int) ?? 1)
            )
        }
    }

    private func makeFriendCode() -> String {
        let letters = Array("ABCDEFGHJKLMNPQRSTUVWXYZ")
        let numbers = Array("23456789")

        let prefix = String((0..<4).map { _ in letters.randomElement() ?? "A" })
        let suffix = String((0..<4).map { _ in numbers.randomElement() ?? "2" })
        return "\(prefix)-\(suffix)"
    }

    func normalizedDisplayName(from raw: String) -> String {
        let scalars = raw.unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }
        return String(String.UnicodeScalarView(scalars)).prefix(30).description
    }
}

private extension Array {
    func chunked(into size: Int) -> [[Element]] {
        guard size > 0 else { return [self] }
        var index = 0
        var chunks: [[Element]] = []
        while index < count {
            let end = Swift.min(index + size, count)
            chunks.append(Array(self[index..<end]))
            index = end
        }
        return chunks
    }
}
