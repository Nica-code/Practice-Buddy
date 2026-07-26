import Foundation
import FirebaseAuth
import FirebaseFirestore

struct FirebaseUserProfile: Equatable {
    let uid: String
    let displayName: String
    let friendCode: String
    let nameEditUsed: Bool
    let avatarID: String
    let profilePhotoURL: String
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
    let profilePhotoURL: String
    let publicLevel: Int
    let lastPracticedAt: Date?
}

struct FriendChatThread {
    let id: String
    let participants: [String]
    let lastMessageText: String
    let lastMessageAt: Date
    let lastMessageSenderUID: String
}

struct FriendChatMessage: Identifiable {
    let id: String
    let senderUID: String
    let senderName: String
    let senderAvatarID: String
    let senderLevel: Int
    let text: String
    let createdAt: Date
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
    let profilePhotoURL: String
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
    case server(String)

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
        case .invalidDisplayName: return "Use 2-30 characters: letters, numbers, spaces, apostrophes, dots, underscores, or hyphens."
        case .displayNameLocked: return "Name can only be changed once."
        case .server(let message): return message
        }
    }
}

final class FirebaseBuddiesRepository {
    static let minDisplayNameLength = 2
    static let maxDisplayNameLength = 30

    private lazy var db = Firestore.firestore()
    private let usersCollection = "users"
    private let publicProfilesCollection = "publicProfiles"
    private let presenceCollection = "presence"
    private let invitesCollection = "invites"
    private let friendshipsCollection = "friendships"
    private let chatThreadsCollection = "friendChats"

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
            if let preferred = preferredInitialDisplayNameFromAuth(),
               shouldAdoptAuthDisplayName(current: profile.displayName, uid: uid) {
                try await ref.setData([
                    "displayName": preferred,
                    "updatedAt": FieldValue.serverTimestamp()
                ], merge: true)
                return FirebaseUserProfile(
                    uid: uid,
                    displayName: preferred,
                    friendCode: profile.friendCode,
                    nameEditUsed: profile.nameEditUsed,
                    avatarID: profile.avatarID,
                    profilePhotoURL: profile.profilePhotoURL,
                    bio: profile.bio,
                    instrument: profile.instrument,
                    publicLevel: profile.publicLevel
                )
            }
            return profile
        }

        let defaultDisplayName = generatedDefaultDisplayName(for: uid)
        let initialDisplayName = preferredInitialDisplayNameFromAuth() ?? defaultDisplayName

        for _ in 0..<6 {
            let code = makeFriendCode()
            let query = try await db.collection(usersCollection)
                .whereField("friendCode", isEqualTo: code)
                .limit(to: 1)
                .getDocuments()

            if !query.documents.isEmpty { continue }

            try await ref.setData([
                "displayName": initialDisplayName,
                "friendCode": code,
                "nameEditUsed": false,
                "avatarID": "avatar_note",
                "profilePhotoURL": "",
                "bio": "",
                "instrument": "",
                "publicLevel": 1,
                "totalPracticeMinutes": 0,
                "createdAt": FieldValue.serverTimestamp(),
                "updatedAt": FieldValue.serverTimestamp()
            ], merge: true)

            return FirebaseUserProfile(
                uid: uid,
                displayName: initialDisplayName,
                friendCode: code,
                nameEditUsed: false,
                avatarID: "avatar_note",
                profilePhotoURL: "",
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
        db.collection(presenceCollection).document(uid).addSnapshotListener { snap, _ in
            Task { @MainActor in
                let data = snap?.data()
                let stateRaw = (data?["presenceState"] as? String) ?? BuddyPresenceValue.offline.rawValue
                let state = BuddyPresenceValue(rawValue: stateRaw) ?? .offline
                let lastChanged = (data?["presenceLastChanged"] as? Timestamp)?.dateValue() ?? .distantPast
                onChange(BuddyPresenceState(state: state, lastChanged: lastChanged))
            }
        }
    }

    func publishFriendActivity(
        from uid: String,
        to buddyUIDs: [String],
        lastPracticedAt: Date?
    ) async throws {
        let targets = Set(buddyUIDs.filter { !$0.isEmpty && $0 != uid })
        guard !targets.isEmpty else { return }

        let batch = db.batch()
        for buddyUID in targets {
            let projection = db.collection(friendshipsCollection)
                .document(buddyUID)
                .collection("buddies")
                .document(uid)
            if let lastPracticedAt {
                batch.setData([
                    "lastPracticedAt": Timestamp(date: lastPracticedAt)
                ], forDocument: projection, merge: true)
            } else {
                batch.setData([
                    "lastPracticedAt": FieldValue.delete()
                ], forDocument: projection, merge: true)
            }
        }
        try await batch.commit()
    }

    func listenToPublicStats(
        uid: String,
        onChange: @escaping @MainActor (BuddyPublicStats) -> Void
    ) -> ListenerRegistration {
        db.collection(publicProfilesCollection).document(uid).addSnapshotListener { snap, _ in
            Task { @MainActor in
                let data = snap?.data()
                let level = max(1, (data?["publicLevel"] as? Int) ?? 1)
                let leagueRaw = ((data?["duelLeague"] as? String) ?? "bronze").trimmingCharacters(in: .whitespacesAndNewlines)
                let league = leagueRaw.isEmpty ? "Bronze" : leagueRaw.capitalized
                let rating = max(0, (data?["duelRating"] as? Int) ?? 0)
                onChange(
                    BuddyPublicStats(
                        publicLevel: level,
                        duelLeague: league,
                        duelRating: rating,
                        profilePhotoURL: (data?["profilePhotoURL"] as? String) ?? ""
                    )
                )
            }
        }
    }

    func fetchPublicStats(forUIDs uids: [String]) async throws -> [String: BuddyPublicStats] {
        let unique = Array(Set(uids))
        guard !unique.isEmpty else { return [:] }

        var output: [String: BuddyPublicStats] = [:]
        for chunk in unique.chunked(into: 10) {
            let snapshot = try await db.collection(publicProfilesCollection)
                .whereField(FieldPath.documentID(), in: chunk)
                .getDocuments()
            for doc in snapshot.documents {
                let data = doc.data()
                let level = max(1, (data["publicLevel"] as? Int) ?? 1)
                let leagueRaw = ((data["duelLeague"] as? String) ?? "bronze").trimmingCharacters(in: .whitespacesAndNewlines)
                let league = leagueRaw.isEmpty ? "Bronze" : leagueRaw.capitalized
                let rating = max(0, (data["duelRating"] as? Int) ?? 0)
                output[doc.documentID] = BuddyPublicStats(
                    publicLevel: level,
                    duelLeague: league,
                    duelRating: rating,
                    profilePhotoURL: (data["profilePhotoURL"] as? String) ?? ""
                )
            }
        }
        return output
    }

    func sendInvite(from myProfile: FirebaseUserProfile, friendCode rawCode: String) async throws -> String {
        let code = rawCode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !code.isEmpty else { throw FirebaseBuddiesError.invalidFriendCode }
        guard let baseURL = AppInfo.duelFunctionsBaseURL,
              let user = Auth.auth().currentUser else {
            throw FirebaseBuddiesError.server("Friend requests are unavailable in this build.")
        }
        let token = try await user.getIDToken()
        var request = URLRequest(url: baseURL.appendingPathComponent("friendInviteByCode"))
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["friendCode": code])
        let (data, response) = try await URLSession.shared.data(for: request)
        let payload = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw FirebaseBuddiesError.server(payload["error"] as? String ?? "Couldn’t send the friend request.")
        }
        guard payload["ok"] as? Bool == true,
              let targetUID = payload["targetUID"] as? String,
              !targetUID.isEmpty else {
            throw FirebaseBuddiesError.server(payload["error"] as? String ?? "Couldn’t send the friend request.")
        }
        _ = myProfile // The server reads the current profile, never the client snapshot.
        return targetUID
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
        let doc = try await db.collection(publicProfilesCollection).document(cleanedUID).getDocument()
        guard let profile = parsePublicUserProfile(uid: cleanedUID, data: doc.data()) else {
            throw FirebaseBuddiesError.profileNotFound
        }
        return profile
    }

    func updateDisplayName(uid: String, rawDisplayName: String) async throws {
        let cleanedRaw = rawDisplayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard Self.isValidDisplayName(cleanedRaw) else {
            throw FirebaseBuddiesError.invalidDisplayName
        }

        let userRef = db.collection(usersCollection).document(uid)
        let snap = try await userRef.getDocument()
        let used = (snap.data()?["nameEditUsed"] as? Bool) ?? false
        if used {
            throw FirebaseBuddiesError.displayNameLocked
        }

        try await db.collection(usersCollection).document(uid).setData([
            "displayName": cleanedRaw,
            "nameEditUsed": true,
            "updatedAt": FieldValue.serverTimestamp()
        ], merge: true)
    }

    func updateProfileDetails(
        uid: String,
        avatarID: String,
        profilePhotoURL: String? = nil,
        rawBio: String,
        rawInstrument: String
    ) async throws {
        let cleanBio = String(rawBio.trimmingCharacters(in: .whitespacesAndNewlines).prefix(160))
        let cleanInstrument = String(rawInstrument.trimmingCharacters(in: .whitespacesAndNewlines).prefix(40))
        let cleanAvatar = avatarID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "avatar_note" : avatarID

        var patch: [String: Any] = [
            "avatarID": cleanAvatar,
            "bio": cleanBio,
            "instrument": cleanInstrument,
            "updatedAt": FieldValue.serverTimestamp()
        ]
        if let profilePhotoURL {
            patch["profilePhotoURL"] = profilePhotoURL.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        try await db.collection(usersCollection).document(uid).setData(patch, merge: true)

        let myProfile = try await db.collection(usersCollection).document(uid).getDocument()
        let displayName = (myProfile.data()?["displayName"] as? String) ?? generatedDefaultDisplayName(for: uid)
        let friendCode = (myProfile.data()?["friendCode"] as? String) ?? ""
        let publicLevel = max(1, (myProfile.data()?["publicLevel"] as? Int) ?? 1)
        let effectivePhotoURL = (patch["profilePhotoURL"] as? String) ?? ((myProfile.data()?["profilePhotoURL"] as? String) ?? "")

        let buddiesSnapshot = try await db.collection(friendshipsCollection)
            .document(uid)
            .collection("buddies")
            .getDocuments()

        let batch = db.batch()
        for doc in buddiesSnapshot.documents {
            let buddyUID = doc.documentID
            let remoteBuddyRef = db.collection(friendshipsCollection)
                .document(buddyUID)
                .collection("buddies")
                .document(uid)
            let patchData: [String: Any] = [
                "displayName": displayName,
                "friendCode": friendCode,
                "avatarID": cleanAvatar,
                "profilePhotoURL": effectivePhotoURL,
                "publicLevel": publicLevel
            ]
            batch.setData(patchData, forDocument: remoteBuddyRef, merge: true)
        }
        if !buddiesSnapshot.documents.isEmpty {
            try await batch.commit()
        }
    }

    func updateAvatarLoadout(uid: String, loadout: AvatarLoadout) async throws {
        let normalizedUID = uid.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedUID.isEmpty else { throw FirebaseBuddiesError.missingCurrentUser }

        var payload: [String: Any] = [
            "version": loadout.version,
            "baseID": loadout.baseID,
            "skinToneID": loadout.skinToneID,
            "hairID": loadout.hairID,
            "outfitID": loadout.outfitID,
            "instrumentID": loadout.instrumentID,
            "poseID": loadout.poseID,
            "roomID": loadout.roomID,
            "roomLayouts": roomLayoutsPayload(loadout.roomLayouts)
        ]
        if let accessoryID = loadout.accessoryID {
            payload["accessoryID"] = accessoryID
        }

        try await db.collection(usersCollection).document(normalizedUID).setData(
            [
                "avatarLoadout": payload,
                // Retain the legacy identifier during the compatibility window.
                "avatarID": loadout.baseID,
                "updatedAt": FieldValue.serverTimestamp()
            ],
            merge: true
        )
    }

    private func roomLayoutsPayload(_ layouts: [String: StudioQuestRoomLayout]) -> [String: Any] {
        Dictionary(uniqueKeysWithValues: layouts.map { roomID, layout in
            let placements: [[String: Any]] = layout.placements.map { placement in
                [
                    "id": placement.id,
                    "decorationID": placement.decorationID,
                    "position": ["x": placement.position.x, "y": placement.position.y],
                    "scale": placement.scale,
                    "rotationDegrees": placement.rotationDegrees,
                    "depth": placement.depth
                ]
            }
            return (roomID, [
                "roomID": layout.roomID,
                "placements": placements,
                "updatedAt": Timestamp(date: layout.updatedAt)
            ])
        })
    }

    func repairLocalBuddyDirectory(uid: String) async throws {
        let buddiesRef = db.collection(friendshipsCollection).document(uid).collection("buddies")
        let buddiesSnapshot = try await buddiesRef.getDocuments()
        if buddiesSnapshot.documents.isEmpty { return }

        let buddyUIDs = buddiesSnapshot.documents.map(\.documentID).filter { !$0.isEmpty }
        let stats = try await fetchPublicStats(forUIDs: buddyUIDs)

        let batch = db.batch()
        for buddyUID in buddyUIDs {
            guard let profile = try? await fetchUserProfile(uid: buddyUID) else { continue }
            let stat = stats[buddyUID]
            let localBuddyRef = buddiesRef.document(buddyUID)
            batch.setData([
                "displayName": profile.displayName,
                "friendCode": profile.friendCode,
                "avatarID": profile.avatarID,
                "profilePhotoURL": profile.profilePhotoURL,
                "publicLevel": max(1, stat?.publicLevel ?? profile.publicLevel)
            ], forDocument: localBuddyRef, merge: true)
        }
        try await batch.commit()
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
            "profilePhotoURL": "",
            "publicLevel": 1,
            "sinceAt": now
        ], forDocument: meBuddyRef, merge: true)
        batch.setData([
            "buddyUid": myUID,
            "displayName": invite.toDisplayName,
            "friendCode": invite.toFriendCode,
            "avatarID": "avatar_note",
            "profilePhotoURL": "",
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

    // MARK: - Friend Chat

    func listenToUserDocument(
        uid: String,
        onChange: @escaping @MainActor ([String: Any]?) -> Void
    ) -> ListenerRegistration {
        db.collection(usersCollection).document(uid).addSnapshotListener { snap, _ in
            Task { @MainActor in
                onChange(snap?.data())
            }
        }
    }

    func listenToBuddyDirectory(
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

    func listenToFriendChatThreads(
        uid: String,
        onChange: @escaping @MainActor ([FriendChatThread]) -> Void
    ) -> ListenerRegistration {
        db.collection(chatThreadsCollection)
            .whereField("participants", arrayContains: uid)
            .addSnapshotListener { snap, _ in
                Task { @MainActor in
                    let rows = (snap?.documents ?? []).compactMap { self.parseFriendChatThread(doc: $0) }
                    onChange(rows)
                }
            }
    }

    func friendThreadID(uidA: String, uidB: String) -> String {
        [uidA, uidB].sorted().joined(separator: "__")
    }

    func ensureFriendThread(currentUID: String, friendUID: String) async throws {
        let threadID = friendThreadID(uidA: currentUID, uidB: friendUID)
        let ref = db.collection(chatThreadsCollection).document(threadID)
        // Avoid pre-read: missing docs can fail read rules before first message exists.
        try await ref.setData([
            "participants": [currentUID, friendUID],
            "lastMessageText": "",
            "lastMessageAt": FieldValue.serverTimestamp(),
            "lastMessageSenderUID": "",
            "createdAt": FieldValue.serverTimestamp()
        ], merge: true)
    }

    func sendFriendMessage(
        senderUID: String,
        recipientUID: String,
        senderName: String,
        senderAvatarID: String,
        senderLevel: Int,
        rawText: String
    ) async throws {
        let text = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        let threadID = friendThreadID(uidA: senderUID, uidB: recipientUID)
        let threadRef = db.collection(chatThreadsCollection).document(threadID)

        // setData(merge: true) creates the doc on first send and updates it on subsequent sends —
        // no getDocument() read required. participants/createdAt are idempotent on re-merge.
        try await threadRef.setData([
            "participants": [senderUID, recipientUID],
            "lastMessageText": text,
            "lastMessageAt": FieldValue.serverTimestamp(),
            "lastMessageSenderUID": senderUID,
            "createdAt": FieldValue.serverTimestamp()
        ], merge: true)

        try await threadRef.collection("messages").document().setData([
            "senderUid": senderUID,
            "senderName": senderName,
            "senderAvatarID": senderAvatarID,
            "senderLevel": senderLevel,
            "text": text,
            "createdAt": FieldValue.serverTimestamp()
        ])
    }

    func listenToFriendMessages(
        threadID: String,
        onChange: @escaping @MainActor ([FriendChatMessage]) -> Void
    ) -> ListenerRegistration {
        db.collection(chatThreadsCollection)
            .document(threadID)
            .collection("messages")
            .order(by: "createdAt", descending: false)
            .limit(to: 200)
            .addSnapshotListener { snap, _ in
                Task { @MainActor in
                    let rows = (snap?.documents ?? []).compactMap { self.parseFriendChatMessage(doc: $0) }
                    onChange(rows)
                }
            }
    }

    private func parseFriendChatThread(doc: QueryDocumentSnapshot) -> FriendChatThread? {
        let data = doc.data()
        guard let participants = data["participants"] as? [String] else { return nil }
        return FriendChatThread(
            id: doc.documentID,
            participants: participants,
            lastMessageText: (data["lastMessageText"] as? String) ?? "",
            lastMessageAt: (data["lastMessageAt"] as? Timestamp)?.dateValue() ?? .distantPast,
            lastMessageSenderUID: (data["lastMessageSenderUID"] as? String) ?? ""
        )
    }

    private func parseFriendChatMessage(doc: QueryDocumentSnapshot) -> FriendChatMessage? {
        let data = doc.data()
        let senderUID = (data["senderUid"] as? String) ?? (data["senderUID"] as? String)
        guard let senderUID,
              let text = data["text"] as? String else { return nil }
        return FriendChatMessage(
            id: doc.documentID,
            senderUID: senderUID,
            senderName: (data["senderName"] as? String) ?? "Player",
            senderAvatarID: (data["senderAvatarID"] as? String) ?? "avatar_note",
            senderLevel: max(1, (data["senderLevel"] as? Int) ?? 1),
            text: text,
            createdAt: (data["createdAt"] as? Timestamp)?.dateValue() ?? .distantPast
        )
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
            profilePhotoURL: (data["profilePhotoURL"] as? String) ?? "",
            bio: (data["bio"] as? String) ?? "",
            instrument: (data["instrument"] as? String) ?? "",
            publicLevel: max(1, (data["publicLevel"] as? Int) ?? 1)
        )
    }

    /// A public profile intentionally cannot reveal a friend code, birth date,
    /// entitlement, settings, or private practice data. Existing invite flows
    /// receive an empty code until their server-authoritative migration runs.
    private func parsePublicUserProfile(uid: String, data: [String: Any]?) -> FirebaseUserProfile? {
        guard let data, let displayName = data["displayName"] as? String else { return nil }
        return FirebaseUserProfile(
            uid: uid,
            displayName: displayName,
            friendCode: "",
            nameEditUsed: true,
            avatarID: (data["avatarID"] as? String) ?? "avatar_note",
            profilePhotoURL: (data["profilePhotoURL"] as? String) ?? "",
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
                profilePhotoURL: (data["profilePhotoURL"] as? String) ?? "",
                publicLevel: max(1, (data["publicLevel"] as? Int) ?? 1),
                lastPracticedAt: (data["lastPracticedAt"] as? Timestamp)?.dateValue()
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
        Self.normalizedDisplayName(from: raw)
    }

    static func normalizedDisplayName(from raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let allowedSpecial = CharacterSet(charactersIn: " ._'-")
        let scalars = trimmed.unicodeScalars.filter {
            CharacterSet.alphanumerics.contains($0) || allowedSpecial.contains($0)
        }
        let filtered = String(String.UnicodeScalarView(scalars))
        let collapsedSpaces = filtered.replacingOccurrences(
            of: "\\s+",
            with: " ",
            options: .regularExpression
        )
        let cleaned = collapsedSpaces.trimmingCharacters(in: CharacterSet(charactersIn: " ._'-"))
        return String(cleaned.prefix(Self.maxDisplayNameLength))
    }

    static func isValidDisplayName(_ raw: String) -> Bool {
        let cleaned = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard cleaned == raw else { return false }
        guard (Self.minDisplayNameLength...Self.maxDisplayNameLength).contains(cleaned.count) else { return false }
        guard cleaned.matches(pattern: "^[\\p{L}\\p{N}._'\\- ]+$") else { return false }
        guard cleaned.unicodeScalars.contains(where: { CharacterSet.alphanumerics.contains($0) }) else { return false }
        return true
    }

    private func preferredInitialDisplayNameFromAuth() -> String? {
        guard let raw = Auth.auth().currentUser?.displayName else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if Self.isValidDisplayName(trimmed) {
            return trimmed
        }

        let normalized = Self.normalizedDisplayName(from: trimmed)
        guard Self.isValidDisplayName(normalized) else { return nil }
        return normalized
    }

    private func shouldAdoptAuthDisplayName(current: String, uid: String) -> Bool {
        let trimmed = current.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return true }
        return trimmed == generatedDefaultDisplayName(for: uid)
    }

    private func generatedDefaultDisplayName(for uid: String) -> String {
        "Player\(uid.prefix(4).uppercased())"
    }
}

private extension String {
    func matches(pattern: String) -> Bool {
        range(of: pattern, options: .regularExpression) != nil
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
